import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../domain/models.dart';
import 'backend/api_client.dart';
import 'backend/remote_hotel.dart';
import 'seed.dart';

/// Business rule violation, already worded for the UI.
class DomainException implements Exception {
  final String message;

  const DomainException(this.message);

  @override
  String toString() => message;
}

class RoomNotReadyException extends DomainException {
  final int etaMinutes;
  final List<Room> alternatives;

  const RoomNotReadyException(super.message, {required this.etaMinutes, this.alternatives = const []});
}

class PendingChargesException extends DomainException {
  final double balance;

  const PendingChargesException(super.message, this.balance);
}

class PaymentDeclinedException extends DomainException {
  const PaymentDeclinedException(super.message);
}

class CardInfo {
  final String number;
  final String holder;
  final String expiry;
  final String cvv;

  const CardInfo({required this.number, required this.holder, required this.expiry, required this.cvv});

  String get digits => number.replaceAll(RegExp(r'\D'), '');

  String get masked => 'Tarjeta •••• ${digits.length >= 4 ? digits.substring(digits.length - 4) : digits}';
}

class Period {
  final DateTime start;
  final DateTime end;

  const Period(this.start, this.end);

  bool contains(DateTime value) => !value.isBefore(start) && !value.isAfter(end);

  factory Period.lastDays(DateTime now, int days) =>
      Period(DateUtils.dateOnly(now).subtract(Duration(days: days - 1)), now);
}

class StaffProductivity {
  final AppUser user;
  final int completed;
  final int pending;
  final double avgMinutes;

  const StaffProductivity(this.user, this.completed, this.pending, this.avgMinutes);
}

class AreaStats {
  final Area area;
  final int completed;
  final int pending;
  final int delayed;
  final double avgMinutes;

  const AreaStats(this.area, this.completed, this.pending, this.delayed, this.avgMinutes);
}

class TrendPoint {
  final DateTime weekStart;
  final double cleaningMinutes;
  final double incidentHours;

  const TrendPoint(this.weekStart, this.cleaningMinutes, this.incidentHours);
}

/// In-memory hotel operation shared by every screen.
///
/// It plays the role of the backend for the demo: every change notifies the
/// listeners, so boards and panels refresh without reloading (US-04, US-18).
/// Replace its methods with API calls once RoomTrack has its own backend.
class HotelStore extends ChangeNotifier {
  HotelStore({DateTime Function()? clock, bool seed = true}) : _clock = clock ?? DateTime.now {
    if (seed) {
      seedDemoData(this);
    } else {
      seedCatalog(this);
    }
  }

  /// With `--dart-define=API_BASE_URL=...` the hotel comes from the backend instead of the demo data.
  static final HotelStore instance = _create();

  static HotelStore _create() {
    final store = HotelStore(seed: !backendEnabled);
    if (backendEnabled) store.remote = RemoteHotel(store, ApiClient());
    return store;
  }

  /// The backend, when the app is connected to one.
  RemoteHotel? remote;

  bool get isRemote => remote != null;

  /// Lets the backend sync tell the screens that the data changed.
  void refresh() => notifyListeners();

  /// Housekeeping and maintenance still live on the device: their effect on a room goes to the backend.
  void _pushRoom(Room room) => remote?.pushRoomStatus(room);

  final DateTime Function() _clock;
  DateTime get now => _clock();

  bool autoAssignCleaning = true;
  Duration criticalIncidentLimit = const Duration(minutes: 30);
  Duration overdueTaskLimit = const Duration(minutes: 60);
  Duration arrivalWarning = const Duration(hours: 3);

  /// Similar incidents in a month after which a new one is flagged as a pattern (US-10).
  int recurrenceThreshold = 3;

  final List<AppUser> users = [];
  final List<Room> rooms = [];
  final List<CleaningTask> tasks = [];
  final List<Incident> incidents = [];
  final List<GuestRequest> requests = [];
  final List<Stay> stays = [];
  final List<Payment> payments = [];
  final List<Receipt> receipts = [];
  final List<AppNotification> notifications = [];
  final List<OperationalAlert> alerts = [];
  final List<ChatMessage> messages = [];
  final List<Rating> ratings = [];
  final List<ServiceItem> services = [];
  final List<PreventiveTask> preventiveTasks = [];
  final List<Shift> shifts = [];
  final List<ShiftSwap> swaps = [];
  final List<Handover> handovers = [];
  final List<ReportSchedule> schedules = [];
  final List<OutboxEmail> outbox = [];
  final Map<String, int> _resetTokens = {};
  final Random _random = Random();

  // Local ids start far from the backend ones, so both can live in the same lists.
  int _seq = 1000000;
  int nextId() => ++_seq;

  AppUser? currentUser;
  Timer? _ticker;

  void startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 30), (_) => runChecks());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  AppUser? userById(int? id) => id == null ? null : users.where((u) => u.id == id).firstOrNull;
  Room roomById(int id) => rooms.firstWhere((r) => r.id == id);
  Stay stayById(int id) => stays.firstWhere((s) => s.id == id);
  CleaningTask taskById(int id) => tasks.firstWhere((t) => t.id == id);
  Incident incidentById(int id) => incidents.firstWhere((i) => i.id == id);
  GuestRequest requestById(int id) => requests.firstWhere((r) => r.id == id);

  String userName(int? id) => userById(id)?.name ?? 'Sin asignar';

  List<AppUser> staffOf(UserRole role, {bool onlyActive = true}) =>
      users.where((u) => u.role == role && (!onlyActive || u.active)).toList();

  List<int> get floors => (rooms.map((r) => r.floor).toSet().toList()..sort());

  // ---------------------------------------------------------------------------
  // US-01 / US-02 / US-03 Authentication, profile and staff accounts
  // ---------------------------------------------------------------------------

  AppUser signIn(String email, String password) {
    final user = _userByEmail(email);
    if (user == null || user.password != password) {
      throw const DomainException('Correo o contraseña incorrectos.');
    }
    if (!user.active) {
      throw const DomainException('Tu cuenta está desactivada. Contacta al administrador.');
    }
    currentUser = user;
    notifyListeners();
    return user;
  }

  void signOut() {
    currentUser = null;
    notifyListeners();
  }

  AppUser? _userByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return users.where((u) => u.email.toLowerCase() == normalized).firstOrNull;
  }

  /// Always answers the same way, so nobody can probe which e-mails exist.
  String requestPasswordReset(String email) {
    final user = _userByEmail(email);
    if (user != null) {
      final token = (100000 + _random.nextInt(899999)).toString();
      _resetTokens[token] = user.id;
      _mail(user.email, 'Restablece tu contraseña',
          'Usa este enlace seguro para crear una nueva contraseña: roomtrack://reset?token=$token');
    }
    notifyListeners();
    return 'Si el correo está registrado, te enviamos un enlace seguro para restablecer tu contraseña.';
  }

  /// Demo shortcut that reads the last recovery link from the outbox.
  String? lastResetToken(String email) {
    final mail = outbox.reversed
        .where((m) => m.to.toLowerCase() == email.trim().toLowerCase() && m.subject == 'Restablece tu contraseña')
        .firstOrNull;
    if (mail == null) return null;
    return RegExp(r'token=(\d+)').firstMatch(mail.body)?.group(1);
  }

  void resetPassword(String token, String newPassword) {
    final userId = _resetTokens.remove(token.trim());
    if (userId == null) throw const DomainException('El enlace no es válido o ya fue usado.');
    _validatePassword(newPassword);
    userById(userId)!.password = newPassword;
    notifyListeners();
  }

  AppUser registerGuest({required String name, required String email, required String password}) {
    _validateEmail(email);
    _validatePassword(password);
    if (name.trim().isEmpty) throw const DomainException('Ingresa tu nombre.');
    if (_userByEmail(email) != null) throw const DomainException('Ya existe una cuenta con ese correo.');
    final user = AppUser(
      id: nextId(),
      name: name.trim(),
      email: email.trim(),
      role: UserRole.guest,
      password: password,
    );
    users.add(user);
    for (final stay in stays.where((s) => s.guestEmail.toLowerCase() == user.email.toLowerCase())) {
      stay.guestUserId = user.id;
    }
    notifyListeners();
    return user;
  }

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _validateEmail(String email) {
    if (!_emailPattern.hasMatch(email.trim())) {
      throw const DomainException('El correo no tiene un formato válido.');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 6) throw const DomainException('La contraseña debe tener al menos 6 caracteres.');
  }

  void updateProfile(AppUser user, {required String name, required String email, required String phone, required String photoUrl}) {
    _validateEmail(email);
    if (name.trim().isEmpty) throw const DomainException('El nombre no puede estar vacío.');
    final other = _userByEmail(email);
    if (other != null && other.id != user.id) throw const DomainException('Ese correo ya está en uso.');
    user
      ..name = name.trim()
      ..email = email.trim()
      ..phone = phone.trim()
      ..photoUrl = photoUrl.trim();
    notifyListeners();
  }

  void changePassword(AppUser user, String current, String newPassword) {
    if (user.password != current) throw const DomainException('La contraseña actual no es correcta.');
    _validatePassword(newPassword);
    user.password = newPassword;
    notifyListeners();
  }

  void setNotificationPref(AppUser user, NotificationType type, bool enabled) {
    user.prefs[type] = enabled;
    notifyListeners();
  }

  /// Returns the temporary password e-mailed to the new collaborator.
  String createStaff({required String name, required String email, required String phone, required UserRole role}) {
    if (!role.isStaff) throw const DomainException('Elige un rol del Staff Operativo.');
    _validateEmail(email);
    if (name.trim().isEmpty) throw const DomainException('Ingresa el nombre del colaborador.');
    if (_userByEmail(email) != null) throw const DomainException('Ya existe una cuenta con ese correo.');
    final password = 'RT${100000 + _random.nextInt(899999)}';
    users.add(AppUser(id: nextId(), name: name.trim(), email: email.trim(), phone: phone.trim(), role: role, password: password));
    _mail(email.trim(), 'Tus credenciales de RoomTrack',
        'Hola ${name.trim()}, tu cuenta de ${role.label} está lista. Usuario: ${email.trim()} · Contraseña temporal: $password');
    notifyListeners();
    return password;
  }

  /// Deactivated accounts lose access right away: the shell signs them out.
  void setActive(AppUser user, bool active) {
    if (user.id == currentUser?.id && !active) throw const DomainException('No puedes desactivar tu propia cuenta.');
    user.active = active;
    if (!active) {
      for (final task in tasks.where((t) => t.isOpen && t.assigneeId == user.id)) {
        task.assigneeId = null;
        _autoAssign(task);
      }
    }
    notifyListeners();
  }

  void changeRole(AppUser user, UserRole role) {
    if (!role.isStaff) throw const DomainException('Elige un rol del Staff Operativo.');
    user.role = role;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-04 / US-28 Rooms and availability
  // ---------------------------------------------------------------------------

  bool hasBlockingIncident(int roomId) =>
      incidents.any((i) => i.roomId == roomId && i.isOpen && i.blocksRoom);

  bool isAssignable(Room room) =>
      room.status == RoomStatus.available && !hasBlockingIncident(room.id) && stayInRoom(room.id) == null;

  List<Room> assignableRooms({RoomType? type}) =>
      rooms.where((r) => isAssignable(r) && (type == null || r.type == type)).toList();

  Stay? stayInRoom(int roomId) =>
      stays.where((s) => s.roomId == roomId && s.status == StayStatus.checkedIn).firstOrNull;

  void setRoomStatus(Room room, RoomStatus status) {
    room.status = status;
    notifyListeners();
  }

  /// Minutes until a room of [type] should be ready, used when the guest arrives early.
  int estimateReadyMinutes(RoomType type) {
    final candidates = rooms.where((r) => r.type == type && stayInRoom(r.id) == null);
    var best = 120;
    for (final room in candidates) {
      final task = tasks.where((t) => t.roomId == room.id && t.isOpen).firstOrNull;
      int eta;
      if (room.status == RoomStatus.cleaning && task?.startedAt != null) {
        eta = max(5, 25 - now.difference(task!.startedAt!).inMinutes);
      } else if (room.status == RoomStatus.dirty || room.status == RoomStatus.cleaning) {
        eta = 45;
      } else if (room.status == RoomStatus.maintenance || hasBlockingIncident(room.id)) {
        eta = 90;
      } else {
        eta = 0;
      }
      best = min(best, eta);
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // US-05 / US-06 / US-07 / US-29 Housekeeping
  // ---------------------------------------------------------------------------

  static List<ChecklistItem> checklistFor(RoomType type) {
    final base = [
      ChecklistItem('Cambiar sábanas y fundas'),
      ChecklistItem('Limpiar y desinfectar baño'),
      ChecklistItem('Aspirar y trapear piso'),
      ChecklistItem('Reponer amenities'),
      ChecklistItem('Vaciar papeleras'),
      ChecklistItem('Revisar minibar', required: false),
    ];
    return switch (type) {
      RoomType.standard => base,
      RoomType.twin => [...base, ChecklistItem('Tender ambas camas')],
      RoomType.suite => [
          ...base,
          ChecklistItem('Limpiar jacuzzi'),
          ChecklistItem('Ordenar sala de estar'),
          ChecklistItem('Reponer minibar completo'),
          ChecklistItem('Colocar arreglo de bienvenida', required: false),
        ],
    };
  }

  CleaningTask createCleaningTask(int roomId, {Priority priority = Priority.normal, int? assigneeId}) {
    final existing = tasks.where((t) => t.roomId == roomId && t.isOpen).firstOrNull;
    if (existing != null) return existing;
    final room = roomById(roomId);
    final task = CleaningTask(
      id: nextId(),
      roomId: roomId,
      checklist: checklistFor(room.type),
      createdAt: now,
      priority: priority,
    );
    task.events.add(TimelineEvent(now, 'Tarea creada con prioridad ${priority.label.toLowerCase()}'));
    tasks.add(task);
    if (room.status == RoomStatus.available) room.status = RoomStatus.dirty;
    _pushRoom(room);
    if (assigneeId != null) {
      _assign(task, assigneeId);
    } else {
      _autoAssign(task);
    }
    notifyListeners();
    return task;
  }

  int openLoad(int userId) =>
      tasks.where((t) => t.isOpen && t.assigneeId == userId).length +
      incidents.where((i) => i.isOpen && i.assigneeId == userId).length;

  AppUser? _leastLoaded(UserRole role) {
    final candidates = staffOf(role);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => openLoad(a.id).compareTo(openLoad(b.id)));
    return candidates.first;
  }

  void _autoAssign(CleaningTask task) {
    if (!autoAssignCleaning || task.assigneeId != null) return;
    final user = _leastLoaded(UserRole.housekeeping);
    if (user != null) _assign(task, user.id, automatic: true);
  }

  void _assign(CleaningTask task, int userId, {bool automatic = false}) {
    final previous = task.assigneeId;
    task.assigneeId = userId;
    final room = roomById(task.roomId);
    task.events.add(TimelineEvent(
      now,
      previous == null
          ? '${automatic ? 'Asignada automáticamente' : 'Asignada'} a ${userName(userId)}'
          : 'Reasignada de ${userName(previous)} a ${userName(userId)}',
    ));
    _notify(userId, 'Nueva tarea de limpieza', 'Habitación ${room.number} · prioridad ${task.priority.label.toLowerCase()}',
        NotificationType.task, urgent: task.priority == Priority.urgent);
    if (previous != null && previous != userId) {
      _notify(previous, 'Tarea reasignada', 'La habitación ${room.number} ya no está en tu lista.', NotificationType.task);
    }
  }

  void assignTask(int taskId, int userId) {
    final task = taskById(taskId);
    if (!task.isOpen) throw const DomainException('La tarea ya está cerrada.');
    if (task.assigneeId == userId) return;
    _assign(task, userId);
    notifyListeners();
  }

  void setTaskPriority(int taskId, Priority priority) {
    final task = taskById(taskId);
    if (task.priority == priority) return;
    task.priority = priority;
    task.events.add(TimelineEvent(now, 'Prioridad cambiada a ${priority.label.toLowerCase()}'));
    if (task.assigneeId != null) {
      final room = roomById(task.roomId);
      _notify(
        task.assigneeId!,
        priority == Priority.urgent ? '¡Tarea urgente!' : 'Prioridad actualizada',
        'Habitación ${room.number} ahora es ${priority.label.toLowerCase()}',
        NotificationType.priority,
        urgent: priority == Priority.urgent,
      );
    }
    notifyListeners();
  }

  /// Open tasks of a collaborator, most urgent and oldest first (US-06, US-29).
  List<CleaningTask> tasksFor(int userId, {bool onlyCritical = false}) {
    final list = tasks
        .where((t) => t.isOpen && t.assigneeId == userId && (!onlyCritical || t.priority.isCritical))
        .toList();
    list.sort(_byPriorityThenDate);
    return list;
  }

  static int _byPriorityThenDate(CleaningTask a, CleaningTask b) {
    final byPriority = b.priority.index.compareTo(a.priority.index);
    return byPriority != 0 ? byPriority : a.createdAt.compareTo(b.createdAt);
  }

  List<CleaningTask> get openTasks => tasks.where((t) => t.isOpen).toList()..sort(_byPriorityThenDate);

  void startTask(int taskId) {
    final task = taskById(taskId);
    if (task.status != TaskStatus.pending) return;
    task
      ..status = TaskStatus.inProgress
      ..startedAt = now
      ..events.add(TimelineEvent(now, 'Limpieza iniciada por ${userName(task.assigneeId)}'));
    roomById(task.roomId).status = RoomStatus.cleaning;
    _pushRoom(roomById(task.roomId));
    notifyListeners();
  }

  void toggleChecklistItem(int taskId, int index, bool done) {
    taskById(taskId).checklist[index].done = done;
    notifyListeners();
  }

  void completeTask(int taskId) {
    final task = taskById(taskId);
    final missing = task.missingRequired;
    if (missing.isNotEmpty) {
      throw DomainException('Completa los ítems obligatorios:\n• ${missing.map((m) => m.label).join('\n• ')}');
    }
    task
      ..status = TaskStatus.done
      ..startedAt ??= now
      ..completedAt = now
      ..events.add(TimelineEvent(now, 'Habitación marcada como limpia'));
    final room = roomById(task.roomId);
    room.status = hasBlockingIncident(room.id) ? RoomStatus.maintenance : RoomStatus.available;
    _pushRoom(room);
    _notifyRole(UserRole.reception, 'Habitación lista', 'La habitación ${room.number} está limpia y disponible.', NotificationType.task);
    notifyListeners();
  }

  /// Damage found while cleaning becomes an incident for maintenance (US-06).
  Incident reportImpediment(int taskId, {required String description, required Priority urgency, required int reporterId}) {
    final task = taskById(taskId);
    task.events.add(TimelineEvent(now, 'Impedimento reportado: $description'));
    return createIncident(
      roomId: task.roomId,
      title: 'Desperfecto detectado en limpieza',
      description: description,
      category: 'General',
      urgency: urgency,
      reporterId: reporterId,
    );
  }

  // ---------------------------------------------------------------------------
  // US-08 / US-09 / US-10 / US-30 Incidents and maintenance
  // ---------------------------------------------------------------------------

  static const List<String> incidentCategories = [
    'Plomería',
    'Electricidad',
    'Aire acondicionado',
    'Mobiliario',
    'Cerrajería',
    'General',
  ];

  Incident createIncident({
    required int roomId,
    required String title,
    required String description,
    required String category,
    required Priority urgency,
    required int reporterId,
    bool blocksRoom = true,
    bool preventive = false,
  }) {
    if (title.trim().isEmpty) throw const DomainException('Describe brevemente la incidencia.');
    final room = roomById(roomId);
    final incident = Incident(
      id: nextId(),
      roomId: roomId,
      title: title.trim(),
      description: description.trim(),
      category: category,
      urgency: urgency,
      reportedById: reporterId,
      createdAt: now,
      blocksRoom: blocksRoom && !preventive,
      preventive: preventive,
    );
    incident.events.add(TimelineEvent(now, 'Reportada por ${userName(reporterId)} · ${urgency.label}'));

    final monthAgo = now.subtract(const Duration(days: 30));
    final similar = incidents.where((i) =>
        i.roomId == roomId && !i.preventive && i.category == category && i.createdAt.isAfter(monthAgo));
    if (!preventive && similar.length >= recurrenceThreshold) {
      incident.recurring = true;
      _raiseAlert('recurrence-$roomId-$category', 'Problema recurrente en la habitación ${room.number}',
          '${similar.length + 1} incidencias de $category en los últimos 30 días. Considera mantenimiento preventivo.');
    }

    final technician = _leastLoaded(UserRole.maintenance);
    incident.assigneeId = technician?.id;
    incidents.add(incident);

    if (incident.blocksRoom && room.status != RoomStatus.occupied) room.status = RoomStatus.maintenance;
    _pushRoom(room);

    for (final user in staffOf(UserRole.maintenance)) {
      _notify(user.id, preventive ? 'Mantenimiento preventivo' : 'Nueva incidencia',
          'Hab. ${room.number}: ${incident.title} (${urgency.label})', NotificationType.incident,
          urgent: urgency == Priority.urgent);
    }
    notifyListeners();
    return incident;
  }

  List<Incident> incidentsFor(int userId) {
    final list = incidents.where((i) => i.isOpen && i.assigneeId == userId).toList();
    list.sort(_incidentOrder);
    return list;
  }

  List<Incident> get openIncidents => incidents.where((i) => i.isOpen).toList()..sort(_incidentOrder);

  static int _incidentOrder(Incident a, Incident b) {
    final byUrgency = b.urgency.index.compareTo(a.urgency.index);
    return byUrgency != 0 ? byUrgency : a.createdAt.compareTo(b.createdAt);
  }

  void assignIncident(int incidentId, int userId) {
    final incident = incidentById(incidentId);
    incident.assigneeId = userId;
    incident.events.add(TimelineEvent(now, 'Asignada a ${userName(userId)}'));
    _notify(userId, 'Incidencia asignada', 'Hab. ${roomById(incident.roomId).number}: ${incident.title}', NotificationType.incident);
    notifyListeners();
  }

  void startIncident(int incidentId) {
    final incident = incidentById(incidentId);
    if (incident.status != WorkStatus.pending) return;
    incident.status = WorkStatus.inProgress;
    incident.events.add(TimelineEvent(now, 'En proceso por ${userName(incident.assigneeId)}'));
    _notify(incident.reportedById, 'Incidencia en proceso', 'Hab. ${roomById(incident.roomId).number}: ${incident.title}',
        NotificationType.incident);
    notifyListeners();
  }

  void resolveIncident(int incidentId, String notes) {
    if (notes.trim().isEmpty) throw const DomainException('Agrega observaciones sobre la solución.');
    final incident = incidentById(incidentId);
    incident
      ..status = WorkStatus.resolved
      ..resolvedAt = now
      ..resolutionNotes = notes.trim()
      ..events.add(TimelineEvent(now, 'Resuelta: ${notes.trim()}'));
    final room = roomById(incident.roomId);
    if (room.status == RoomStatus.maintenance && !hasBlockingIncident(room.id)) {
      room.status = RoomStatus.dirty;
      _pushRoom(room);
      createCleaningTask(room.id, priority: Priority.high);
    }
    _notify(incident.reportedById, 'Incidencia resuelta', 'Hab. ${room.number}: ${incident.title}', NotificationType.incident);
    _resolveAlert('incident-${incident.id}', 'Incidencia resuelta');
    notifyListeners();
  }

  /// Corrective and preventive history of a room, newest first (US-10, US-30).
  List<Incident> roomHistory(int roomId) =>
      incidents.where((i) => i.roomId == roomId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool roomHasRecurringPattern(int roomId) {
    final monthAgo = now.subtract(const Duration(days: 30));
    final counts = <String, int>{};
    for (final i in incidents.where((i) => i.roomId == roomId && !i.preventive && i.createdAt.isAfter(monthAgo))) {
      counts[i.category] = (counts[i.category] ?? 0) + 1;
    }
    return counts.values.any((count) => count > recurrenceThreshold);
  }

  PreventiveTask schedulePreventive({required String title, required int roomId, required int frequencyDays, required DateTime firstDue}) {
    if (title.trim().isEmpty) throw const DomainException('Describe la tarea preventiva.');
    if (frequencyDays < 1) throw const DomainException('La frecuencia debe ser de al menos un día.');
    final task = PreventiveTask(id: nextId(), title: title.trim(), roomId: roomId, frequencyDays: frequencyDays, nextDue: firstDue);
    preventiveTasks.add(task);
    runChecks();
    return task;
  }

  // ---------------------------------------------------------------------------
  // US-11 / US-19 / US-33 Guest requests and services
  // ---------------------------------------------------------------------------

  GuestRequest createRequest({
    required int roomId,
    required String description,
    required Area area,
    required int createdById,
    int? stayId,
  }) {
    if (description.trim().isEmpty) throw const DomainException('Describe la solicitud.');
    final request = GuestRequest(
      id: nextId(),
      roomId: roomId,
      stayId: stayId,
      description: description.trim(),
      area: area,
      createdAt: now,
      etaMinutes: area.etaMinutes,
      createdById: createdById,
    );
    request.events.add(TimelineEvent(now, 'Registrada y derivada a ${area.label}'));
    requests.add(request);
    final room = roomById(roomId);
    _notifyRole(area.role, 'Nueva solicitud · Hab. ${room.number}', request.description, NotificationType.request);
    notifyListeners();
    return request;
  }

  void deriveRequest(int requestId, Area area) {
    final request = requestById(requestId);
    request.area = area;
    request.events.add(TimelineEvent(now, 'Derivada a ${area.label}'));
    _notifyRole(area.role, 'Solicitud derivada · Hab. ${roomById(request.roomId).number}', request.description,
        NotificationType.request);
    notifyListeners();
  }

  void updateRequestStatus(int requestId, WorkStatus status) {
    final request = requestById(requestId);
    request.status = status;
    request.events.add(TimelineEvent(now, 'Estado: ${status.label}'));
    if (status == WorkStatus.resolved) request.resolvedAt = now;
    final guestId = request.stayId == null ? null : stayById(request.stayId!).guestUserId;
    if (guestId != null) {
      _notify(guestId, status == WorkStatus.resolved ? 'Solicitud atendida' : 'Solicitud en proceso', request.description,
          NotificationType.stay);
    }
    notifyListeners();
  }

  List<GuestRequest> requestsForStay(int stayId) =>
      requests.where((r) => r.stayId == stayId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  GuestRequest requestService(int stayId, int serviceId) {
    final stay = stayById(stayId);
    final service = services.firstWhere((s) => s.id == serviceId);
    if (!service.available) throw const DomainException('Este servicio no está disponible por ahora.');
    if (stay.status != StayStatus.checkedIn || stay.roomId == null) {
      throw const DomainException('Podrás solicitar servicios cuando completes tu check-in.');
    }
    if (service.price > 0) {
      stay.charges.add(FolioCharge(id: nextId(), description: service.name, amount: service.price, createdAt: now));
    }
    return createRequest(
      roomId: stay.roomId!,
      description: 'Servicio: ${service.name}',
      area: service.area,
      createdById: stay.guestUserId ?? 0,
      stayId: stayId,
    );
  }

  // ---------------------------------------------------------------------------
  // US-12 / US-20 Messaging
  // ---------------------------------------------------------------------------

  static String taskChannel(int taskId) => 'task:$taskId';
  static String areaChannel(Area area) => 'area:${area.name}';
  static String guestChannel(int stayId) => 'guest:$stayId';

  List<ChatMessage> messagesIn(String channel) => messages.where((m) => m.channel == channel).toList();

  void sendMessage(String channel, AppUser author, String text) {
    if (text.trim().isEmpty) return;
    messages.add(ChatMessage(
      id: nextId(),
      channel: channel,
      authorId: author.id,
      authorName: author.name,
      text: text.trim(),
      createdAt: now,
    ));
    final parts = channel.split(':');
    final title = 'Mensaje de ${author.firstName}';
    switch (parts.first) {
      case 'task':
        final task = taskById(int.parse(parts[1]));
        task.events.add(TimelineEvent(now, '${author.firstName} comentó: ${text.trim()}'));
        final targets = {task.assigneeId, ...messagesIn(channel).map((m) => m.authorId)}..remove(author.id);
        for (final id in targets.whereType<int>()) {
          _notify(id, title, text.trim(), NotificationType.message);
        }
      case 'area':
        final area = Area.values.byName(parts[1]);
        for (final user in staffOf(area.role).where((u) => u.id != author.id)) {
          _notify(user.id, '$title · canal ${area.label}', text.trim(), NotificationType.message);
        }
      case 'guest':
        final stay = stayById(int.parse(parts[1]));
        if (author.role == UserRole.guest) {
          _notifyRole(UserRole.reception, 'Huésped ${stay.guestName}', text.trim(), NotificationType.message);
        } else if (stay.guestUserId != null) {
          _notify(stay.guestUserId!, 'Recepción respondió', text.trim(), NotificationType.message);
        }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-13 / US-14 / US-27 Stays
  // ---------------------------------------------------------------------------

  Stay? activeStayOf(int userId) {
    final mine = stays.where((s) => s.guestUserId == userId).toList()..sort((a, b) => b.checkIn.compareTo(a.checkIn));
    return mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull;
  }

  List<Stay> get arrivalsToday {
    final today = DateUtils.dateOnly(now);
    return stays
        .where((s) => s.status == StayStatus.reserved || s.status == StayStatus.checkInInProgress)
        .where((s) => !DateUtils.dateOnly(s.checkIn).isAfter(today))
        .toList();
  }

  List<Stay> get inHouse => stays.where((s) => s.status == StayStatus.checkedIn).toList();

  List<Stay> get upcoming => stays
      .where((s) => s.status == StayStatus.reserved && DateUtils.dateOnly(s.checkIn).isAfter(DateUtils.dateOnly(now)))
      .toList();

  Stay createReservation({
    required String guestName,
    required String guestEmail,
    required RoomType type,
    required int nights,
    DateTime? checkIn,
  }) {
    if (guestName.trim().isEmpty) throw const DomainException('Ingresa el nombre del huésped.');
    _validateEmail(guestEmail);
    if (nights < 1) throw const DomainException('La estancia debe ser de al menos una noche.');
    final start = checkIn ?? DateTime(now.year, now.month, now.day, 15);
    final stay = Stay(
      id: nextId(),
      guestName: guestName.trim(),
      guestEmail: guestEmail.trim(),
      roomType: type,
      checkIn: start,
      checkOut: DateTime(start.year, start.month, start.day + nights, 12),
      guestUserId: _userByEmail(guestEmail)?.id,
    );
    stay.charges.add(_roomCharge(stay, nights));
    stays.add(stay);
    notifyListeners();
    return stay;
  }

  FolioCharge _roomCharge(Stay stay, int nights) => FolioCharge(
        id: nextId(),
        description: 'Cargo de habitación · $nights ${nights == 1 ? 'noche' : 'noches'}',
        amount: stay.roomType.nightlyRate * nights,
        createdAt: now,
      );

  void startDigitalCheckIn(int stayId, String documentId) {
    final stay = stayById(stayId);
    if (stay.status != StayStatus.reserved) throw const DomainException('Esta reserva ya inició su check-in.');
    if (documentId.trim().length < 6) throw const DomainException('Ingresa un documento de identidad válido.');
    stay
      ..documentId = documentId.trim()
      ..digital = true
      ..status = StayStatus.checkInInProgress;
    notifyListeners();
  }

  /// Arrival at the hotel after the digital check-in: identity check, room and access code (US-13).
  Stay confirmArrival(int stayId, String documentId) {
    final stay = stayById(stayId);
    if (stay.status != StayStatus.checkInInProgress) throw const DomainException('Primero completa tu check-in digital.');
    if (stay.depositHeld < stay.depositRequired) {
      throw const DomainException('Paga el depósito de garantía para habilitar tu check-in.');
    }
    if (documentId.trim() != stay.documentId) {
      throw const DomainException('El documento no coincide con el registrado en tu check-in.');
    }
    final room = stay.roomId != null ? roomById(stay.roomId!) : assignableRooms(type: stay.roomType).firstOrNull;
    if (room == null || !isAssignable(room)) {
      final eta = estimateReadyMinutes(stay.roomType);
      throw RoomNotReadyException(
        'Tu habitación aún no está lista. Tiempo estimado de espera: $eta minutos.',
        etaMinutes: eta,
      );
    }
    _occupy(stay, room);
    return stay;
  }

  /// Reception check-in for guests who skip the digital flow (US-27, US-28).
  Stay assistedCheckIn(int stayId, int roomId, {required int receptionistId, String documentId = ''}) {
    final stay = stayById(stayId);
    if (stay.status == StayStatus.checkedIn || stay.status == StayStatus.checkedOut) {
      throw const DomainException('Este huésped ya hizo check-in.');
    }
    final room = roomById(roomId);
    if (!isAssignable(room)) {
      final sameType = assignableRooms(type: stay.roomType);
      throw RoomNotReadyException(
        'La habitación ${room.number} no está disponible (${room.status.label.toLowerCase()}).',
        etaMinutes: estimateReadyMinutes(stay.roomType),
        alternatives: sameType.isNotEmpty ? sameType : assignableRooms(),
      );
    }
    if (documentId.trim().isNotEmpty) stay.documentId = documentId.trim();
    stay.receptionistIds.add(receptionistId);
    _occupy(stay, room);
    return stay;
  }

  void _occupy(Stay stay, Room room) {
    stay
      ..roomId = room.id
      ..status = StayStatus.checkedIn
      ..checkedInAt = now
      ..accessCode = (100000 + _random.nextInt(899999)).toString();
    room.status = RoomStatus.occupied;
    _resolveAlert('arrival-${stay.id}', 'Huésped ubicado en la habitación ${room.number}');
    if (stay.guestUserId != null) {
      _notify(stay.guestUserId!, 'Check-in completado', 'Habitación ${room.number} · código de acceso ${stay.accessCode}',
          NotificationType.stay);
    }
    notifyListeners();
  }

  double paidFor(Stay stay) => payments
      .where((p) =>
          p.stayId == stay.id &&
          p.status == PaymentStatus.approved &&
          (p.kind == PaymentKind.reservation || p.kind == PaymentKind.charges))
      .fold(0.0, (sum, p) => sum + p.amount);

  double totalCharges(Stay stay) => stay.charges.fold(0.0, (sum, c) => sum + c.amount);

  double balanceOf(Stay stay) => max(0, totalCharges(stay) - paidFor(stay));

  /// Leaves the room pending cleaning, refunds the deposit and e-mails the summary (US-14, US-16).
  void checkOut(int stayId, {int? receptionistId}) {
    final stay = stayById(stayId);
    if (stay.status != StayStatus.checkedIn) throw const DomainException('Solo puedes hacer check-out de una estancia activa.');
    final balance = balanceOf(stay);
    if (balance > 0.009) {
      throw PendingChargesException('Tienes cargos pendientes por \$${balance.toStringAsFixed(2)}. Revisa tu folio.', balance);
    }
    if (receptionistId != null) stay.receptionistIds.add(receptionistId);
    stay
      ..status = StayStatus.checkedOut
      ..checkedOutAt = now;
    if (stay.depositHeld > 0 && !stay.depositRefunded) {
      payments.add(Payment(
        id: nextId(),
        stayId: stay.id,
        amount: stay.depositHeld,
        method: 'Devolución automática',
        kind: PaymentKind.refund,
        status: PaymentStatus.refunded,
        createdAt: now,
      ));
      stay.depositRefunded = true;
    }
    final room = roomById(stay.roomId!);
    room.status = RoomStatus.dirty;
    createCleaningTask(room.id, priority: arrivalsToday.any((s) => s.roomType == room.type) ? Priority.high : Priority.normal);
    _mail(stay.guestEmail, 'Comprobante de tu estancia',
        'Estancia ${fmtShortDate(stay.checkIn)} - ${fmtShortDate(now)} · Habitación ${room.number} · '
        'Total \$${totalCharges(stay).toStringAsFixed(2)}'
        '${stay.depositRefunded ? ' · Depósito de \$${stay.depositHeld.toStringAsFixed(2)} en devolución' : ''}');
    notifyListeners();
  }

  /// Checks availability before extending (US-14).
  void extendStay(int stayId, int extraNights) {
    final stay = stayById(stayId);
    if (!stay.isActive) throw const DomainException('La estancia ya finalizó.');
    if (extraNights < 1) throw const DomainException('Elige al menos una noche adicional.');
    final newCheckOut = stay.checkOut.add(Duration(days: extraNights));
    final clash = stays.any((other) =>
        other.id != stay.id &&
        other.isActive &&
        other.roomId != null &&
        other.roomId == stay.roomId &&
        other.checkIn.isBefore(newCheckOut) &&
        other.checkOut.isAfter(stay.checkOut));
    if (clash) throw const DomainException('No hay disponibilidad para extender en tu habitación.');
    stay.checkOut = newCheckOut;
    stay.charges.add(_roomCharge(stay, extraNights));
    notifyListeners();
  }

  void setFiscalData(int stayId, FiscalData data) {
    if (!RegExp(r'^\d{11}$').hasMatch(data.ruc)) throw const DomainException('El RUC debe tener 11 dígitos.');
    if (data.businessName.trim().isEmpty) throw const DomainException('Ingresa la razón social.');
    stayById(stayId).fiscalData = data;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-15 / US-16 / US-17 Payments and receipts
  // ---------------------------------------------------------------------------

  static String? validateCard(CardInfo card) {
    final digits = card.digits;
    if (card.holder.trim().isEmpty) return 'Ingresa el nombre del titular.';
    if (digits.length < 13 || digits.length > 19 || !_luhn(digits)) return 'El número de tarjeta no es válido.';
    final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(card.expiry.trim());
    if (match == null) return 'La fecha de vencimiento debe tener el formato MM/AA.';
    final month = int.parse(match.group(1)!);
    final year = 2000 + int.parse(match.group(2)!);
    if (month < 1 || month > 12) return 'El mes de vencimiento no es válido.';
    if (DateTime(year, month + 1).isBefore(DateTime.now())) return 'La tarjeta está vencida.';
    if (!RegExp(r'^\d{3,4}$').hasMatch(card.cvv.trim())) return 'El CVV no es válido.';
    return null;
  }

  static bool _luhn(String digits) {
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      var n = int.parse(digits[digits.length - 1 - i]);
      if (i.isOdd) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
    }
    return sum % 10 == 0;
  }

  /// Simulated gateway: cards ending in 0002 are declined for lack of funds, 0069 by the bank.
  Payment _processCard(Stay stay, double amount, CardInfo card, PaymentKind kind) {
    final error = validateCard(card);
    if (error != null) throw DomainException(error);
    final digits = card.digits;
    final declineReason = digits.endsWith('0002')
        ? 'fondos insuficientes'
        : digits.endsWith('0069')
            ? 'el banco rechazó la operación'
            : null;
    final payment = Payment(
      id: nextId(),
      stayId: stay.id,
      amount: amount,
      method: card.masked,
      kind: kind,
      status: declineReason == null ? PaymentStatus.approved : PaymentStatus.rejected,
      createdAt: now,
      reason: declineReason ?? '',
    );
    payments.add(payment);
    if (declineReason != null) {
      notifyListeners();
      throw PaymentDeclinedException('Pago rechazado: $declineReason. Intenta con otro medio de pago.');
    }
    _issueReceipt(stay, payment);
    return payment;
  }

  Payment _recordCash(Stay stay, double amount, PaymentKind kind) {
    final payment = Payment(
      id: nextId(),
      stayId: stay.id,
      amount: amount,
      method: 'Efectivo en recepción',
      kind: kind,
      status: PaymentStatus.approved,
      createdAt: now,
    );
    payments.add(payment);
    _issueReceipt(stay, payment);
    return payment;
  }

  Payment payDeposit(int stayId, CardInfo card) {
    final stay = stayById(stayId);
    if (stay.depositHeld >= stay.depositRequired) throw const DomainException('El depósito ya fue retenido.');
    final payment = _processCard(stay, stay.depositRequired, card, PaymentKind.deposit);
    stay.depositHeld = stay.depositRequired;
    notifyListeners();
    return payment;
  }

  Payment payReservation(int stayId, CardInfo card) {
    final stay = stayById(stayId);
    final balance = balanceOf(stay);
    if (balance <= 0) throw const DomainException('No hay saldo pendiente.');
    final payment = _processCard(stay, balance, card, PaymentKind.reservation);
    notifyListeners();
    return payment;
  }

  /// Pays the pending balance with one or more methods (US-16). `null` card means cash at the desk.
  List<Payment> payBalance(int stayId, List<({double amount, CardInfo? card})> parts) {
    final stay = stayById(stayId);
    final balance = balanceOf(stay);
    if (balance <= 0) throw const DomainException('Tu folio ya está saldado.');
    if (parts.any((p) => p.amount <= 0)) throw const DomainException('Cada monto debe ser mayor a cero.');
    final total = parts.fold(0.0, (sum, p) => sum + p.amount);
    if ((total - balance).abs() > 0.009) {
      throw DomainException('Los montos deben sumar \$${balance.toStringAsFixed(2)}.');
    }
    final kind = stay.status == StayStatus.checkedIn ? PaymentKind.charges : PaymentKind.reservation;
    final done = <Payment>[];
    for (final part in parts) {
      final card = part.card;
      done.add(card == null ? _recordCash(stay, part.amount, kind) : _processCard(stay, part.amount, card, kind));
    }
    notifyListeners();
    return done;
  }

  void _issueReceipt(Stay stay, Payment payment) {
    final isInvoice = stay.fiscalData != null;
    final count = receipts.where((r) => r.type == (isInvoice ? 'Factura' : 'Boleta')).length + 1;
    final receipt = Receipt(
      id: nextId(),
      paymentId: payment.id,
      stayId: stay.id,
      number: '${isInvoice ? 'F001' : 'B001'}-${count.toString().padLeft(6, '0')}',
      type: isInvoice ? 'Factura' : 'Boleta',
      email: stay.guestEmail,
      amount: payment.amount,
      createdAt: now,
      fiscalData: stay.fiscalData,
    );
    receipts.add(receipt);
    payment.receiptId = receipt.id;
    _mail(stay.guestEmail, '${receipt.type} ${receipt.number}',
        '${payment.kind.label} por \$${payment.amount.toStringAsFixed(2)} · ${payment.method}');
    if (stay.guestUserId != null) {
      _notify(stay.guestUserId!, 'Pago confirmado', '${payment.kind.label}: \$${payment.amount.toStringAsFixed(2)}',
          NotificationType.stay);
    }
  }

  void resendReceipt(int receiptId) {
    final receipt = receipts.firstWhere((r) => r.id == receiptId);
    receipt.sentCount++;
    _mail(receipt.email, 'Reenvío: ${receipt.type} ${receipt.number}', 'Monto \$${receipt.amount.toStringAsFixed(2)}');
    notifyListeners();
  }

  List<Payment> paymentsOf(int stayId) =>
      payments.where((p) => p.stayId == stayId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // ---------------------------------------------------------------------------
  // US-21 / US-26 Ratings
  // ---------------------------------------------------------------------------

  void submitRating(int stayId, {required int cleaning, required int attention, required int maintenance, String comment = ''}) {
    final stay = stayById(stayId);
    if (stay.status != StayStatus.checkedOut) throw const DomainException('Podrás calificar al finalizar tu estancia.');
    if (stay.rated) throw const DomainException('Ya calificaste esta estancia. ¡Gracias!');
    final start = stay.checkedInAt ?? stay.checkIn;
    final end = stay.checkedOutAt ?? now;
    bool during(DateTime? at) => at != null && !at.isBefore(start) && !at.isAfter(end.add(const Duration(hours: 4)));
    ratings.add(Rating(
      stayId: stayId,
      scores: {Area.housekeeping: cleaning, Area.reception: attention, Area.maintenance: maintenance},
      comment: comment.trim(),
      createdAt: now,
      staffIds: {
        Area.housekeeping: tasks
            .where((t) => t.roomId == stay.roomId && during(t.completedAt) && t.assigneeId != null)
            .map((t) => t.assigneeId!)
            .toSet(),
        Area.maintenance: incidents
            .where((i) => i.roomId == stay.roomId && during(i.resolvedAt) && i.assigneeId != null)
            .map((i) => i.assigneeId!)
            .toSet(),
        Area.reception: {...stay.receptionistIds},
      },
    ));
    stay.rated = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-22 / US-23 Notifications and alerts
  // ---------------------------------------------------------------------------

  void _notify(int userId, String title, String body, NotificationType type, {bool urgent = false}) {
    final user = userById(userId);
    if (user == null || !user.active || !user.wants(type)) return;
    notifications.add(AppNotification(
      id: nextId(),
      userId: userId,
      title: title,
      body: body,
      type: type,
      urgent: urgent,
      createdAt: now,
    ));
  }

  void _notifyRole(UserRole role, String title, String body, NotificationType type, {bool urgent = false}) {
    for (final user in staffOf(role)) {
      _notify(user.id, title, body, type, urgent: urgent);
    }
  }

  List<AppNotification> notificationsFor(int userId) =>
      notifications.where((n) => n.userId == userId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int unreadCount(int userId) => notifications.where((n) => n.userId == userId && !n.read).length;

  void markNotificationsRead(int userId) {
    for (final n in notifications.where((n) => n.userId == userId)) {
      n.read = true;
    }
    notifyListeners();
  }

  void _raiseAlert(String key, String title, String detail) {
    if (alerts.any((a) => a.key == key && !a.resolved)) return;
    alerts.add(OperationalAlert(id: nextId(), key: key, title: title, detail: detail, createdAt: now));
    _notifyRole(UserRole.admin, title, detail, NotificationType.alert, urgent: true);
  }

  void _resolveAlert(String key, String resolution) {
    for (final alert in alerts.where((a) => a.key == key && !a.resolved)) {
      alert
        ..resolved = true
        ..resolution = resolution
        ..resolvedAt = now;
    }
  }

  void resolveAlert(int alertId, String resolution) {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    alert
      ..resolved = true
      ..resolution = resolution.trim().isEmpty ? 'Atendida por el administrador' : resolution.trim()
      ..resolvedAt = now;
    notifyListeners();
  }

  List<OperationalAlert> get activeAlerts =>
      alerts.where((a) => !a.resolved).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Time-based rules: escalations, delays, preventive work and scheduled reports.
  void runChecks() {
    for (final incident in incidents.where((i) => i.isOpen && i.urgency == Priority.urgent && !i.escalated)) {
      if (now.difference(incident.createdAt) >= criticalIncidentLimit) {
        incident.escalated = true;
        incident.events.add(TimelineEvent(now, 'Escalada al administrador por demora'));
        _raiseAlert('incident-${incident.id}', 'Incidencia crítica sin resolver',
            'Hab. ${roomById(incident.roomId).number}: ${incident.title} lleva ${now.difference(incident.createdAt).inMinutes} min abierta.');
      }
    }

    for (final task in tasks.where((t) => t.isOpen && t.priority.isCritical)) {
      if (now.difference(task.createdAt) >= overdueTaskLimit) {
        _raiseAlert('task-${task.id}', 'Limpieza atrasada',
            'Hab. ${roomById(task.roomId).number} (${task.priority.label.toLowerCase()}) sin terminar hace ${now.difference(task.createdAt).inMinutes} min.');
      }
    }
    for (final task in tasks.where((t) => !t.isOpen)) {
      _resolveAlert('task-${task.id}', 'Limpieza completada');
    }

    for (final stay in arrivalsToday) {
      final soon = stay.checkIn.difference(now) <= arrivalWarning;
      final ready = stay.roomId != null ? isAssignable(roomById(stay.roomId!)) : assignableRooms(type: stay.roomType).isNotEmpty;
      if (soon && !ready) {
        _raiseAlert('arrival-${stay.id}', 'Llegada próxima sin habitación lista',
            '${stay.guestName} llega a las ${fmtHour(stay.checkIn)} y no hay ${stay.roomType.label.toLowerCase()} limpia.');
      } else if (ready) {
        _resolveAlert('arrival-${stay.id}', 'Habitación lista para la llegada');
      }
    }

    for (final task in preventiveTasks) {
      if (!task.reminded && task.nextDue.difference(now) <= const Duration(days: 2) && task.nextDue.isAfter(now)) {
        task.reminded = true;
        _notifyRole(UserRole.maintenance, 'Preventivo próximo', '${task.title} · Hab. ${roomById(task.roomId).number} vence el ${fmtShortDate(task.nextDue)}',
            NotificationType.incident);
      }
      while (!task.nextDue.isAfter(now)) {
        task.generated.add(task.nextDue);
        createIncident(
          roomId: task.roomId,
          title: 'Preventivo: ${task.title}',
          description: 'Generado automáticamente cada ${task.frequencyDays} días.',
          category: 'Preventivo',
          urgency: Priority.normal,
          reporterId: staffOf(UserRole.admin).firstOrNull?.id ?? 0,
          preventive: true,
        );
        task
          ..nextDue = task.nextDue.add(Duration(days: task.frequencyDays))
          ..reminded = false;
      }
    }

    for (final schedule in schedules) {
      while (!schedule.nextSend.isAfter(now)) {
        for (final to in schedule.recipients) {
          _mail(to, '${schedule.name} (${schedule.format})', exportCsv(Period.lastDays(now, schedule.frequencyDays)));
        }
        schedule
          ..lastSent = now
          ..nextSend = schedule.nextSend.add(Duration(days: schedule.frequencyDays));
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-18 Dashboard indicators
  // ---------------------------------------------------------------------------

  double get occupancyRate =>
      rooms.isEmpty ? 0 : rooms.where((r) => r.status == RoomStatus.occupied).length / rooms.length;

  int get pendingCleaning =>
      rooms.where((r) => r.status == RoomStatus.dirty || r.status == RoomStatus.cleaning).length;

  List<CleaningTask> get overdueTasks =>
      tasks.where((t) => t.isOpen && now.difference(t.createdAt) >= overdueTaskLimit).toList();

  // ---------------------------------------------------------------------------
  // US-24 / US-25 / US-26 / US-34 Analytics
  // ---------------------------------------------------------------------------

  static double _avg(Iterable<double> values) => values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _taskMinutes(CleaningTask t) =>
      t.completedAt!.difference(t.startedAt ?? t.createdAt).inSeconds / 60;

  static double _incidentHours(Incident i) => i.resolvedAt!.difference(i.createdAt).inMinutes / 60;

  Iterable<CleaningTask> _doneTasks(Period period) =>
      tasks.where((t) => t.completedAt != null && period.contains(t.completedAt!));

  Iterable<Incident> _resolvedIncidents(Period period) =>
      incidents.where((i) => i.resolvedAt != null && period.contains(i.resolvedAt!));

  List<StaffProductivity> productivity(Period period) {
    final result = <StaffProductivity>[];
    for (final user in users.where((u) => u.role == UserRole.housekeeping || u.role == UserRole.maintenance)) {
      if (user.role == UserRole.housekeeping) {
        final done = _doneTasks(period).where((t) => t.assigneeId == user.id);
        result.add(StaffProductivity(user, done.length, tasks.where((t) => t.isOpen && t.assigneeId == user.id).length,
            _avg(done.map(_taskMinutes))));
      } else {
        final done = _resolvedIncidents(period).where((i) => i.assigneeId == user.id);
        result.add(StaffProductivity(user, done.length, incidents.where((i) => i.isOpen && i.assigneeId == user.id).length,
            _avg(done.map((i) => _incidentHours(i) * 60))));
      }
    }
    result.sort((a, b) => b.completed.compareTo(a.completed));
    return result;
  }

  List<AreaStats> areaComparison(Period period) {
    final doneTasks = _doneTasks(period).toList();
    final doneIncidents = _resolvedIncidents(period).toList();
    final doneRequests = requests.where((r) => r.resolvedAt != null && period.contains(r.resolvedAt!)).toList();
    return [
      AreaStats(
        Area.housekeeping,
        doneTasks.length,
        tasks.where((t) => t.isOpen).length,
        doneTasks.where((t) => t.completedAt!.difference(t.createdAt) > overdueTaskLimit).length,
        _avg(doneTasks.map(_taskMinutes)),
      ),
      AreaStats(
        Area.maintenance,
        doneIncidents.length,
        incidents.where((i) => i.isOpen).length,
        doneIncidents.where((i) => i.escalated).length,
        _avg(doneIncidents.map((i) => _incidentHours(i) * 60)),
      ),
      AreaStats(
        Area.reception,
        doneRequests.length,
        requests.where((r) => r.status != WorkStatus.resolved).length,
        doneRequests.where((r) => r.resolvedAt!.difference(r.createdAt).inMinutes > r.etaMinutes).length,
        _avg(doneRequests.map((r) => r.resolvedAt!.difference(r.createdAt).inMinutes.toDouble())),
      ),
    ];
  }

  Map<RoomType, double> cleaningMinutesByType(Period period) {
    final done = _doneTasks(period).toList();
    return {
      for (final type in RoomType.values)
        type: _avg(done.where((t) => roomById(t.roomId).type == type).map(_taskMinutes)),
    };
  }

  double incidentResolutionHours(Period period) => _avg(_resolvedIncidents(period).map(_incidentHours));

  List<TrendPoint> weeklyTrend(Period period) {
    final points = <TrendPoint>[];
    var weekStart = DateUtils.dateOnly(period.start);
    while (!weekStart.isAfter(period.end)) {
      final week = Period(weekStart, weekStart.add(const Duration(days: 7)).subtract(const Duration(seconds: 1)));
      points.add(TrendPoint(weekStart, _avg(_doneTasks(week).map(_taskMinutes)), _avg(_resolvedIncidents(week).map(_incidentHours))));
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return points;
  }

  Map<Area, double> satisfactionByArea(Period period) {
    final inPeriod = ratings.where((r) => period.contains(r.createdAt)).toList();
    return {for (final area in Area.values) area: _avg(inPeriod.map((r) => (r.scores[area] ?? 0).toDouble()))};
  }

  List<({AppUser user, double average, int count})> satisfactionByStaff(Period period) {
    final scores = <int, List<double>>{};
    for (final rating in ratings.where((r) => period.contains(r.createdAt))) {
      rating.staffIds.forEach((area, ids) {
        for (final id in ids) {
          scores.putIfAbsent(id, () => []).add((rating.scores[area] ?? 0).toDouble());
        }
      });
    }
    final result = [
      for (final entry in scores.entries)
        if (userById(entry.key) != null) (user: userById(entry.key)!, average: _avg(entry.value), count: entry.value.length),
    ];
    result.sort((a, b) => b.average.compareTo(a.average));
    return result;
  }

  /// Report opened by Excel; the same content travels in scheduled e-mails (US-24, US-34).
  String exportCsv(Period period) {
    final buffer = StringBuffer()
      ..writeln('Reporte RoomTrack;${fmtShortDate(period.start)};${fmtShortDate(period.end)}')
      ..writeln()
      ..writeln('Colaborador;Rol;Completadas;Pendientes;Promedio (min)');
    for (final p in productivity(period)) {
      buffer.writeln('${p.user.name};${p.user.role.label};${p.completed};${p.pending};${p.avgMinutes.toStringAsFixed(1)}');
    }
    buffer
      ..writeln()
      ..writeln('Área;Completadas;Pendientes;Con demora;Promedio (min)');
    for (final a in areaComparison(period)) {
      buffer.writeln('${a.area.label};${a.completed};${a.pending};${a.delayed};${a.avgMinutes.toStringAsFixed(1)}');
    }
    final income = payments
        .where((p) => p.status == PaymentStatus.approved && p.kind != PaymentKind.deposit && period.contains(p.createdAt))
        .fold(0.0, (sum, p) => sum + p.amount);
    buffer
      ..writeln()
      ..writeln('Ingresos;${income.toStringAsFixed(2)}')
      ..writeln('Ocupación actual;${(occupancyRate * 100).toStringAsFixed(0)}%');
    return buffer.toString();
  }

  ReportSchedule scheduleReport({
    required String name,
    required String kind,
    required int frequencyDays,
    required List<String> recipients,
    required String format,
  }) {
    if (recipients.isEmpty) throw const DomainException('Agrega al menos un destinatario.');
    for (final email in recipients) {
      _validateEmail(email);
    }
    final schedule = ReportSchedule(
      id: nextId(),
      name: name.trim().isEmpty ? 'Reporte $kind' : name.trim(),
      kind: kind,
      frequencyDays: frequencyDays,
      recipients: recipients,
      format: format,
      nextSend: now.add(Duration(days: frequencyDays)),
    );
    schedules.add(schedule);
    notifyListeners();
    return schedule;
  }

  void deleteSchedule(int id) {
    schedules.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // US-31 / US-32 Shifts and handover
  // ---------------------------------------------------------------------------

  Shift createShift({required DateTime date, required Area area, required String label, required int startHour,
      required int endHour, required int minStaff, required List<int> staffIds}) {
    final shift = Shift(
      id: nextId(),
      date: DateUtils.dateOnly(date),
      area: area,
      label: label,
      startHour: startHour,
      endHour: endHour,
      minStaff: minStaff,
      staffIds: [...staffIds],
    );
    shifts.add(shift);
    for (final id in staffIds) {
      _notify(id, 'Nuevo turno asignado', '${shift.label} ${fmtShortDate(shift.date)} · ${shift.hours}', NotificationType.task);
    }
    notifyListeners();
    return shift;
  }

  void toggleShiftMember(int shiftId, int userId) {
    final shift = shifts.firstWhere((s) => s.id == shiftId);
    if (!shift.staffIds.remove(userId)) shift.staffIds.add(userId);
    notifyListeners();
  }

  List<Shift> shiftsOf(int userId) =>
      shifts.where((s) => s.staffIds.contains(userId)).toList()..sort((a, b) => a.date.compareTo(b.date));

  ShiftSwap requestSwap({required int requesterId, required int fromShiftId, required int targetUserId, required int toShiftId}) {
    final from = shifts.firstWhere((s) => s.id == fromShiftId);
    final to = shifts.firstWhere((s) => s.id == toShiftId);
    if (!from.staffIds.contains(requesterId) || !to.staffIds.contains(targetUserId)) {
      throw const DomainException('Cada colaborador debe pertenecer al turno que cede.');
    }
    final swap = ShiftSwap(id: nextId(), requesterId: requesterId, fromShiftId: fromShiftId, targetUserId: targetUserId, toShiftId: toShiftId);
    swaps.add(swap);
    _notifyRole(UserRole.admin, 'Solicitud de cambio de turno', '${userName(requesterId)} ↔ ${userName(targetUserId)}', NotificationType.task);
    notifyListeners();
    return swap;
  }

  void decideSwap(int swapId, bool approve) {
    final swap = swaps.firstWhere((s) => s.id == swapId);
    if (swap.approved != null) throw const DomainException('Esta solicitud ya fue respondida.');
    swap.approved = approve;
    if (approve) {
      final from = shifts.firstWhere((s) => s.id == swap.fromShiftId);
      final to = shifts.firstWhere((s) => s.id == swap.toShiftId);
      from.staffIds
        ..remove(swap.requesterId)
        ..add(swap.targetUserId);
      to.staffIds
        ..remove(swap.targetUserId)
        ..add(swap.requesterId);
    }
    for (final id in [swap.requesterId, swap.targetUserId]) {
      _notify(id, approve ? 'Cambio de turno aprobado' : 'Cambio de turno rechazado', 'Revisa tu calendario.', NotificationType.task);
    }
    notifyListeners();
  }

  /// Pending items of the author's area are attached automatically (US-32).
  Handover createHandover(AppUser author, String notes) {
    final area = author.role.area ?? Area.reception;
    final open = <String>[
      if (area == Area.housekeeping)
        for (final t in openTasks) 'Limpieza hab. ${roomById(t.roomId).number} · ${t.status.label} (${userName(t.assigneeId)})',
      if (area == Area.maintenance)
        for (final i in openIncidents) 'Incidencia hab. ${roomById(i.roomId).number}: ${i.title} · ${i.status.label}',
      if (area == Area.reception) ...[
        for (final r in requests.where((r) => r.status != WorkStatus.resolved))
          'Solicitud hab. ${roomById(r.roomId).number}: ${r.description}',
        for (final s in arrivalsToday) 'Llegada pendiente: ${s.guestName}',
      ],
    ];
    if (notes.trim().isEmpty && open.isEmpty) throw const DomainException('Escribe un resumen para el siguiente turno.');
    final handover = Handover(id: nextId(), authorId: author.id, area: area, notes: notes.trim(), createdAt: now, openItems: open);
    handovers.add(handover);
    notifyListeners();
    return handover;
  }

  Handover? latestHandoverFor(AppUser user) {
    final area = user.role.area;
    final list = handovers.where((h) => (area == null || h.area == area) && h.authorId != user.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.firstOrNull;
  }

  void markHandoverRead(int handoverId, int userId) {
    handovers.firstWhere((h) => h.id == handoverId).readBy[userId] = now;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  void _mail(String to, String subject, String body) {
    outbox.add(OutboxEmail(to: to, subject: subject, body: body, createdAt: now));
  }

  static String fmtShortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String fmtHour(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
