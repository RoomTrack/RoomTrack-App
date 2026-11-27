import 'dart:typed_data';

import 'package:flutter/material.dart' show DateUtils;

import '../../domain/models.dart';
import '../hotel_store.dart';
import 'api_client.dart';
import 'remote_reports.dart';

/// Accounts created by `tool/seed_backend.py` in a local backend.
const String kRemoteStaffPassword = 'RoomTrack-Staff-2026!';
const String kRemoteGuestPassword = 'RoomTrack-Huesped-2026!';

const List<({String email, String label, String password})> kRemoteDemoAccounts = [
  (email: 'admin@roomtrack.pe', label: 'Administrador', password: kRemoteStaffPassword),
  (email: 'recepcion@roomtrack.pe', label: 'Recepción', password: kRemoteStaffPassword),
  (email: 'limpieza@roomtrack.pe', label: 'Limpieza', password: kRemoteStaffPassword),
  (email: 'mantenimiento@roomtrack.pe', label: 'Mantenimiento', password: kRemoteStaffPassword),
  (email: 'huesped@roomtrack.pe', label: 'Huésped (pagada)', password: kRemoteGuestPassword),
  (email: 'huesped2@roomtrack.pe', label: 'Huésped (por pagar)', password: kRemoteGuestPassword),
];

/// Result of the first step of the sign-in: staff accounts still need their second factor.
sealed class SignInOutcome {
  const SignInOutcome();
}

class SignedIn extends SignInOutcome {
  final AppUser user;

  const SignedIn(this.user);
}

/// The account has no authenticator yet: it must enroll one before getting a session.
class MfaEnrollmentNeeded extends SignInOutcome {
  final String mfaToken;
  final String email;

  const MfaEnrollmentNeeded(this.mfaToken, this.email);
}

/// The account has an authenticator: send one of its codes (or a recovery code).
class MfaCodeNeeded extends SignInOutcome {
  final String mfaToken;
  final String email;

  const MfaCodeNeeded(this.mfaToken, this.email);
}

class MfaEnrollment {
  final String secret;
  final String otpAuthUri;

  const MfaEnrollment(this.secret, this.otpAuthUri);
}

/// Payment methods the front desk can register (`RegisterPaymentResource.Method`).
const List<({String value, String label})> kPaymentMethods = [
  (value: 'Yape', label: 'Yape'),
  (value: 'Plin', label: 'Plin'),
  (value: 'BankTransfer', label: 'Transferencia'),
  (value: 'Cash', label: 'Efectivo'),
  (value: 'CardAtFrontDesk', label: 'Tarjeta en recepción'),
];

class MonthlyMetrics {
  final double revenue;
  final int bookings;
  final double occupancyRate;
  final int cancelled;

  const MonthlyMetrics(this.revenue, this.bookings, this.occupancyRate, this.cancelled);
}

/// Payment methods of a hotel (`HotelPaymentSettingsResource`).
class HotelPaymentSettings {
  final bool acceptsBookings;
  final String? accountHolder;
  final String? yapeNumber;
  final String? plinNumber;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountCci;

  const HotelPaymentSettings({
    this.acceptsBookings = false,
    this.accountHolder,
    this.yapeNumber,
    this.plinNumber,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountCci,
  });

  factory HotelPaymentSettings.fromJson(Map<String, dynamic> data) => HotelPaymentSettings(
        acceptsBookings: data['acceptsBookings'] == true,
        accountHolder: data['accountHolder'] as String?,
        yapeNumber: data['yapeNumber'] as String?,
        plinNumber: data['plinNumber'] as String?,
        bankName: data['bankName'] as String?,
        bankAccountNumber: data['bankAccountNumber'] as String?,
        bankAccountCci: data['bankAccountCci'] as String?,
      );

  /// Blank values go as null: that method is not offered.
  Map<String, dynamic> toJson() {
    String? clean(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();
    return {
      'accountHolder': clean(accountHolder),
      'yapeNumber': clean(yapeNumber),
      'plinNumber': clean(plinNumber),
      'bankName': clean(bankName),
      'bankAccountNumber': clean(bankAccountNumber),
      'bankAccountCci': clean(bankAccountCci),
    };
  }
}

/// The RoomTrack backend seen from the app.
///
/// It owns the session, copies what the backend knows (users, rooms, bookings, payments) into the
/// [HotelStore] the screens already listen to, and sends the actions the backend supports. Everything the
/// backend does not have yet (housekeeping tasks, incidents, requests...) keeps working on the store alone.
class RemoteHotel {
  RemoteHotel(this.store, this.api);

  final HotelStore store;
  final ApiClient api;

  /// The signed-in account as the backend describes it (hotel, role).
  Map<String, dynamic>? me;

  int? get hotelId => me?['hotelId'] as int?;

  // ---------------------------------------------------------------------------
  // Session (US-01)
  // ---------------------------------------------------------------------------

  Future<SignInOutcome> signIn(String email, String password) async {
    final data = await api.post('/authentication/sign-in', {
      'email': email.trim(),
      'password': password,
      'rememberMe': true,
    }) as Map<String, dynamic>;
    if (data['token'] != null) return SignedIn(await _startSession(data));
    final mfaToken = data['mfaToken'] as String;
    final account = data['email']?.toString() ?? email.trim();
    if (data['mfaEnrollmentRequired'] == true) return MfaEnrollmentNeeded(mfaToken, account);
    return MfaCodeNeeded(mfaToken, account);
  }

  Future<MfaEnrollment> startMfaEnrollment(String mfaToken) async {
    final data = await api.post('/authentication/mfa/enrollment', null, mfaToken) as Map<String, dynamic>;
    return MfaEnrollment(data['secret'] as String, data['otpAuthUri'] as String);
  }

  /// Confirms the authenticator with its first code. Returns the recovery codes, shown only once.
  Future<List<String>> confirmMfaEnrollment(String mfaToken, String code) async {
    final data = await api.post('/authentication/mfa/enrollment/confirm', {'code': code.trim()}, mfaToken)
        as Map<String, dynamic>;
    await _startSession(data);
    return [for (final item in (data['recoveryCodes'] as List? ?? const [])) item.toString()];
  }

  Future<AppUser> verifyMfa(String mfaToken, {String? code, String? recoveryCode}) async {
    final data = await api.post('/authentication/mfa/verify', {
      if (code != null) 'code': code.trim(),
      if (recoveryCode != null) 'recoveryCode': recoveryCode.trim().toUpperCase(),
    }, mfaToken) as Map<String, dynamic>;
    return _startSession(data);
  }

  Future<AppUser> _startSession(Map<String, dynamic> data) async {
    api.setSession(ApiSession(data['token'] as String, data['refreshToken'] as String?));
    return _loadCurrentUser();
  }

  /// Resumes a saved session. Returns null when it is no longer valid.
  Future<AppUser?> restore(ApiSession session) async {
    api.session = session;
    try {
      return await _loadCurrentUser();
    } on ApiException {
      api.setSession(null);
      return null;
    }
  }

  Future<AppUser> _loadCurrentUser() async {
    me = await api.get('/users/me') as Map<String, dynamic>;
    final user = _user(me!);
    _upsertUser(user);
    store.currentUser = user;
    await sync();
    return user;
  }

  Future<void> signOut() async {
    final refresh = api.session?.refreshToken;
    if (refresh != null) {
      try {
        await api.post('/authentication/sign-out', {'refreshToken': refresh});
      } on ApiException {
        // The local session ends anyway.
      }
    }
    api.setSession(null);
    _forgetSession();
    store.signOut();
  }

  /// What was copied for the account that signed out.
  void _forgetSession() {
    me = null;
    _preferencesLoaded = false;
    _conversationOf.clear();
    _loadedUpTo.clear();
  }

  Future<String> signUpGuest({required String name, required String email, required String password}) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) throw const DomainException('Escribe tu nombre y tu apellido.');
    final data = await api.post('/authentication/sign-up', {
      'firstName': parts.first,
      'lastName': parts.skip(1).join(' '),
      'email': email.trim(),
      'password': password,
      'role': 'guest',
    }) as Map<String, dynamic>;
    return data['message']?.toString() ?? 'Te enviamos un enlace para verificar tu correo.';
  }

  /// Accepts the whole link or just its `token`.
  Future<void> verifyEmail(String linkOrToken) =>
      api.post('/authentication/verify-email', {'token': _tokenFrom(linkOrToken)});

  Future<void> resendVerification(String email) =>
      api.post('/authentication/verify-email/resend', {'email': email.trim()});

  Future<void> requestPasswordReset(String email) =>
      api.post('/authentication/password-recovery', {'email': email.trim()});

  Future<void> resetPassword(String linkOrToken, String newPassword) =>
      api.post('/authentication/password-reset', {'token': _tokenFrom(linkOrToken), 'newPassword': newPassword});

  Future<void> changePassword(String current, String newPassword) =>
      api.post('/users/change-password', {'currentPassword': current, 'newPassword': newPassword});

  /// Ends every session of the account, on every device (this one included).
  Future<void> signOutEverywhere() async {
    try {
      await api.post('/authentication/sign-out-all');
    } finally {
      api.setSession(null);
      _forgetSession();
      store.signOut();
    }
  }

  static String _tokenFrom(String linkOrToken) {
    final text = linkOrToken.trim();
    final match = RegExp(r'[?&]token=([^&\s]+)').firstMatch(text);
    return match == null ? text : Uri.decodeComponent(match.group(1)!);
  }

  // ---------------------------------------------------------------------------
  // Sync: backend → store
  // ---------------------------------------------------------------------------

  bool get _isAdmin => store.currentUser?.role == UserRole.admin;

  /// Every hotel staff member sees the incidents of their hotel (a chain admin would have to pick one).
  bool get _seesIncidents => (store.currentUser?.role.isStaff ?? false) && hotelId != null;

  /// The backend has the cleaning tasks (US-05 / US-06). False until a sync finds them, and on backends without the
  /// housekeeping module: there the tasks stay on this device as before.
  bool hasCleaningTasks = false;

  /// Housekeeping, reception and administrators (not maintenance).
  bool get _seesCleaningTasks =>
      const {UserRole.admin, UserRole.reception, UserRole.housekeeping}.contains(store.currentUser?.role) && hotelId != null;

  /// The backend has the preventive maintenance plans (US-30) and generates their tasks itself.
  bool hasPreventivePlans = false;

  /// The backend has the guest requests (US-11 / US-19).
  bool hasGuestRequests = false;

  /// The backend has the conversations (US-12 / US-20).
  bool hasConversations = false;

  /// The backend has the guest folios, the check-out and the receipts (US-14 to US-17).
  bool hasFolios = false;

  /// The backend has the shifts and their swaps (US-31).
  bool hasShifts = false;

  /// The backend has the shift handovers (US-32).
  bool hasHandovers = false;

  /// The backend has the service catalog of the hotel (US-33): the screens use it instead of the demo catalog.
  bool hasServiceCatalog = false;

  /// The backend keeps the evaluations of the stays (US-21, US-26).
  bool hasStayReviews = false;

  /// The backend sends the staff reports by e-mail on a schedule (US-34).
  bool hasReportSchedules = false;

  /// The administrator's panel as the backend calculated it in the last sync (US-18); null without it.
  DashboardSnapshot? dashboard;

  bool get _seesPayments {
    final role = store.currentUser?.role;
    return role == UserRole.admin || role == UserRole.reception || role == UserRole.guest;
  }

  /// Copies users, rooms, bookings and payments from the backend into the store.
  Future<void> sync() async {
    final rooms = (await api.get('/rooms') as List).cast<Map<String, dynamic>>();
    final bookings = (await api.get('/bookings') as List).cast<Map<String, dynamic>>();
    final users = _isAdmin ? (await api.get('/users') as List).cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[];

    final visibleRooms = rooms.where((r) => hotelId == null || r['hotelId'] == hotelId).map(_room).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    if (!hasCleaningTasks) {
      for (final room in visibleRooms) {
        // The backend has one Cleaning status; a cleaning already started on a device stays "en limpieza".
        final local = store.rooms.where((r) => r.id == room.id).firstOrNull;
        if (room.status == RoomStatus.dirty && local?.status == RoomStatus.cleaning) room.status = RoomStatus.cleaning;
      }
    }
    store.rooms
      ..clear()
      ..addAll(visibleRooms);
    if ((store.currentUser?.role.isStaff ?? false) && hotelId != null) await _applyRoomMap();

    for (final data in users.where((u) => hotelId == null || u['hotelId'] == hotelId || u['hotelId'] == null)) {
      _upsertUser(_user(data));
    }

    final activeBookings = bookings.where((b) => b['status'] != 'Cancelled').toList();
    final stays = <Stay>[];
    for (final booking in activeBookings) {
      final previous = store.stays.where((s) => s.id == booking['id']).firstOrNull;
      stays.add(_stay(booking, previous));
    }
    store.stays
      ..clear()
      ..addAll(stays);

    // US-08 / US-09: the backend has the incidents of the hotel. US-30: and its preventive plans, whose tasks arrive
    // as incidents of kind Preventive; on a backend without plans the preventive work stays on this device.
    if (_seesIncidents) {
      try {
        try {
          final plans = (await api.get('/preventive-maintenance-plans?hotelId=$hotelId') as List).cast<Map<String, dynamic>>();
          store.preventiveTasks
            ..clear()
            ..addAll(plans.where((data) => data['isActive'] != false).map(_preventivePlan));
          hasPreventivePlans = true;
        } on ApiException catch (e) {
          if (e.statusCode != 404) rethrow;
          hasPreventivePlans = false;
        }
        final incidents = (await api.get('/incidents?limit=500') as List).cast<Map<String, dynamic>>();
        final previous = {for (final i in store.incidents) i.id: i};
        store.incidents
          ..removeWhere((i) => hasPreventivePlans || !i.preventive)
          ..addAll(incidents.map((data) => _incident(data, previous[data['id']])));
      } on ApiException catch (e) {
        // A backend without the incidents module (an older local one) keeps them on this device.
        if (e.statusCode != 404) rethrow;
      }
      // US-23: escalations and recurrences the backend raised, with how each incident ended.
      if (_isAdmin) {
        try {
          final alerts = (await api.get('/incidents/alerts?hotelId=$hotelId') as List).cast<Map<String, dynamic>>();
          store.alerts
            ..removeWhere((a) => a.incidentId != null)
            ..addAll(alerts.map(_alert));
        } on ApiException catch (e) {
          if (e.statusCode != 404) rethrow;
        }
      }
    }

    // US-05 / US-06: with the backend's cleaning tasks the checklist still lives on this device (it has none).
    if (_seesCleaningTasks) {
      try {
        final tasks = (await api.get('/cleaning-tasks?limit=500') as List).cast<Map<String, dynamic>>();
        final previous = {for (final t in store.tasks) t.id: t};
        store.tasks
          ..clear()
          ..addAll(tasks.where((data) => data['status'] != 'Cancelled').map((data) => _task(data, previous[data['id']])));
        hasCleaningTasks = true;
        if (store.currentUser?.role != UserRole.housekeeping) {
          final settings = await api.get('/cleaning-tasks/settings') as Map<String, dynamic>;
          store.autoAssignCleaning = settings['autoAssign'] == true;
        }
      } on ApiException catch (e) {
        // A backend without the housekeeping module keeps the tasks on this device.
        if (e.statusCode != 404) rethrow;
        hasCleaningTasks = false;
      }
    }
    if (hasCleaningTasks) {
      // The backend has one Cleaning status: a room whose task was started is "en limpieza".
      for (final room in store.rooms.where((r) => r.status == RoomStatus.dirty)) {
        if (store.tasks.any((t) => t.roomId == room.id && t.status == TaskStatus.inProgress)) room.status = RoomStatus.cleaning;
      }
    }

    // US-11 / US-19: a guest's own requests; the staff those of the hotel.
    if (hotelId != null || store.currentUser?.role == UserRole.guest) {
      try {
        final requests = (await api.get('/guest-requests?limit=500') as List).cast<Map<String, dynamic>>();
        final previous = {for (final r in store.requests) r.id: r};
        store.requests
          ..clear()
          ..addAll(requests.where((data) => _requestStatus(data['status']) != null).map((data) => _request(data, previous[data['id']])));
        hasGuestRequests = true;
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        hasGuestRequests = false;
      }
    }

    // US-31 / US-32: the shifts of the next two weeks, their swaps and the shift handovers.
    if (store.currentUser?.role.isStaff ?? false) {
      try {
        await _syncShifts();
        hasShifts = true;
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        hasShifts = false;
      }
      try {
        final handovers = (await api.get('/shift-handovers?limit=30') as List).cast<Map<String, dynamic>>();
        store.handovers
          ..clear()
          ..addAll(handovers.map(_handover));
        hasHandovers = true;
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        hasHandovers = false;
      }
    }

    // US-22: what the user chose to be notified about.
    if (store.currentUser case final user?) {
      try {
        await _loadNotificationPreferences(user);
      } on ApiException {
        // The switches stay as they are.
      }
    }

    // US-12 / US-20: the area channels and the guests' conversations with the front desk.
    try {
      await _syncConversations();
      hasConversations = true;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      hasConversations = false;
    }

    if (_seesPayments) {
      // The folio payments (kind charges) are replaced stay by stay with their folio.
      store.payments.removeWhere((p) => p.kind != PaymentKind.charges || !store.stays.any((s) => s.id == p.stayId));
      for (final booking in activeBookings.where((b) => b['confirmedAt'] != null || b['status'] != 'Pending')) {
        try {
          final payment = await api.get('/payments/booking/${booking['id']}') as Map<String, dynamic>;
          store.payments.add(_payment(payment));
        } on ApiException catch (e) {
          if (e.statusCode != 404) rethrow;
        }
      }
      // US-15 / US-16: the folio of each stay in the hotel (additional charges, their payments and the deposit).
      // A guest also keeps the folio of the stays already finished (their account summary).
      final guest = store.currentUser?.role == UserRole.guest;
      for (final stay in store.stays.where((s) => s.status == StayStatus.checkedIn || (guest && s.status == StayStatus.checkedOut))) {
        try {
          _applyFolio(stay, await api.get('/bookings/${stay.id}/folio') as Map<String, dynamic>);
          hasFolios = true;
        } on ApiException catch (e) {
          // A backend without folios answers 404: the stay keeps the charges of this device.
          if (e.statusCode != 404) rethrow;
        }
      }
      // The access code is only given to the guest of the booking.
      if (store.currentUser?.role == UserRole.guest) {
        for (final stay in store.stays.where((s) => s.status == StayStatus.checkedIn && s.accessCode == null)) {
          try {
            final checkIn = await api.get('/bookings/${stay.id}/check-in') as Map<String, dynamic>;
            stay.accessCode = checkIn['accessCode']?.toString();
          } on ApiException {
            // Without the code the key screen shows dashes; the check-in itself is still valid.
          }
        }
      }
    }

    // Sprint 4: catalog, evaluations, scheduled reports and the administrator's panel.
    await syncReports();
    store.refresh();
  }

  void _upsertUser(AppUser user) {
    final index = store.users.indexWhere((u) => u.id == user.id);
    if (index < 0) {
      store.users.add(user);
      return;
    }
    final existing = store.users[index];
    existing
      ..name = user.name
      ..email = user.email
      ..role = user.role
      ..active = user.active;
    if (store.currentUser?.id == user.id) store.currentUser = existing;
  }

  static UserRole _role(String value) => switch (value) {
        'reception' => UserRole.reception,
        'housekeeping' => UserRole.housekeeping,
        'maintenance' => UserRole.maintenance,
        'guest' => UserRole.guest,
        _ => UserRole.admin, // admin and chain_admin
      };

  static String roleName(UserRole role) => switch (role) {
        UserRole.admin => 'admin',
        UserRole.reception => 'reception',
        UserRole.housekeeping => 'housekeeping',
        UserRole.maintenance => 'maintenance',
        UserRole.guest => 'guest',
      };

  static AppUser _user(Map<String, dynamic> data) {
    final email = data['email']?.toString() ?? '';
    final name = [data['firstName'], data['lastName']].whereType<String>().join(' ').trim();
    return AppUser(
      id: data['id'] as int,
      name: name.isEmpty ? email.split('@').first : name,
      email: email,
      role: _role(data['role']?.toString() ?? 'guest'),
      password: '',
      active: (data['status'] ?? 'Active') == 'Active',
    );
  }

  static RoomType _roomType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('suite')) return RoomType.suite;
    if (lower.contains('dobl') || lower.contains('double') || lower.contains('twin')) return RoomType.twin;
    return RoomType.standard;
  }

  /// The backend has a single Cleaning status: the app shows it as pending cleaning.
  static RoomStatus _roomStatus(String value) => switch (value) {
        'Occupied' => RoomStatus.occupied,
        'Cleaning' => RoomStatus.dirty,
        'Maintenance' => RoomStatus.maintenance,
        _ => RoomStatus.available,
      };

  static String backendRoomStatus(RoomStatus status) => switch (status) {
        RoomStatus.available => 'Available',
        RoomStatus.occupied => 'Occupied',
        RoomStatus.dirty || RoomStatus.cleaning => 'Cleaning',
        RoomStatus.maintenance => 'Maintenance',
      };

  static Room _room(Map<String, dynamic> data) {
    final number = data['number']?.toString() ?? '${data['id']}';
    final digits = RegExp(r'^\d+').firstMatch(number)?.group(0) ?? '';
    return Room(
      id: data['id'] as int,
      number: number,
      floor: digits.length >= 3 ? int.parse(digits.substring(0, digits.length - 2)) : 1,
      type: _roomType(data['roomTypeName']?.toString() ?? ''),
      status: _roomStatus(data['status']?.toString() ?? 'Available'),
    )
      ..roomTypeId = data['roomTypeId'] as int?
      ..typeName = data['roomTypeName']?.toString() ?? ''
      ..price = (data['price'] as num?)?.toDouble()
      ..description = data['description']?.toString() ?? ''
      ..amenities = [for (final a in (data['amenities'] as List? ?? const [])) a.toString()];
  }

  /// US-04: the room map of the hotel says which statuses each room can go to and which have been in maintenance too
  /// long. A backend without it leaves every status open.
  Future<void> _applyRoomMap() async {
    try {
      final map = await api.get('/rooms/map?hotelId=$hotelId') as Map<String, dynamic>;
      final items = {for (final item in (map['rooms'] as List? ?? const []).cast<Map<String, dynamic>>()) item['id']: item};
      for (final room in store.rooms) {
        final item = items[room.id];
        if (item == null) continue;
        room
          ..allowedNext = {
            for (final status in (item['allowedNextStatuses'] as List? ?? const [])) _roomStatus(status.toString()),
            // Housekeeping's "en limpieza" is the backend's Cleaning too.
            if ((item['allowedNextStatuses'] as List? ?? const []).contains('Cleaning')) RoomStatus.cleaning,
          }
          ..maintenanceOverdue = item['maintenanceOverdue'] == true;
      }
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  Stay _stay(Map<String, dynamic> data, Stay? previous) {
    final checkIn = DateTime.parse(data['checkInDate'].toString());
    final checkOut = DateTime.parse(data['checkOutDate'].toString());
    final room = store.rooms.where((r) => r.id == data['roomId']).firstOrNull;
    final stay = Stay(
      id: data['id'] as int,
      guestUserId: data['userId'] as int?,
      guestName: data['guestName']?.toString() ?? '',
      guestEmail: data['guestEmail']?.toString() ?? '',
      roomType: room?.type ?? RoomType.standard,
      roomId: data['roomId'] as int?,
      checkIn: DateTime(checkIn.year, checkIn.month, checkIn.day, 15),
      checkOut: DateTime(checkOut.year, checkOut.month, checkOut.day, 12),
      status: switch (data['status']) {
        'CheckedIn' => StayStatus.checkedIn,
        'Completed' => StayStatus.checkedOut,
        _ => StayStatus.reserved,
      },
      // The backend has no guarantee deposit: nothing to hold.
      depositRequired: 0,
      digital: data['checkedInAt'] != null,
    )
      ..code = data['code']?.toString()
      ..awaitingPayment = data['status'] == 'Pending'
      ..paymentDueAt = DateTime.tryParse(data['paymentDueAt']?.toString() ?? '')?.toLocal()
      ..paymentInstructions = (data['paymentInstructions'] as Map?)?.cast<String, dynamic>() ?? previous?.paymentInstructions
      ..accessCode = previous?.accessCode
      ..checkedInAt = DateTime.tryParse(data['checkedInAt']?.toString() ?? '')?.toLocal();
    final nights = (data['nights'] as num?)?.toInt() ?? stay.nights;
    stay.charges.add(FolioCharge(
      id: stay.id,
      description: 'Cargo de habitación · $nights ${nights == 1 ? 'noche' : 'noches'}',
      amount: (data['totalPrice'] as num).toDouble(),
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? store.now,
    ));
    // Charges added on this device (services) are kept until the backend has a folio.
    if (previous != null) stay.charges.addAll(previous.charges.where((c) => c.id != stay.id));
    return stay;
  }

  static Payment _payment(Map<String, dynamic> data) => Payment(
        id: data['id'] as int,
        stayId: data['bookingId'] as int,
        amount: (data['amount'] as num).toDouble(),
        method: _methodLabel(data['method']?.toString() ?? ''),
        kind: PaymentKind.reservation,
        status: switch (data['status']) {
          'Failed' => PaymentStatus.rejected,
          'Refunded' => PaymentStatus.refunded,
          _ => PaymentStatus.approved,
        },
        createdAt: DateTime.tryParse('${data['paymentDate']}Z'.replaceFirst(' ', 'T'))?.toLocal() ?? DateTime.now(),
      );

  static Priority incidentPriority(String value) => switch (value) {
        'Low' => Priority.low,
        'High' => Priority.high,
        'Critical' => Priority.urgent,
        _ => Priority.normal, // Medium
      };

  static String backendIncidentPriority(Priority priority) => switch (priority) {
        Priority.low => 'Low',
        Priority.normal => 'Medium',
        Priority.high => 'High',
        Priority.urgent => 'Critical',
      };

  /// The backend has no categories: its incidents show none. The history only comes with a single incident; the
  /// list keeps the one already loaded.
  Incident _incident(Map<String, dynamic> data, [Incident? previous]) {
    final incident = Incident(
      id: data['id'] as int,
      roomId: data['roomId'] as int,
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      category: '',
      urgency: incidentPriority(data['priority']?.toString() ?? ''),
      reportedById: data['reportedByUserId'] as int,
      createdAt: DateTime.parse(data['reportedAt'].toString()).toLocal(),
      status: switch (data['status']) {
        'InProgress' => WorkStatus.inProgress,
        'Resolved' => WorkStatus.resolved,
        _ => WorkStatus.pending,
      },
      assigneeId: data['assigneeUserId'] as int?,
      blocksRoom: data['blocksRoom'] == true,
      escalated: data['escalatedAt'] != null,
      // US-30: generated by a preventive plan of the backend. US-10: more than 3 similar ones in a month.
      preventive: data['kind'] == 'Preventive',
      recurring: data['isRecurring'] == true,
      resolutionNotes: data['resolutionNotes']?.toString() ?? '',
    )
      ..resolvedAt = DateTime.tryParse(data['resolvedAt']?.toString() ?? '')?.toLocal()
      ..reportedByEmail = data['reportedByEmail']?.toString();
    final history = data['history'];
    if (history is List) {
      incident.events.addAll([
        for (final entry in history.cast<Map<String, dynamic>>())
          TimelineEvent(DateTime.parse(entry['occurredAt'].toString()).toLocal(), _incidentEventText(entry)),
      ]);
    } else if (previous != null) {
      incident.events.addAll(previous.events);
    }
    return incident;
  }

  /// The backend's `detail` is in English: the text is rebuilt in Spanish from the action.
  String _incidentEventText(Map<String, dynamic> entry) {
    final by = entry['actorEmail'] == null ? '' : ' · ${entry['actorEmail']}';
    final detail = entry['detail']?.toString() ?? '';
    switch (entry['action']) {
      case 'Reported':
        return 'Reportada$by';
      case 'Assigned':
        final assignee = int.tryParse(RegExp(r'\d+$').firstMatch(detail)?.group(0) ?? '');
        final name = store.userById(assignee)?.name;
        return '${name == null ? 'Asignada' : 'Asignada a $name'}$by';
      case 'Started':
        return 'En proceso$by';
      case 'PriorityChanged':
        final parts = detail.split('→').map((p) => incidentPriority(p.trim()).label).toList();
        return '${parts.length == 2 ? 'Prioridad: ${parts[0]} → ${parts[1]}' : 'Prioridad cambiada'}$by';
      case 'Escalated':
        return 'Escalada al administrador por demora';
      case 'Resolved':
        return 'Resuelta${detail.isEmpty ? '' : ': $detail'}$by';
      default:
        return '${entry['action']}$by';
    }
  }

  /// Puts the incident the backend answered (with its history) in the store.
  void _upsertIncident(Map<String, dynamic> data) {
    final previous = store.incidents.where((i) => i.id == data['id']).firstOrNull;
    final incident = _incident(data, previous);
    store.incidents
      ..remove(previous)
      ..add(incident);
    store.refresh();
  }

  static String _methodLabel(String value) =>
      kPaymentMethods.where((m) => m.value == value).firstOrNull?.label ?? value;

  // ---------------------------------------------------------------------------
  // Actions the backend supports
  // ---------------------------------------------------------------------------

  /// US-04 / US-06: allowed transitions are enforced by the backend.
  Future<void> changeRoomStatus(Room room, RoomStatus status) async {
    await api.patch('/rooms/${room.id}/status', {'status': backendRoomStatus(status)});
    await sync();
  }

  /// Fire-and-forget version used by the on-device workflows (cleaning, incidents). If the backend refuses the
  /// transition, the next sync brings back its status.
  Future<void> pushRoomStatus(Room room) async {
    try {
      await api.patch('/rooms/${room.id}/status', {'status': backendRoomStatus(room.status)});
    } on ApiException {
      // The periodic sync reconciles.
    }
  }

  /// Status changes of a room, newest first (who and when).
  Future<List<({DateTime at, String from, String to, String by})>> roomStatusHistory(int roomId) async {
    final data = (await api.get('/rooms/$roomId/status-history') as List).cast<Map<String, dynamic>>();
    return [
      for (final item in data)
        (
          at: DateTime.parse(item['changedAt'].toString()).toLocal(),
          from: _roomStatus(item['fromStatus'].toString()).label,
          to: _roomStatus(item['toStatus'].toString()).label,
          by: item['origin'] == 'CheckIn' ? 'Check-in del huésped' : (item['changedByEmail']?.toString() ?? 'Personal'),
        ),
    ];
  }

  /// US-03: the backend e-mails a verification link to the new collaborator.
  Future<void> createStaff({required String name, required String email, required UserRole role, required String password}) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) throw const DomainException('Escribe nombre y apellido del colaborador.');
    await api.post('/users', {
      'firstName': parts.first,
      'lastName': parts.skip(1).join(' '),
      'email': email.trim(),
      'password': password,
      'role': roleName(role),
      'hotelId': hotelId,
    });
    await sync();
  }

  Future<void> setActive(AppUser user, bool active) async {
    if (active) {
      await api.post('/users/${user.id}/activate');
    } else {
      await api.delete('/users/${user.id}');
    }
    await sync();
  }

  Future<void> changeRole(AppUser user, UserRole role) async {
    await api.post('/users/${user.id}/assign-role', {'targetUserId': user.id, 'newRole': roleName(role)});
    await sync();
  }

  /// Removes the authenticator and recovery codes of a collaborator (e.g. a lost phone) and ends their sessions:
  /// at the next sign-in they enroll a new one.
  Future<void> resetMfa(AppUser user) => api.post('/users/${user.id}/mfa/reset');

  /// How the guests of the hotel pay their bookings. Every field is null until the admin configures it.
  Future<HotelPaymentSettings> paymentSettings() async =>
      HotelPaymentSettings.fromJson(await api.get('/hotels/${_ownHotelId()}/payment-settings') as Map<String, dynamic>);

  /// Replaces the payment methods of the hotel: from then on it accepts bookings. Blank fields are not offered.
  Future<HotelPaymentSettings> updatePaymentSettings(HotelPaymentSettings settings) async =>
      HotelPaymentSettings.fromJson(
          await api.put('/hotels/${_ownHotelId()}/payment-settings', settings.toJson()) as Map<String, dynamic>);

  int _ownHotelId() => hotelId ?? (throw const DomainException('Tu cuenta no pertenece a un hotel.'));

  /// US-27: a booking made at the desk for a guest without an account.
  Future<Stay> createBooking({required int roomId, required DateTime checkIn, required int nights, required String guestName, required String guestEmail}) async {
    final start = DateUtils.dateOnly(checkIn);
    final data = await api.post('/bookings', {
      'roomId': roomId,
      'checkInDate': _date(start),
      'checkOutDate': _date(start.add(Duration(days: nights))),
      'guestName': guestName.trim(),
      'guestEmail': guestEmail.trim(),
    }) as Map<String, dynamic>;
    await sync();
    return store.stayById(data['id'] as int);
  }

  /// US-15: the front desk registers the payment of a pending booking (it becomes Confirmed).
  Future<void> registerPayment(int bookingId, {required String method, String operationNumber = '', String note = ''}) async {
    await api.post('/bookings/$bookingId/payments', {
      'method': method,
      if (operationNumber.trim().isNotEmpty) 'operationNumber': operationNumber.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    await sync();
  }

  /// US-13: the guest's digital check-in with a photo of the identity document. Returns the access code.
  Future<String?> completeCheckIn(int bookingId, {required String documentType, required String documentNumber,
      required String nationality, required Uint8List document, required String fileName}) async {
    final data = await api.postMultipart('/bookings/$bookingId/check-in', {
      'documentType': documentType,
      'documentNumber': documentNumber.trim(),
      'nationality': nationality.trim().toUpperCase(),
    }, fileField: 'document', bytes: document, fileName: fileName) as Map<String, dynamic>;
    final code = data['accessCode']?.toString();
    await sync();
    store.stays.where((s) => s.id == bookingId).firstOrNull?.accessCode = code;
    store.refresh();
    return code;
  }

  /// US-13, escenario 4: help from reception during the check-in.
  Future<void> requestCheckInAssistance(int bookingId, String message) =>
      api.post('/bookings/$bookingId/check-in/assistance', {'message': message.trim()});

  /// Only Pending or Confirmed bookings, before the check-in day. A paid booking gets its payment refunded.
  Future<void> cancelBooking(int bookingId) async {
    await api.post('/bookings/$bookingId/cancel');
    await sync();
  }

  // ---------------------------------------------------------------------------
  // Incidents (US-08 / US-09)
  // ---------------------------------------------------------------------------

  /// US-08: maintenance is notified by the backend; with [blocksRoom] the room goes to Maintenance.
  Future<void> reportIncident({required int roomId, required String title, required String description,
      required Priority urgency, required bool blocksRoom}) async {
    if (title.trim().isEmpty) throw const DomainException('Describe brevemente la incidencia.');
    final data = await api.post('/incidents', {
      'roomId': roomId,
      'title': title.trim(),
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'priority': backendIncidentPriority(urgency),
      'blocksRoom': blocksRoom,
    }) as Map<String, dynamic>;
    _upsertIncident(data);
    // The room may have gone to Maintenance.
    await sync();
  }

  /// US-06: damage found while cleaning goes to maintenance as an incident that blocks the room; the task keeps a
  /// note of it.
  Future<void> reportImpediment(int taskId, {required String description, required Priority urgency}) async {
    if (description.trim().isEmpty) throw const DomainException('Describe el desperfecto que encontraste.');
    if (hasCleaningTasks) {
      return _taskAction(() => api.post('/cleaning-tasks/$taskId/impediments', {
            'title': 'Desperfecto detectado en limpieza',
            'description': description.trim(),
            'priority': backendIncidentPriority(urgency),
            'blocksRoom': true,
          }));
    }
    final task = store.taskById(taskId);
    await reportIncident(
      roomId: task.roomId,
      title: 'Desperfecto detectado en limpieza',
      description: description,
      urgency: urgency,
      blocksRoom: true,
    );
    task.events.add(TimelineEvent(store.now, 'Impedimento reportado: ${description.trim()}'));
    store.refresh();
  }

  /// The incident with its history.
  Future<void> refreshIncident(int incidentId) async =>
      _upsertIncident(await api.get('/incidents/$incidentId') as Map<String, dynamic>);

  /// Pending → InProgress. A maintenance staff member starting an unassigned incident takes it.
  Future<void> startIncident(int incidentId) => _incidentAction(() => api.post('/incidents/$incidentId/start'));

  /// When it blocked its room and nothing else does, the backend sends the room to Cleaning and creates its cleaning
  /// task; a backend without the housekeeping module leaves the task to this device.
  Future<void> resolveIncident(int incidentId, String notes) async {
    if (notes.trim().isEmpty) throw const DomainException('Agrega observaciones sobre la solución.');
    await _incidentAction(() => api.post('/incidents/$incidentId/resolve', {'resolutionNotes': notes.trim()}));
    final room = store.roomById(store.incidentById(incidentId).roomId);
    if (!hasCleaningTasks && room.status == RoomStatus.dirty) store.createCleaningTask(room.id, priority: Priority.high);
  }

  /// Only an administrator assigns to someone else; maintenance takes an incident with [startIncident].
  Future<void> assignIncident(int incidentId, int userId) =>
      _incidentAction(() => api.post('/incidents/$incidentId/assign', {'assigneeUserId': userId}));

  Future<void> changeIncidentPriority(int incidentId, Priority urgency) => _incidentAction(
      () => api.put('/incidents/$incidentId/priority', {'priority': backendIncidentPriority(urgency)}));

  Future<void> _incidentAction(Future<dynamic> Function() call) async {
    _upsertIncident(await call() as Map<String, dynamic>);
    // The room may have changed too (Maintenance → Cleaning).
    await sync();
  }

  // ---------------------------------------------------------------------------
  // Guest requests (US-11 / US-19), when the backend has them ([hasGuestRequests])
  // ---------------------------------------------------------------------------

  /// The guest-request and messaging enums travel as numbers (Reception = 0, Housekeeping = 1, Maintenance = 2);
  /// names are accepted too.
  static Area area(Object? value) => switch (value) {
        0 || 'Reception' => Area.reception,
        2 || 'Maintenance' => Area.maintenance,
        _ => Area.housekeeping,
      };

  static int backendArea(Area area) => switch (area) {
        Area.reception => 0,
        Area.housekeeping => 1,
        Area.maintenance => 2,
      };

  /// Null for a cancelled request: it leaves the lists.
  static WorkStatus? _requestStatus(Object? value) => switch (value) {
        1 || 'InProgress' => WorkStatus.inProgress,
        2 || 'Resolved' => WorkStatus.resolved,
        3 || 'Cancelled' => null,
        _ => WorkStatus.pending,
      };

  GuestRequest _request(Map<String, dynamic> data, [GuestRequest? previous]) {
    final createdAt = DateTime.parse(data['createdAt'].toString()).toLocal();
    final eta = DateTime.tryParse(data['estimatedAttentionBy']?.toString() ?? '')?.toLocal();
    final title = data['title']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';
    final requestArea = area(data['area']);
    final request = GuestRequest(
      id: data['id'] as int,
      roomId: data['roomId'] as int,
      stayId: data['bookingId'] as int?,
      description: description.isEmpty ? title : '$title · $description',
      area: requestArea,
      createdAt: createdAt,
      etaMinutes: eta == null ? requestArea.etaMinutes : eta.difference(createdAt).inMinutes.clamp(1, 24 * 60),
      createdById: data['createdByUserId'] as int,
      status: _requestStatus(data['status']) ?? WorkStatus.pending,
    )
      ..resolvedAt = DateTime.tryParse(data['resolvedAt']?.toString() ?? '')?.toLocal()
      ..assigneeId = data['assigneeUserId'] as int?;
    final history = data['history'];
    if (history is List) {
      request.events.addAll([
        for (final entry in history.cast<Map<String, dynamic>>())
          TimelineEvent(DateTime.parse(entry['occurredAt'].toString()).toLocal(), _requestEventText(entry)),
      ]);
    } else if (previous != null) {
      request.events.addAll(previous.events);
    } else {
      request.events.add(TimelineEvent(createdAt, 'Registrada para ${requestArea.label}'));
    }
    return request;
  }

  String _requestEventText(Map<String, dynamic> entry) {
    final by = entry['actorEmail'] == null ? '' : ' · ${entry['actorEmail']}';
    final detail = entry['detail']?.toString() ?? '';
    return switch (entry['action']) {
      0 || 'Created' => 'Registrada para ${area(_areaIn(detail)).label}$by',
      1 || 'Routed' => 'Derivada a ${area(_areaIn(detail)).label}$by',
      2 || 'Assigned' => 'Asignada$by',
      3 || 'Started' => 'En proceso$by',
      4 || 'Resolved' => 'Atendida${detail.isEmpty ? '' : ': $detail'}$by',
      5 || 'Cancelled' => 'Cancelada${detail.isEmpty ? '' : ': $detail'}$by',
      final other => '$other$by',
    };
  }

  /// The area the English detail ends with: "For Housekeeping", "Reception → Maintenance".
  static String _areaIn(String detail) => detail.split(RegExp(r'→|\s')).lastWhere((w) => w.isNotEmpty, orElse: () => '');

  void _upsertRequest(Map<String, dynamic> data) {
    final previous = store.requests.where((r) => r.id == data['id']).firstOrNull;
    store.requests.remove(previous);
    if (_requestStatus(data['status']) != null) store.requests.add(_request(data, previous));
    store.refresh();
  }

  Future<void> _requestAction(Future<dynamic> Function() call) async => _upsertRequest(await call() as Map<String, dynamic>);

  /// Keeps a request as the backend answered it (used by the other backend modules).
  void upsertRequest(Map<String, dynamic> data) => _upsertRequest(data);

  /// The front desk registers a request for a room and the area that attends it. A guest sends it for the room of
  /// their stay: without [area] it reaches the front desk, which routes it.
  Future<void> createRequest({required String title, String description = '', Area? area, int? roomId}) async {
    final text = title.trim();
    if (text.length < 3) throw const DomainException('Describe la solicitud.');
    // The title holds up to 120 characters: a longer text goes whole in the description.
    final shortTitle = text.length <= 120 ? text : '${text.substring(0, 117)}...';
    final detail = [if (text.length > 120) text, if (description.trim().isNotEmpty) description.trim()].join('\n');
    await _requestAction(() => api.post('/guest-requests', {
          'title': shortTitle,
          if (detail.isNotEmpty) 'description': detail,
          if (area != null) 'area': backendArea(area),
          'roomId': ?roomId,
        }));
  }

  /// US-33: a service of the catalog goes to its area. Its cost is in the request: the guest cannot post charges, the
  /// front desk adds it to the folio.
  Future<void> requestService(ServiceItem service) {
    if (!service.available) throw const DomainException('Este servicio no está disponible por ahora.');
    return createRequest(
      title: 'Servicio: ${service.name}',
      description: service.price > 0 ? 'Cargo a la cuenta: \$${service.price.toStringAsFixed(2)}' : '',
      area: service.area,
    );
  }

  Future<void> routeRequest(int requestId, Area area) =>
      _requestAction(() => api.post('/guest-requests/$requestId/route', {'area': backendArea(area)}));

  /// The front desk puts someone of the request's area in charge; a member of the area takes it for themselves.
  Future<void> assignRequest(int requestId, int userId) =>
      _requestAction(() => api.post('/guest-requests/$requestId/assign', {'assigneeUserId': userId}));

  Future<void> startRequest(int requestId) => _requestAction(() => api.post('/guest-requests/$requestId/start'));

  Future<void> resolveRequest(int requestId, {String note = ''}) => _requestAction(
      () => api.post('/guest-requests/$requestId/resolve', {if (note.trim().isNotEmpty) 'note': note.trim()}));

  /// A guest withdraws a request nobody started; the front desk cancels any open one.
  Future<void> cancelRequest(int requestId, {String note = ''}) => _requestAction(
      () => api.post('/guest-requests/$requestId/cancel', {if (note.trim().isNotEmpty) 'note': note.trim()}));

  // ---------------------------------------------------------------------------
  // Messaging (US-12 / US-20), when the backend has it ([hasConversations])
  //
  // The screens keep talking in channels ('area:housekeeping', 'task:12', 'guest:<stay>'); each one is a conversation
  // of the backend.
  // ---------------------------------------------------------------------------

  /// Conversation of each channel, and the last message already copied of each conversation.
  final Map<String, int> _conversationOf = {};
  final Map<int, String?> _loadedUpTo = {};

  static const List<String> _subjects = ['CleaningTask', 'Incident', 'GuestRequest'];

  /// The channel the app uses for a conversation of the backend; null when it has no place in the app.
  String? _channelOf(Map<String, dynamic> conversation) {
    switch (conversation['kind']) {
      case 0 || 'GuestDesk':
        final guestId = conversation['guestUserId'] as int?;
        final stay = guestId == null ? null : store.activeStayOf(guestId);
        return stay == null ? null : HotelStore.guestChannel(stay.id);
      case 1 || 'AreaChannel':
        return HotelStore.areaChannel(area(conversation['area']));
      case 2 || 'TaskThread':
        final subject = conversation['subject'];
        final id = conversation['subjectId'];
        return switch (subject) {
          0 || 'CleaningTask' => HotelStore.taskChannel(id as int),
          1 || 'Incident' => 'incident:$id',
          2 || 'GuestRequest' => 'request:$id',
          _ => null,
        };
      default:
        return null;
    }
  }

  /// Lists my conversations and copies the messages of those with something new.
  Future<void> _syncConversations() async {
    final conversations = (await api.get('/conversations${hotelId == null ? '' : '?hotelId=$hotelId'}') as List)
        .cast<Map<String, dynamic>>();
    for (final conversation in conversations.take(40)) {
      final channel = _channelOf(conversation);
      if (channel == null) continue;
      final id = conversation['id'] as int;
      _conversationOf[channel] = id;
      final last = conversation['lastMessageAt']?.toString();
      if (last != null && _loadedUpTo[id] != last) await _loadConversation(channel, '/conversations/$id');
      _loadedUpTo[id] = last;
    }
  }

  /// The latest messages of a conversation replace the ones of its channel.
  Future<void> _loadConversation(String channel, String path) async {
    final data = await api.get('$path?limit=100') as Map<String, dynamic>;
    final conversation = data['conversation'] as Map<String, dynamic>;
    _conversationOf[channel] = conversation['id'] as int;
    _loadedUpTo[conversation['id'] as int] = conversation['lastMessageAt']?.toString();
    final messages = (data['messages'] as List).cast<Map<String, dynamic>>().reversed.map((m) => ChatMessage(
          id: (m['id'] as num).toInt(),
          channel: channel,
          authorId: m['senderUserId'] as int,
          authorName: m['senderName']?.toString() ?? '',
          text: m['body']?.toString() ?? '',
          createdAt: DateTime.parse(m['sentAt'].toString()).toLocal(),
        ));
    store.messages
      ..removeWhere((m) => m.channel == channel)
      ..addAll(messages);
    store.refresh();
  }

  /// Brings the messages of a channel when its screen opens (a task's comments are not in the list of conversations).
  Future<void> loadChannel(String channel) async {
    final parts = channel.split(':');
    final subject = switch (parts.first) { 'task' => 0, 'incident' => 1, 'request' => 2, _ => null };
    try {
      if (subject != null) {
        await _loadConversation(channel, '/conversations/threads/${_subjects[subject]}/${parts[1]}');
      } else if (_conversationOf[channel] case final id?) {
        await _loadConversation(channel, '/conversations/$id');
      }
    } on ApiException catch (e) {
      // Nobody has written yet.
      if (e.statusCode != 404) rethrow;
    }
  }

  /// Writes in a channel: the backend notifies the other side (the area, the assignee, the guest or the front desk).
  Future<void> sendMessage(String channel, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final parts = channel.split(':');
    final path = switch (parts.first) {
      'area' => '/conversations/areas/${const ['Reception', 'Housekeeping', 'Maintenance'][backendArea(Area.values.byName(parts[1]))]}/messages',
      'task' => '/conversations/threads/CleaningTask/${parts[1]}/messages',
      'incident' => '/conversations/threads/Incident/${parts[1]}/messages',
      'request' => '/conversations/threads/GuestRequest/${parts[1]}/messages',
      'guest' when store.currentUser?.role == UserRole.guest => '/conversations/front-desk/messages',
      _ => switch (_conversationOf[channel]) {
          final id? => '/conversations/$id/messages',
          null => throw const DomainException('Este huésped aún no escribió: la conversación empieza desde su app.'),
        },
    };
    final message = await api.post(path, {'body': body}) as Map<String, dynamic>;
    final conversationId = message['conversationId'] as int;
    _conversationOf[channel] = conversationId;
    await _loadConversation(channel, '/conversations/$conversationId');
  }

  // ---------------------------------------------------------------------------
  // Folio, check-out and receipts (US-14 to US-17), when the backend has them ([hasFolios])
  //
  // The room charge and the booking payment stay as before; the folio adds the additional charges and their payments
  // (negative ids, so they do not collide with the bookings' ones).
  // ---------------------------------------------------------------------------

  static const Map<String, String> chargeCategories = {
    'Minibar': 'Minibar',
    'RoomService': 'Room service',
    'Restaurant': 'Restaurante',
    'Laundry': 'Lavandería',
    'Spa': 'Spa',
    'Damage': 'Daños',
    'Other': 'Otro',
  };

  void _applyFolio(Stay stay, Map<String, dynamic> folio) {
    stay.charges
      ..removeWhere((c) => c.id != stay.id)
      ..addAll([
        for (final charge in (folio['charges'] as List? ?? const []).cast<Map<String, dynamic>>())
          FolioCharge(
            id: -(charge['id'] as num).toInt(),
            description: charge['description']?.toString() ?? '',
            amount: (charge['amount'] as num).toDouble(),
            createdAt: DateTime.parse(charge['postedAt'].toString()).toLocal(),
          ),
      ]);
    store.payments
      ..removeWhere((p) => p.stayId == stay.id && p.kind == PaymentKind.charges)
      ..addAll([
        for (final payment in (folio['payments'] as List? ?? const []).cast<Map<String, dynamic>>())
          Payment(
            id: -(payment['id'] as num).toInt(),
            stayId: stay.id,
            amount: (payment['amount'] as num).toDouble(),
            method: _methodLabel(payment['method']?.toString() ?? ''),
            kind: PaymentKind.charges,
            status: PaymentStatus.approved,
            createdAt: DateTime.parse(payment['paidAt'].toString()).toLocal(),
          ),
      ]);
    final deposit = folio['deposit'] as Map<String, dynamic>?;
    stay
      ..depositHeld = deposit == null || deposit['status'] == 'None' ? 0 : (deposit['amount'] as num).toDouble()
      ..depositRefunded = deposit?['status'] == 'Released';
    final invoice = folio['invoiceData'] as Map<String, dynamic>?;
    stay.fiscalData = invoice == null
        ? null
        : FiscalData(
            ruc: invoice['ruc']?.toString() ?? '',
            businessName: invoice['businessName']?.toString() ?? '',
            address: invoice['address']?.toString() ?? '',
          );
  }

  Receipt _receipt(Map<String, dynamic> data) => Receipt(
        id: data['id'] as int,
        paymentId: 0,
        stayId: data['bookingId'] as int,
        number: data['number']?.toString() ?? '',
        type: data['type']?.toString() ?? 'Boleta',
        email: data['customerEmail']?.toString() ?? '',
        amount: (data['total'] as num).toDouble(),
        createdAt: DateTime.parse(data['issuedAt'].toString()).toLocal(),
        fiscalData: data['customerDocument'] == null || data['type'] != 'Factura'
            ? null
            : FiscalData(
                ruc: data['customerDocument'].toString(),
                businessName: data['customerName']?.toString() ?? '',
                address: data['customerAddress']?.toString() ?? '',
              ),
        sentCount: (data['sentCount'] as num?)?.toInt() ?? 1,
      );

  /// The folio of a stay and its receipts (the detail screens; the sync brings only the folios of checked-in stays).
  Future<void> refreshFolio(int stayId) async {
    final stay = store.stayById(stayId);
    try {
      _applyFolio(stay, await api.get('/bookings/$stayId/folio') as Map<String, dynamic>);
      hasFolios = true;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    try {
      final receipts = (await api.get('/bookings/$stayId/receipts') as List).cast<Map<String, dynamic>>();
      store.receipts
        ..removeWhere((r) => r.stayId == stayId)
        ..addAll(receipts.map(_receipt));
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    store.refresh();
  }

  /// The front desk posts an additional charge (minibar, laundry...): the check-out waits until it is paid.
  Future<void> postCharge(int stayId, {required String description, required double amount, String category = 'Other'}) async {
    if (description.trim().isEmpty) throw const DomainException('Describe el cargo.');
    if (amount <= 0) throw const DomainException('Ingresa un monto mayor que cero.');
    await api.post('/bookings/$stayId/folio/charges', {'description': description.trim(), 'category': category, 'amount': amount});
    await refreshFolio(stayId);
  }

  /// US-15: the refundable guarantee deposit, held at check-in and released at check-out.
  Future<void> holdDeposit(int stayId, {required double amount, required String method, String operationNumber = ''}) async {
    await api.post('/bookings/$stayId/folio/deposit', {
      'amount': amount,
      'method': method,
      if (operationNumber.trim().isNotEmpty) 'operationNumber': operationNumber.trim(),
    });
    await refreshFolio(stayId);
  }

  /// US-16: pays the balance, split in up to 4 parts; every part gets its boleta or factura by e-mail.
  Future<void> payFolio(int stayId, List<({double amount, String method, String operationNumber})> parts) async {
    final data = await api.post('/bookings/$stayId/folio/payments', {
      'parts': [
        for (final part in parts)
          {
            'amount': double.parse(part.amount.toStringAsFixed(2)),
            'method': part.method,
            if (part.operationNumber.trim().isNotEmpty) 'operationNumber': part.operationNumber.trim(),
          },
      ],
    }) as Map<String, dynamic>;
    _applyFolio(store.stayById(stayId), data['folio'] as Map<String, dynamic>);
    await refreshFolio(stayId);
  }

  /// US-17: the receipts issued from now on are facturas to this RUC.
  Future<void> setInvoiceData(int stayId, FiscalData data) async {
    await api.put('/bookings/$stayId/folio/invoice-data', {
      'ruc': data.ruc.trim(),
      'businessName': data.businessName.trim(),
      if (data.address.trim().isNotEmpty) 'address': data.address.trim(),
    });
    await refreshFolio(stayId);
  }

  Future<void> resendReceipt(int receiptId) async {
    final data = await api.post('/receipts/$receiptId/resend') as Map<String, dynamic>?;
    if (data != null) {
      final receipt = _receipt(data);
      store.receipts
        ..removeWhere((r) => r.id == receipt.id)
        ..add(receipt);
      store.refresh();
    }
  }

  /// US-14 / US-27: the guest (from the app) or the front desk. Refused while the folio has a balance; the room goes
  /// to cleaning, the access code stops working, the deposit is released and the summary goes by e-mail.
  Future<void> checkOut(int stayId) async {
    await api.post('/bookings/$stayId/check-out');
    await sync();
    if (store.stays.any((s) => s.id == stayId)) await refreshFolio(stayId);
  }

  // ---------------------------------------------------------------------------
  // Shifts (US-31) and handovers (US-32), when the backend has them ([hasShifts], [hasHandovers])
  // ---------------------------------------------------------------------------

  /// The periods of the backend, with the label and hours the app shows.
  static const Map<String, (String, int, int)> shiftPeriods = {
    'Morning': ('Mañana', 7, 15),
    'Afternoon': ('Tarde', 15, 23),
    'Night': ('Noche', 23, 7),
  };

  static Area shiftArea(String? value) => switch (value) {
        'FrontDesk' => Area.reception,
        'Maintenance' => Area.maintenance,
        _ => Area.housekeeping,
      };

  static String backendShiftArea(Area area) => switch (area) {
        Area.reception => 'FrontDesk',
        Area.housekeeping => 'Housekeeping',
        Area.maintenance => 'Maintenance',
      };

  static Shift _shift(Map<String, dynamic> data) {
    final period = shiftPeriods[data['period']] ?? shiftPeriods['Morning']!;
    final date = DateTime.parse(data['date'].toString());
    final assignees = (data['assignees'] as List? ?? const []).cast<Map<String, dynamic>>();
    final shift = Shift(
      id: data['id'] as int,
      date: DateTime(date.year, date.month, date.day),
      area: shiftArea(data['area']?.toString()),
      label: period.$1,
      startHour: period.$2,
      endHour: period.$3,
      minStaff: (data['minimumStaff'] as num).toInt(),
      staffIds: [for (final a in assignees) a['userId'] as int],
    );
    shift.staffNames.addAll({for (final a in assignees) a['userId'] as int: a['displayName']?.toString() ?? ''});
    return shift;
  }

  Future<void> _syncShifts() async {
    final from = DateUtils.dateOnly(store.now);
    final shifts = (await api.get('/shifts?from=${_date(from)}&to=${_date(from.add(const Duration(days: 13)))}') as List)
        .cast<Map<String, dynamic>>();
    store.shifts
      ..clear()
      ..addAll(shifts.map(_shift));
    final swaps = (await api.get('/shift-swaps') as List).cast<Map<String, dynamic>>();
    store.swaps
      ..clear()
      ..addAll(swaps.map((data) => ShiftSwap(
            id: data['id'] as int,
            requesterId: data['requesterUserId'] as int,
            fromShiftId: data['requesterShiftId'] as int,
            targetUserId: data['colleagueUserId'] as int,
            toShiftId: data['colleagueShiftId'] as int,
          )..approved = switch (data['status']) { 'Approved' => true, 'Rejected' => false, _ => null }));
  }

  Future<void> _shiftAction(Future<dynamic> Function() call) async {
    await call();
    await _syncShifts();
    store.refresh();
  }

  /// Administrators: defines a shift of an area with its minimum staff and, optionally, who works it.
  Future<void> createShift({required DateTime date, required Area area, required String period, required int minStaff,
          List<int> staffIds = const []}) =>
      _shiftAction(() => api.post('/shifts', {
            'date': _date(date),
            'period': period,
            'area': backendShiftArea(area),
            'minimumStaff': minStaff,
            'assigneeUserIds': staffIds,
          }));

  Future<void> toggleShiftMember(Shift shift, int userId) => _shiftAction(() => shift.staffIds.contains(userId)
      ? api.delete('/shifts/${shift.id}/assignees/$userId')
      : api.post('/shifts/${shift.id}/assignees', {'userId': userId}));

  Future<void> requestSwap({required int myShiftId, required int colleagueUserId, required int colleagueShiftId, String reason = ''}) =>
      _shiftAction(() => api.post('/shift-swaps', {
            'myShiftId': myShiftId,
            'colleagueUserId': colleagueUserId,
            'colleagueShiftId': colleagueShiftId,
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
          }));

  Future<void> decideSwap(int swapId, bool approve) =>
      _shiftAction(() => api.post('/shift-swaps/$swapId/${approve ? 'approve' : 'reject'}'));

  Handover _handover(Map<String, dynamic> data) {
    final handover = Handover(
      id: data['id'] as int,
      authorId: data['authorUserId'] as int,
      area: shiftArea(data['area']?.toString()),
      notes: data['notes']?.toString() ?? '',
      createdAt: DateTime.parse(data['createdAt'].toString()).toLocal(),
      openItems: [
        for (final item in (data['items'] as List? ?? const []).cast<Map<String, dynamic>>()) _handoverItemText(item),
      ],
    )..authorEmail = data['authorEmail']?.toString();
    for (final ack in (data['acknowledgements'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final userId = ack['userId'] as int;
      handover.readBy[userId] = DateTime.parse(ack['acknowledgedAt'].toString()).toLocal();
      if (ack['email'] != null) handover.readerEmails[userId] = ack['email'].toString();
    }
    return handover;
  }

  String _handoverItemText(Map<String, dynamic> item) {
    final room = store.rooms.where((r) => r.id == item['roomId']).firstOrNull?.number ?? '${item['roomId']}';
    final cleaning = item['kind'] == 'CleaningTask';
    final status = switch (item['status']) {
      'InProgress' => 'en proceso',
      'Pending' => 'pendiente',
      final other => '$other'.toLowerCase(),
    };
    final priority = cleaning
        ? taskPriority(item['priority']?.toString() ?? '').label
        : incidentPriority(item['priority']?.toString() ?? '').label;
    final who = item['assigneeUserId'] == null ? 'sin asignar' : store.userName(item['assigneeUserId'] as int?);
    return cleaning
        ? 'Limpieza hab. $room · $status · ${priority.toLowerCase()} ($who)'
        : 'Incidencia hab. $room: ${item['summary']} · $status · ${priority.toLowerCase()}';
  }

  /// The open items of the area are attached by the backend; an administrator hands over [area].
  Future<void> createHandover(String notes, {Area? area}) async {
    final data = await api.post('/shift-handovers', {
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (area != null) 'area': backendShiftArea(area),
    }) as Map<String, dynamic>;
    store.handovers.add(_handover(data));
    store.refresh();
  }

  Future<void> acknowledgeHandover(int handoverId) async {
    final data = await api.post('/shift-handovers/$handoverId/acknowledge') as Map<String, dynamic>;
    store.handovers
      ..removeWhere((h) => h.id == handoverId)
      ..add(_handover(data));
    store.refresh();
  }

  // ---------------------------------------------------------------------------
  // Notification preferences (US-22): the categories of the backend's push notifications
  // ---------------------------------------------------------------------------

  static String pushCategory(NotificationType type) => switch (type) {
        NotificationType.task => 'cleaning_task_assigned',
        NotificationType.priority => 'priority_changed',
        NotificationType.incident => 'incident_assigned',
        NotificationType.alert => 'incident_escalated',
        NotificationType.request || NotificationType.stay => 'guest_request',
        NotificationType.message => 'message',
      };

  bool _preferencesLoaded = false;

  /// Copies the categories the user turned off into the profile switches (once per session).
  Future<void> _loadNotificationPreferences(AppUser user) async {
    if (_preferencesLoaded) return;
    final data = await api.get('/users/me/notification-preferences') as Map<String, dynamic>;
    final enabled = {
      for (final c in (data['categories'] as List? ?? const []).cast<Map<String, dynamic>>()) c['category'].toString(): c['enabled'] != false,
    };
    for (final type in NotificationType.values) {
      user.prefs[type] = enabled[pushCategory(type)] ?? true;
    }
    _preferencesLoaded = true;
  }

  /// Turns a kind of notification on or off for every device of the account.
  Future<void> setNotificationPref(AppUser user, NotificationType type, bool enabled) async {
    final previous = user.wants(type);
    store.setNotificationPref(user, type, enabled);
    // Types that share a category follow the one just changed.
    for (final other in NotificationType.values.where((t) => pushCategory(t) == pushCategory(type))) {
      user.prefs[other] = enabled;
    }
    final disabled = {for (final t in NotificationType.values) if (!user.wants(t)) pushCategory(t)}.toList();
    try {
      await api.put('/users/me/notification-preferences', {'disabledCategories': disabled});
    } on ApiException {
      store.setNotificationPref(user, type, previous);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Preventive maintenance (US-30) and alerts (US-23), when the backend has them ([hasPreventivePlans])
  // ---------------------------------------------------------------------------

  static PreventiveTask _preventivePlan(Map<String, dynamic> data) {
    final due = DateTime.parse(data['nextDueOn'].toString());
    return PreventiveTask(
      id: data['id'] as int,
      title: data['title']?.toString() ?? '',
      roomId: data['roomId'] as int,
      frequencyDays: (data['frequencyDays'] as num).toInt(),
      nextDue: DateTime(due.year, due.month, due.day, 9),
      reminderDaysBefore: (data['reminderDaysBefore'] as num?)?.toInt() ?? 2,
      active: data['isActive'] != false,
      generatedCount: (data['generatedCount'] as num?)?.toInt() ?? 0,
    );
  }

  OperationalAlert _alert(Map<String, dynamic> data) {
    final incidentId = data['incidentId'] as int;
    final room = store.rooms.where((r) => r.id == data['roomId']).firstOrNull?.number ?? '${data['roomId']}';
    final escalation = data['kind'] == 'Escalation';
    final resolvedAt = DateTime.tryParse(data['resolvedAt']?.toString() ?? '')?.toLocal();
    return OperationalAlert(
      id: -incidentId * 2 - (escalation ? 0 : 1),
      key: 'backend-${data['kind']}-$incidentId',
      title: escalation ? 'Incidencia crítica sin atender' : 'Problema recurrente en la habitación',
      detail: 'Hab. $room: ${data['title']} · ${incidentPriority(data['priority']?.toString() ?? '').label.toLowerCase()}',
      createdAt: DateTime.parse(data['raisedAt'].toString()).toLocal(),
      resolved: data['status'] == 'Resolved',
      resolution: data['resolutionNotes']?.toString() ?? (data['status'] == 'Resolved' ? 'Incidencia resuelta' : ''),
    )
      ..incidentId = incidentId
      ..resolvedAt = resolvedAt;
  }

  /// The backend generates the task on [firstDue] and then every [frequencyDays] days, and reminds maintenance
  /// [reminderDaysBefore] days before each one.
  Future<void> schedulePreventive({required String title, required int roomId, required int frequencyDays,
      required DateTime firstDue, String description = '', int reminderDaysBefore = 2}) async {
    if (title.trim().length < 3) throw const DomainException('Describe la tarea preventiva.');
    await api.post('/preventive-maintenance-plans', {
      'roomId': roomId,
      'title': title.trim(),
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'frequencyDays': frequencyDays,
      'firstDueOn': _date(firstDue),
      'reminderDaysBefore': reminderDaysBefore,
    });
    await sync();
  }

  Future<void> reschedulePreventive(int planId, {required int frequencyDays, required DateTime nextDue, int? reminderDaysBefore}) async {
    await api.put('/preventive-maintenance-plans/$planId/schedule', {
      'frequencyDays': frequencyDays,
      'nextDueOn': _date(nextDue),
      'reminderDaysBefore': ?reminderDaysBefore,
    });
    await sync();
  }

  /// The plan stops generating tasks; the ones already generated stay.
  Future<void> deactivatePreventive(int planId) async {
    await api.post('/preventive-maintenance-plans/$planId/deactivate');
    await sync();
  }

  // ---------------------------------------------------------------------------
  // Cleaning tasks (US-05 / US-06), when the backend has them ([hasCleaningTasks])
  // ---------------------------------------------------------------------------

  /// The backend's task priorities have the app's names (Low, Normal, High, Urgent).
  static Priority taskPriority(String value) => Priority.values.asNameMap()[value.toLowerCase()] ?? Priority.normal;

  static String backendTaskPriority(Priority priority) => '${priority.name[0].toUpperCase()}${priority.name.substring(1)}';

  /// US-07: the backend's checklist (per room type, configured by the hotel) comes only with a single task, like its
  /// history; the list brings its percentage and keeps the items already loaded. A backend without checklists keeps
  /// the one of the room type on this device.
  CleaningTask _task(Map<String, dynamic> data, [CleaningTask? previous]) {
    final roomId = data['roomId'] as int;
    final status = switch (data['status']) {
      'InProgress' => TaskStatus.inProgress,
      'Completed' => TaskStatus.done,
      _ => TaskStatus.pending,
    };
    final remoteChecklist = data['checklist'];
    final hasRemoteChecklist = data.containsKey('checklistProgress');
    var checklist = remoteChecklist is List
        ? [
            for (final item in remoteChecklist.cast<Map<String, dynamic>>())
              ChecklistItem(item['label']?.toString() ?? '',
                  required: item['isRequired'] != false, done: item['isDone'] == true, remoteId: (item['id'] as num).toInt()),
          ]
        : previous?.checklist;
    if (checklist == null && hasRemoteChecklist) {
      checklist = <ChecklistItem>[];
    } else if (checklist == null) {
      checklist = HotelStore.checklistFor(store.rooms.where((r) => r.id == roomId).firstOrNull?.type ?? RoomType.standard);
      // Cleaned on another device: its checklist was completed there.
      if (status == TaskStatus.done) {
        for (final item in checklist) {
          item.done = true;
        }
      }
    }
    final task = CleaningTask(
      id: data['id'] as int,
      roomId: roomId,
      checklist: checklist,
      createdAt: DateTime.parse(data['createdAt'].toString()).toLocal(),
      assigneeId: data['assigneeUserId'] as int?,
      priority: taskPriority(data['priority']?.toString() ?? ''),
      status: status,
    )
      ..startedAt = DateTime.tryParse(data['startedAt']?.toString() ?? '')?.toLocal()
      ..completedAt = DateTime.tryParse(data['completedAt']?.toString() ?? '')?.toLocal()
      ..notes = data['notes']?.toString() ?? '';
    // Until its items are loaded, the progress is the one the backend computed.
    if (hasRemoteChecklist && remoteChecklist is! List && !checklist.any((item) => item.remoteId != null)) {
      task.reportedProgress = (data['checklistProgress'] as num).toDouble() / 100;
    }
    final history = data['history'];
    if (history is List) {
      task.events.addAll([
        for (final entry in history.cast<Map<String, dynamic>>())
          TimelineEvent(DateTime.parse(entry['occurredAt'].toString()).toLocal(), _taskEventText(entry)),
      ]);
    } else if (previous != null) {
      task.events.addAll(previous.events);
    }
    return task;
  }

  /// The backend's `detail` is in English: the text is rebuilt in Spanish from the action.
  String _taskEventText(Map<String, dynamic> entry) {
    final by = entry['actorEmail'] == null ? '' : ' · ${entry['actorEmail']}';
    final detail = entry['detail']?.toString() ?? '';
    String userName(String? id) => store.userById(int.tryParse(id ?? ''))?.name ?? 'otra persona';
    switch (entry['action']) {
      case 'Created':
        final priority = taskPriority(RegExp(r'Priority (\w+)').firstMatch(detail)?.group(1) ?? '');
        final automatic = detail.contains('went to Cleaning') ? ' al pasar la habitación a limpieza' : '';
        return 'Tarea creada$automatic · prioridad ${priority.label.toLowerCase()}$by';
      case 'Assigned':
      case 'Reassigned':
        final match = RegExp(r'Assigned to user (\d+)( \(least workload\))?(, was user (\d+))?').firstMatch(detail);
        final to = userName(match?.group(1));
        if (match?.group(4) != null) return 'Reasignada de ${userName(match!.group(4))} a $to$by';
        return '${match?.group(2) != null ? 'Asignada automáticamente' : 'Asignada'} a $to$by';
      case 'Started':
        return 'Limpieza iniciada$by';
      case 'PriorityChanged':
        final parts = detail.split('→').map((p) => taskPriority(p.trim()).label).toList();
        return '${parts.length == 2 ? 'Prioridad: ${parts[0]} → ${parts[1]}' : 'Prioridad cambiada'}$by';
      case 'ImpedimentReported':
        return 'Impedimento reportado: $detail$by';
      case 'ChecklistItemChecked':
        return 'Hecho: $detail$by';
      case 'ChecklistItemUnchecked':
        return 'Desmarcado: $detail$by';
      case 'Completed':
        return 'Habitación marcada como limpia$by';
      case 'Cancelled':
        return 'Tarea cancelada$by';
      default:
        return '${entry['action']}$by';
    }
  }

  /// Puts the task the backend answered (with its history) in the store; a cancelled task leaves it.
  void _upsertTask(Map<String, dynamic> data) {
    final previous = store.tasks.where((t) => t.id == data['id']).firstOrNull;
    store.tasks.remove(previous);
    if (data['status'] != 'Cancelled') store.tasks.add(_task(data, previous));
    store.refresh();
  }

  Future<void> _taskAction(Future<dynamic> Function() call) async {
    _upsertTask(await call() as Map<String, dynamic>);
    // Starting or completing a task changes its room; an impediment can block it.
    await sync();
  }

  /// The task with its history.
  Future<void> refreshCleaningTask(int taskId) async =>
      _upsertTask(await api.get('/cleaning-tasks/$taskId') as Map<String, dynamic>);

  /// An extra cleaning (rooms that go to Cleaning get their task by themselves). Without [assigneeId] the backend
  /// assigns it by workload when the automatic assignment is on.
  Future<void> createCleaningTask(int roomId, {Priority priority = Priority.normal, int? assigneeId}) =>
      _taskAction(() => api.post('/cleaning-tasks', {
            'roomId': roomId,
            'priority': backendTaskPriority(priority),
            'assigneeUserId': ?assigneeId,
          }));

  /// Without [userId], to the housekeeping staff member with the fewest open tasks.
  Future<void> assignCleaningTask(int taskId, int? userId) =>
      _taskAction(() => api.post('/cleaning-tasks/$taskId/assign', {'assigneeUserId': userId}));

  /// Pending → InProgress and the room goes to Cleaning. A housekeeper starting an unassigned task takes it.
  Future<void> startCleaningTask(int taskId) => _taskAction(() => api.post('/cleaning-tasks/$taskId/start'));

  /// InProgress → Completed and the room becomes Available. The checklist (on this device) must be done first.
  Future<void> completeCleaningTask(int taskId) async {
    final task = store.taskById(taskId);
    // Without its items loaded the backend checks them (409 cleaning_task.checklist_incomplete).
    final missing = task.reportedProgress == null ? task.missingRequired : const <ChecklistItem>[];
    if (missing.isNotEmpty) {
      throw DomainException('Completa los ítems obligatorios:\n• ${missing.map((m) => m.label).join('\n• ')}');
    }
    await _taskAction(() => api.post('/cleaning-tasks/$taskId/complete'));
  }

  /// US-07: marks a step of the task's checklist: the backend's item, or the one kept on this device.
  Future<void> markChecklistItem(int taskId, int index, bool done) async {
    final item = store.taskById(taskId).checklist[index];
    final id = item.remoteId;
    if (id == null) return store.toggleChecklistItem(taskId, index, done);
    // Shown at once; the answer brings the task as the backend has it.
    item.done = done;
    store.refresh();
    try {
      _upsertTask(await api.put('/cleaning-tasks/$taskId/checklist/$id', {'done': done}) as Map<String, dynamic>);
    } on ApiException {
      item.done = !done;
      store.refresh();
      rethrow;
    }
  }

  Future<void> setCleaningTaskPriority(int taskId, Priority priority) =>
      _taskAction(() => api.put('/cleaning-tasks/$taskId/priority', {'priority': backendTaskPriority(priority)}));

  /// The room status does not change.
  Future<void> cancelCleaningTask(int taskId, {String reason = ''}) => _taskAction(
      () => api.post('/cleaning-tasks/$taskId/cancel', {if (reason.trim().isNotEmpty) 'reason': reason.trim()}));

  /// Administrators only: new tasks without an assignee go to the least loaded housekeeper.
  Future<void> setAutoAssignCleaning(bool value) async {
    final settings = await api.put('/cleaning-tasks/settings', {'autoAssign': value}) as Map<String, dynamic>;
    store.autoAssignCleaning = settings['autoAssign'] == true;
    store.refresh();
  }

  /// US-18 / US-24: revenue, bookings and occupancy of the month.
  Future<MonthlyMetrics> monthlyMetrics() async {
    final data = await api.get('/analytics/performance/monthly${hotelId == null ? '' : '?hotelId=$hotelId'}') as Map<String, dynamic>;
    return MonthlyMetrics(
      (data['totalRevenue'] as num).toDouble(),
      (data['totalBookings'] as num).toInt(),
      (data['occupancyRate'] as num).toDouble(),
      (data['cancelledBookings'] as num).toInt(),
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
