import 'dart:typed_data';

import 'package:flutter/material.dart' show DateUtils;

import '../../domain/models.dart';
import '../hotel_store.dart';
import 'api_client.dart';

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
    me = null;
    store.signOut();
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

  static String _tokenFrom(String linkOrToken) {
    final text = linkOrToken.trim();
    final match = RegExp(r'[?&]token=([^&\s]+)').firstMatch(text);
    return match == null ? text : Uri.decodeComponent(match.group(1)!);
  }

  // ---------------------------------------------------------------------------
  // Sync: backend → store
  // ---------------------------------------------------------------------------

  bool get _isAdmin => store.currentUser?.role == UserRole.admin;

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
    for (final room in visibleRooms) {
      // The backend has one Cleaning status; a cleaning already started on a device stays "en limpieza".
      final local = store.rooms.where((r) => r.id == room.id).firstOrNull;
      if (room.status == RoomStatus.dirty && local?.status == RoomStatus.cleaning) room.status = RoomStatus.cleaning;
    }
    store.rooms
      ..clear()
      ..addAll(visibleRooms);

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

    if (_seesPayments) {
      store.payments.clear();
      for (final booking in activeBookings.where((b) => b['confirmedAt'] != null || b['status'] != 'Pending')) {
        try {
          final payment = await api.get('/payments/booking/${booking['id']}') as Map<String, dynamic>;
          store.payments.add(_payment(payment));
        } on ApiException catch (e) {
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
    );
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

  Future<void> cancelBooking(int bookingId) async {
    await api.post('/bookings/$bookingId/cancel');
    await sync();
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
