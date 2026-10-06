import 'package:flutter/material.dart';

enum UserRole { admin, reception, housekeeping, maintenance, guest }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Administrador',
        UserRole.reception => 'Recepción',
        UserRole.housekeeping => 'Limpieza',
        UserRole.maintenance => 'Mantenimiento',
        UserRole.guest => 'Huésped',
      };

  /// Operational area the role belongs to, `null` for the admin and guests.
  Area? get area => switch (this) {
        UserRole.reception => Area.reception,
        UserRole.housekeeping => Area.housekeeping,
        UserRole.maintenance => Area.maintenance,
        _ => null,
      };

  bool get isStaff => this != UserRole.guest;
}

enum Area { reception, housekeeping, maintenance }

extension AreaX on Area {
  String get label => switch (this) {
        Area.reception => 'Recepción',
        Area.housekeeping => 'Limpieza',
        Area.maintenance => 'Mantenimiento',
      };

  IconData get icon => switch (this) {
        Area.reception => Icons.support_agent,
        Area.housekeeping => Icons.cleaning_services_outlined,
        Area.maintenance => Icons.build_outlined,
      };

  UserRole get role => switch (this) {
        Area.reception => UserRole.reception,
        Area.housekeeping => UserRole.housekeeping,
        Area.maintenance => UserRole.maintenance,
      };

  /// Estimated attention time promised to guests when a request reaches this area.
  int get etaMinutes => switch (this) {
        Area.reception => 10,
        Area.housekeeping => 20,
        Area.maintenance => 40,
      };
}

enum Priority { low, normal, high, urgent }

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.low => 'Baja',
        Priority.normal => 'Normal',
        Priority.high => 'Alta',
        Priority.urgent => 'Urgente',
      };

  Color get color => switch (this) {
        Priority.low => const Color(0xFF7C8B99),
        Priority.normal => const Color(0xFF6F93B8),
        Priority.high => const Color(0xFFE08A1E),
        Priority.urgent => const Color(0xFFD93025),
      };

  bool get isCritical => index >= Priority.high.index;
}

enum RoomStatus { available, occupied, dirty, cleaning, maintenance }

extension RoomStatusX on RoomStatus {
  String get label => switch (this) {
        RoomStatus.available => 'Disponible',
        RoomStatus.occupied => 'Ocupada',
        RoomStatus.dirty => 'Pendiente de limpieza',
        RoomStatus.cleaning => 'En limpieza',
        RoomStatus.maintenance => 'En mantenimiento',
      };

  Color get color => switch (this) {
        RoomStatus.available => const Color(0xFF2E9D6B),
        RoomStatus.occupied => const Color(0xFF6F93B8),
        RoomStatus.dirty => const Color(0xFFE08A1E),
        RoomStatus.cleaning => const Color(0xFF8E6CC9),
        RoomStatus.maintenance => const Color(0xFFD93025),
      };

  IconData get icon => switch (this) {
        RoomStatus.available => Icons.check_circle_outline,
        RoomStatus.occupied => Icons.person_outline,
        RoomStatus.dirty => Icons.cleaning_services_outlined,
        RoomStatus.cleaning => Icons.autorenew,
        RoomStatus.maintenance => Icons.build_outlined,
      };
}

enum RoomType { standard, twin, suite }

extension RoomTypeX on RoomType {
  String get label => switch (this) {
        RoomType.standard => 'Estándar',
        RoomType.twin => 'Doble',
        RoomType.suite => 'Suite',
      };

  double get nightlyRate => switch (this) {
        RoomType.standard => 95,
        RoomType.twin => 140,
        RoomType.suite => 205,
      };
}

enum TaskStatus { pending, inProgress, done }

extension TaskStatusX on TaskStatus {
  String get label => switch (this) {
        TaskStatus.pending => 'Pendiente',
        TaskStatus.inProgress => 'En limpieza',
        TaskStatus.done => 'Limpia',
      };
}

enum WorkStatus { pending, inProgress, resolved }

extension WorkStatusX on WorkStatus {
  String get label => switch (this) {
        WorkStatus.pending => 'Pendiente',
        WorkStatus.inProgress => 'En proceso',
        WorkStatus.resolved => 'Resuelta',
      };

  Color get color => switch (this) {
        WorkStatus.pending => const Color(0xFFE08A1E),
        WorkStatus.inProgress => const Color(0xFF6F93B8),
        WorkStatus.resolved => const Color(0xFF2E9D6B),
      };
}

enum StayStatus { reserved, checkInInProgress, checkedIn, checkedOut }

extension StayStatusX on StayStatus {
  String get label => switch (this) {
        StayStatus.reserved => 'Reserva confirmada',
        StayStatus.checkInInProgress => 'Check-in en proceso',
        StayStatus.checkedIn => 'Hospedado',
        StayStatus.checkedOut => 'Finalizada',
      };
}

enum PaymentKind { reservation, deposit, charges, refund }

extension PaymentKindX on PaymentKind {
  String get label => switch (this) {
        PaymentKind.reservation => 'Pago de reserva',
        PaymentKind.deposit => 'Depósito de garantía',
        PaymentKind.charges => 'Cargos adicionales',
        PaymentKind.refund => 'Devolución de depósito',
      };
}

enum PaymentStatus { approved, rejected, refunded }

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.approved => 'Aprobado',
        PaymentStatus.rejected => 'Rechazado',
        PaymentStatus.refunded => 'Reembolsado',
      };
}

enum NotificationType { task, priority, incident, request, message, alert, stay }

extension NotificationTypeX on NotificationType {
  String get label => switch (this) {
        NotificationType.task => 'Tareas asignadas',
        NotificationType.priority => 'Cambios de prioridad',
        NotificationType.incident => 'Incidencias',
        NotificationType.request => 'Solicitudes',
        NotificationType.message => 'Mensajes',
        NotificationType.alert => 'Alertas operativas',
        NotificationType.stay => 'Mi estancia',
      };
}

class AppUser {
  final int id;
  String name;
  String email;
  String phone;
  String photoUrl;
  UserRole role;
  bool active;

  /// Demo-only credential: a real backend never hands passwords to the client.
  String password;
  final Map<NotificationType, bool> prefs;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.password,
    this.phone = '',
    this.photoUrl = '',
    this.active = true,
  }) : prefs = {for (final type in NotificationType.values) type: true};

  bool wants(NotificationType type) => prefs[type] ?? true;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String get firstName => name.trim().split(' ').first;
}

class Room {
  final int id;
  final String number;
  final int floor;
  final RoomType type;
  RoomStatus status;

  Room({
    required this.id,
    required this.number,
    required this.floor,
    required this.type,
    this.status = RoomStatus.available,
  });
}

class TimelineEvent {
  final DateTime at;
  final String text;

  const TimelineEvent(this.at, this.text);
}

class ChecklistItem {
  final String label;
  final bool required;
  bool done;

  ChecklistItem(this.label, {this.required = true, this.done = false});
}

class CleaningTask {
  final int id;
  final int roomId;
  int? assigneeId;
  Priority priority;
  TaskStatus status;
  final List<ChecklistItem> checklist;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  final List<TimelineEvent> events = [];

  CleaningTask({
    required this.id,
    required this.roomId,
    required this.checklist,
    required this.createdAt,
    this.assigneeId,
    this.priority = Priority.normal,
    this.status = TaskStatus.pending,
  });

  bool get isOpen => status != TaskStatus.done;

  double get progress {
    if (checklist.isEmpty) return 1;
    return checklist.where((item) => item.done).length / checklist.length;
  }

  List<ChecklistItem> get missingRequired => checklist.where((item) => item.required && !item.done).toList();
}

class Incident {
  final int id;
  final int roomId;
  final String title;
  final String description;
  final String category;
  Priority urgency;
  WorkStatus status;
  final int reportedById;
  int? assigneeId;
  final DateTime createdAt;
  DateTime? resolvedAt;
  String resolutionNotes;

  /// Preventive work is planned: it never blocks the room for new guests.
  final bool preventive;
  final bool blocksRoom;
  bool escalated;
  bool recurring;
  final List<TimelineEvent> events = [];

  Incident({
    required this.id,
    required this.roomId,
    required this.title,
    required this.description,
    required this.category,
    required this.urgency,
    required this.reportedById,
    required this.createdAt,
    this.status = WorkStatus.pending,
    this.assigneeId,
    this.preventive = false,
    this.blocksRoom = true,
    this.escalated = false,
    this.recurring = false,
    this.resolutionNotes = '',
  });

  bool get isOpen => status != WorkStatus.resolved;
}

class GuestRequest {
  final int id;
  final int roomId;
  final int? stayId;
  final String description;
  Area area;
  WorkStatus status;
  final DateTime createdAt;
  final int etaMinutes;
  final int createdById;
  DateTime? resolvedAt;
  final List<TimelineEvent> events = [];

  GuestRequest({
    required this.id,
    required this.roomId,
    required this.description,
    required this.area,
    required this.createdAt,
    required this.etaMinutes,
    required this.createdById,
    this.stayId,
    this.status = WorkStatus.pending,
  });
}

class FolioCharge {
  final int id;
  final String description;
  final double amount;
  final DateTime createdAt;

  const FolioCharge({
    required this.id,
    required this.description,
    required this.amount,
    required this.createdAt,
  });
}

class FiscalData {
  final String ruc;
  final String businessName;
  final String address;

  const FiscalData({required this.ruc, required this.businessName, required this.address});
}

class Stay {
  final int id;
  int? guestUserId;
  final String guestName;
  final String guestEmail;
  final RoomType roomType;
  final int guests;
  int? roomId;
  final DateTime checkIn;
  DateTime checkOut;
  StayStatus status;
  final double depositRequired;
  double depositHeld;
  bool depositRefunded;
  String? accessCode;
  String documentId;
  bool digital;
  FiscalData? fiscalData;
  bool rated;
  DateTime? checkedInAt;
  DateTime? checkedOutAt;
  final List<FolioCharge> charges = [];
  final Set<int> receptionistIds = {};

  /// Booking code given by the backend (e.g. SS-7KQ4M2XP).
  String? code;

  /// The backend booking is Pending: the hotel has not registered its payment yet.
  bool awaitingPayment = false;
  DateTime? paymentDueAt;

  /// How to pay a pending booking (the hotel's Yape, Plin or bank account).
  Map<String, dynamic>? paymentInstructions;

  Stay({
    required this.id,
    required this.guestName,
    required this.guestEmail,
    required this.roomType,
    required this.checkIn,
    required this.checkOut,
    this.guests = 1,
    this.guestUserId,
    this.roomId,
    this.status = StayStatus.reserved,
    this.depositRequired = 150,
    this.depositHeld = 0,
    this.depositRefunded = false,
    this.documentId = '',
    this.digital = false,
    this.rated = false,
  });

  int get nights {
    final days = DateUtils.dateOnly(checkOut).difference(DateUtils.dateOnly(checkIn)).inDays;
    return days < 1 ? 1 : days;
  }

  bool get isActive => status != StayStatus.checkedOut;
}

class Payment {
  final int id;
  final int stayId;
  final double amount;
  final String method;
  final PaymentKind kind;
  PaymentStatus status;
  final DateTime createdAt;
  final String reason;
  int? receiptId;

  Payment({
    required this.id,
    required this.stayId,
    required this.amount,
    required this.method,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.reason = '',
  });
}

class Receipt {
  final int id;
  final int paymentId;
  final int stayId;
  final String number;
  final String type;
  final String email;
  final double amount;
  final DateTime createdAt;
  final FiscalData? fiscalData;
  int sentCount;

  Receipt({
    required this.id,
    required this.paymentId,
    required this.stayId,
    required this.number,
    required this.type,
    required this.email,
    required this.amount,
    required this.createdAt,
    this.fiscalData,
    this.sentCount = 1,
  });
}

class AppNotification {
  final int id;
  final int userId;
  final String title;
  final String body;
  final NotificationType type;
  final bool urgent;
  final DateTime createdAt;
  bool read;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.urgent = false,
    this.read = false,
  });
}

class OperationalAlert {
  final int id;

  /// Identifies the condition that raised it, so it is raised only once.
  final String key;
  final String title;
  final String detail;
  final DateTime createdAt;
  bool resolved;
  String resolution;
  DateTime? resolvedAt;

  OperationalAlert({
    required this.id,
    required this.key,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.resolved = false,
    this.resolution = '',
  });
}

class ChatMessage {
  final int id;
  final String channel;
  final int authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.channel,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });
}

class Rating {
  final int stayId;
  final Map<Area, int> scores;
  final String comment;
  final DateTime createdAt;

  /// Collaborators who served the stay, per area, so the admin can see individual performance.
  final Map<Area, Set<int>> staffIds;

  const Rating({
    required this.stayId,
    required this.scores,
    required this.comment,
    required this.createdAt,
    required this.staffIds,
  });
}

class ServiceItem {
  final int id;
  final String name;
  final String description;
  final double price;
  final Area area;
  final IconData icon;
  bool available;

  ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.area,
    required this.icon,
    this.available = true,
  });
}

class PreventiveTask {
  final int id;
  final String title;
  final int roomId;
  final int frequencyDays;
  DateTime nextDue;
  bool reminded;
  final List<DateTime> generated = [];

  PreventiveTask({
    required this.id,
    required this.title,
    required this.roomId,
    required this.frequencyDays,
    required this.nextDue,
    this.reminded = false,
  });
}

class Shift {
  final int id;
  final DateTime date;
  final Area area;
  final String label;
  final int startHour;
  final int endHour;
  final int minStaff;
  final List<int> staffIds;

  Shift({
    required this.id,
    required this.date,
    required this.area,
    required this.label,
    required this.startHour,
    required this.endHour,
    required this.minStaff,
    List<int>? staffIds,
  }) : staffIds = staffIds ?? [];

  bool get hasCoverageGap => staffIds.length < minStaff;

  String get hours => '${startHour.toString().padLeft(2, '0')}:00 - ${endHour.toString().padLeft(2, '0')}:00';
}

class ShiftSwap {
  final int id;
  final int requesterId;
  final int fromShiftId;
  final int targetUserId;
  final int toShiftId;

  /// `null` while the admin has not decided.
  bool? approved;

  ShiftSwap({
    required this.id,
    required this.requesterId,
    required this.fromShiftId,
    required this.targetUserId,
    required this.toShiftId,
  });
}

class Handover {
  final int id;
  final int authorId;
  final Area area;
  final String notes;
  final DateTime createdAt;
  final List<String> openItems;
  final Map<int, DateTime> readBy = {};

  Handover({
    required this.id,
    required this.authorId,
    required this.area,
    required this.notes,
    required this.createdAt,
    required this.openItems,
  });
}

class ReportSchedule {
  final int id;
  final String name;
  final String kind;
  final int frequencyDays;
  final List<String> recipients;
  final String format;
  DateTime nextSend;
  DateTime? lastSent;

  ReportSchedule({
    required this.id,
    required this.name,
    required this.kind,
    required this.frequencyDays,
    required this.recipients,
    required this.format,
    required this.nextSend,
  });
}

/// E-mail the demo backend "sent": recovery links, credentials, receipts and reports.
class OutboxEmail {
  final String to;
  final String subject;
  final String body;
  final DateTime createdAt;

  const OutboxEmail({required this.to, required this.subject, required this.body, required this.createdAt});
}
