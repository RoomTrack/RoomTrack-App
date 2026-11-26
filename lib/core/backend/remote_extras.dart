import 'dart:typed_data';

import '../../domain/models.dart';
import '../hotel_store.dart';
import 'api_client.dart';
import 'remote_hotel.dart';

// The rest of the backend: hotel and room setup, cleaning protocols, staff and guest records, audit log, room climate,
// booking changes and reports the screens ask for when they open (nothing here is copied into the store by the sync).

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _time(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toLocal();

String? _clean(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

/// A hotel as the backend describes it (`HotelResource`). Its location comes as "address, city, country".
class HotelInfo {
  final int id;
  final String name;
  final String address;
  final String city;
  final String country;
  final String imageUrl;
  final String description;
  final String type;
  final List<String> amenities;
  final bool acceptsBookings;

  const HotelInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.country,
    required this.imageUrl,
    required this.description,
    required this.type,
    required this.amenities,
    this.acceptsBookings = false,
  });

  factory HotelInfo.fromJson(Map<String, dynamic> data) {
    final parts = (data['location']?.toString() ?? '').split(',').map((p) => p.trim()).toList();
    final country = parts.length >= 3 ? parts.removeLast() : '';
    final city = parts.length >= 2 ? parts.removeLast() : '';
    return HotelInfo(
      id: data['id'] as int,
      name: data['name']?.toString() ?? '',
      address: parts.join(', '),
      city: city,
      country: country,
      imageUrl: data['imageUrl']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      amenities: [for (final a in (data['amenities'] as List? ?? const [])) a.toString()],
      acceptsBookings: data['acceptsBookings'] == true,
    );
  }

  String get location => [address, city, country].where((p) => p.isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'address': address.trim(),
        'city': city.trim(),
        'country': country.trim(),
        'imageUrl': imageUrl.trim(),
        'description': description.trim(),
        'type': type.trim(),
        'amenities': amenities,
      };
}

class RoomTypeInfo {
  final int id;
  final String name;
  final String description;

  const RoomTypeInfo(this.id, this.name, this.description);
}

/// The cleaning protocol of a room type, or the hotel default when [roomTypeId] is null (US-07).
class ChecklistTemplate {
  final int? roomTypeId;

  /// The backend's built-in protocol: the hotel has not configured one yet.
  final bool isStandard;
  final List<({String label, bool required})> items;
  final DateTime? updatedAt;

  const ChecklistTemplate({required this.roomTypeId, required this.isStandard, required this.items, this.updatedAt});

  factory ChecklistTemplate.fromJson(Map<String, dynamic> data) => ChecklistTemplate(
        roomTypeId: data['roomTypeId'] as int?,
        isStandard: data['isStandard'] == true,
        items: [
          for (final item in (data['items'] as List? ?? const []).cast<Map<String, dynamic>>())
            (label: item['label']?.toString() ?? '', required: item['isRequired'] != false),
        ],
        updatedAt: _time(data['updatedAt']),
      );
}

/// Corrective and preventive work of a room (US-10, US-30).
class RoomMaintenanceSummary {
  final int corrective;
  final int preventive;
  final int recurring;
  final List<({String title, int frequencyDays, DateTime nextDue, bool active})> plans;

  const RoomMaintenanceSummary(this.corrective, this.preventive, this.recurring, this.plans);
}

/// A booking of a room, for its calendar.
class RoomBooking {
  final int id;
  final String code;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final String status;

  const RoomBooking(this.id, this.code, this.guestName, this.checkIn, this.checkOut, this.status);

  String get statusLabel => switch (status) {
        'Pending' => 'Pago pendiente',
        'Confirmed' => 'Confirmada',
        'CheckedIn' => 'Hospedado',
        'Completed' => 'Finalizada',
        'Cancelled' => 'Cancelada',
        'Expired' => 'Vencida',
        final other => other,
      };
}

/// A room free for some dates, with the price of the stay.
class AvailableRoom {
  final int id;
  final String number;
  final String typeName;
  final double pricePerNight;
  final int nights;
  final double total;
  final String status;

  const AvailableRoom(this.id, this.number, this.typeName, this.pricePerNight, this.nights, this.total, this.status);

  factory AvailableRoom.fromJson(Map<String, dynamic> data) => AvailableRoom(
        data['id'] as int,
        data['number']?.toString() ?? '${data['id']}',
        data['roomTypeName']?.toString() ?? '',
        (data['pricePerNight'] as num).toDouble(),
        (data['nights'] as num).toInt(),
        (data['totalPrice'] as num).toDouble(),
        data['status']?.toString() ?? '',
      );
}

/// The emulated thermostat of a room (IoT).
class RoomClimate {
  final double temperature;
  final bool motionDetected;
  final String lastCommand;
  final String hardwareStatus;
  final DateTime? updatedAt;

  const RoomClimate(this.temperature, this.motionDetected, this.lastCommand, this.hardwareStatus, this.updatedAt);

  factory RoomClimate.fromJson(Map<String, dynamic> data) => RoomClimate(
        (data['currentTemperature'] as num?)?.toDouble() ?? 22,
        data['motionDetected'] != false,
        data['lastCommandReceived']?.toString() ?? '',
        data['hardwareStatus']?.toString() ?? '',
        _time(data['timestamp']),
      );

  /// The system lowered the load because nobody was in the room.
  bool get powerSaving => lastCommand == 'AUTO_POWER_SAVING_MODE_TRIGGERED';

  /// The fan speed of the last command ("SET_TEMPERATURE_22C_FAN_MEDIUM"), when it was a thermostat change.
  String? get fanSpeed => RegExp(r'FAN_(\w+)$').firstMatch(lastCommand)?.group(1);
}

/// A movement of the hotel's money (US-17): charges, refunds, deposits and receipts.
class PaymentHistoryEntry {
  final DateTime at;
  final String type;
  final int bookingId;
  final double amount;
  final String? method;
  final String? reference;
  final int? receiptId;

  const PaymentHistoryEntry(this.at, this.type, this.bookingId, this.amount, this.method, this.reference, this.receiptId);

  String get typeLabel => switch (type) {
        'BookingPayment' => 'Pago de reserva',
        'FolioPayment' => 'Pago de consumos',
        'Refund' => 'Reembolso',
        'DepositHeld' => 'Garantía retenida',
        'DepositReleased' => 'Garantía liberada',
        'Receipt' => 'Comprobante emitido',
        final other => other.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' '),
      };
}

/// A shift without enough people; the critical areas come first (US-31).
class CoverageGap {
  final int shiftId;
  final int missing;
  final bool critical;

  const CoverageGap(this.shiftId, this.missing, this.critical);
}

class AuditEntry {
  final int id;
  final DateTime at;
  final String action;
  final bool succeeded;
  final String? actorEmail;
  final String? targetEmail;
  final String? ip;

  const AuditEntry(this.id, this.at, this.action, this.succeeded, this.actorEmail, this.targetEmail, this.ip);

  static const Map<String, String> actions = {
    'SignInSucceeded': 'Inicio de sesión',
    'SignInFailed': 'Inicio de sesión fallido',
    'AccountLocked': 'Cuenta bloqueada',
    'SignedOut': 'Cierre de sesión',
    'PasswordReset': 'Contraseña restablecida',
    'PasswordChanged': 'Contraseña cambiada',
    'UserCreated': 'Cuenta creada',
    'RoleChanged': 'Rol cambiado',
    'UserDeactivated': 'Cuenta desactivada',
    'UserActivated': 'Cuenta reactivada',
    'MfaEnabled': 'Autenticador activado',
    'MfaVerified': 'Segundo factor verificado',
    'MfaFailed': 'Segundo factor fallido',
    'MfaRecoveryCodeUsed': 'Código de recuperación usado',
    'MfaReset': 'Autenticador restablecido',
    'SignedOutEverywhere': 'Cierre de todas las sesiones',
    'AssignmentChanged': 'Asignación cambiada',
  };

  String get actionLabel => actions[action] ?? action;
}

class AuditPage {
  final List<AuditEntry> items;
  final int page;
  final int totalPages;
  final int total;

  const AuditPage(this.items, this.page, this.totalPages, this.total);
}

/// Identity documents of the profiles service (`DocumentType`: Dni = 0, Passport = 1, ForeignerId = 2).
const List<String> kDocumentTypes = ['DNI', 'Pasaporte', 'Carné de extranjería'];

/// Habitual shifts of a staff member (`HabitualShift`).
const Map<String, String> kHabitualShifts = {
  'Morning': 'Mañana',
  'Afternoon': 'Tarde',
  'Night': 'Noche',
  'Rotating': 'Rotativo',
};

/// Roles of a staff assignment (`StaffRole`); the chain-level ones are not given from a hotel.
const Map<String, String> kAssignmentRoles = {
  'Admin': 'Administración',
  'Reception': 'Recepción',
  'Housekeeping': 'Limpieza',
  'Maintenance': 'Mantenimiento',
  'Staff': 'Personal',
};

int? _documentIndex(Object? value) => switch (value) {
      final int index => index,
      'Dni' => 0,
      'Passport' => 1,
      'ForeignerId' => 2,
      _ => null,
    };

/// Address and phone shared by the staff and guest records.
class ContactData {
  final String phone;
  final String street;
  final String number;
  final String city;
  final String postalCode;
  final String country;

  const ContactData({this.phone = '', this.street = '', this.number = '', this.city = '', this.postalCode = '', this.country = ''});

  factory ContactData.fromJson(Map<String, dynamic> data) => ContactData(
        phone: data['phone']?.toString() ?? '',
        street: data['street']?.toString() ?? '',
        number: data['number']?.toString() ?? '',
        city: data['city']?.toString() ?? '',
        postalCode: data['postalCode']?.toString() ?? '',
        country: data['country']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'phone': _clean(phone),
        'street': _clean(street),
        'number': _clean(number),
        'city': _clean(city),
        'postalCode': _clean(postalCode),
        'country': _clean(country),
      };

  String get address => [
        [street, number].where((p) => p.isNotEmpty).join(' '),
        city,
        country,
      ].where((p) => p.isNotEmpty).join(', ');
}

class StaffAssignment {
  final String id;
  final String scope;
  final String role;
  final DateTime start;
  final DateTime? end;
  final String status;

  const StaffAssignment(this.id, this.scope, this.role, this.start, this.end, this.status);

  String get roleLabel => kAssignmentRoles[role] ?? role;

  String get statusLabel => switch (status) {
        'Active' => 'Vigente',
        'Suspended' => 'Suspendida',
        'Terminated' => 'Terminada',
        final other => other,
      };
}

/// The HR record of a staff member (profiles service), apart from their account.
class StaffProfile {
  final String id;
  final int userId;
  final String code;
  final String firstName;
  final String lastName;
  final String email;
  final String position;
  final String shift;
  final int? documentType;
  final String documentNumber;
  final ContactData contact;
  final bool active;
  final List<StaffAssignment> assignments;

  const StaffProfile({
    required this.id,
    required this.userId,
    required this.code,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.position,
    required this.shift,
    required this.documentType,
    required this.documentNumber,
    required this.contact,
    required this.active,
    required this.assignments,
  });

  factory StaffProfile.fromJson(Map<String, dynamic> data) => StaffProfile(
        id: data['id'].toString(),
        userId: data['userId'] as int,
        code: data['code']?.toString() ?? '',
        firstName: data['firstName']?.toString() ?? '',
        lastName: data['lastName']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        position: data['position']?.toString() ?? '',
        shift: data['shift']?.toString() ?? '',
        documentType: _documentIndex(data['documentType']),
        documentNumber: data['documentNumber']?.toString() ?? '',
        contact: ContactData.fromJson(data),
        active: data['status'] == 'Active',
        assignments: [
          for (final a in (data['assignments'] as List? ?? const []).cast<Map<String, dynamic>>())
            StaffAssignment(
              a['id'].toString(),
              a['scope']?.toString() ?? '',
              a['role']?.toString() ?? '',
              DateTime.parse(a['startDate'].toString()),
              DateTime.tryParse(a['endDate']?.toString() ?? ''),
              a['status']?.toString() ?? '',
            ),
        ],
      );

  String get shiftLabel => kHabitualShifts[shift] ?? shift;
}

/// The guest record of the profiles service: contact and identity document.
class GuestProfile {
  final String id;
  final int? userId;
  final String firstName;
  final String lastName;
  final String email;
  final int? documentType;
  final String documentNumber;
  final ContactData contact;
  final bool active;

  const GuestProfile({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.documentType,
    required this.documentNumber,
    required this.contact,
    required this.active,
  });

  factory GuestProfile.fromJson(Map<String, dynamic> data) => GuestProfile(
        id: data['id'].toString(),
        userId: data['userId'] as int?,
        firstName: data['firstName']?.toString() ?? '',
        lastName: data['lastName']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        documentType: _documentIndex(data['documentType']),
        documentNumber: data['documentNumber']?.toString() ?? '',
        contact: ContactData.fromJson(data),
        active: data['status'] == 'Active',
      );

  String get fullName => '$firstName $lastName'.trim();

  String get document => documentType == null || documentNumber.isEmpty ? '' : '${kDocumentTypes[documentType!]} $documentNumber';
}

extension RemoteExtras on RemoteHotel {
  int get _hotel => hotelId ?? (throw const DomainException('Tu cuenta no pertenece a un hotel.'));

  /// A missing record (404) is null.
  Future<T?> _orNull<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Hotel, room types and rooms (administrators)
  // ---------------------------------------------------------------------------

  Future<HotelInfo> hotel() async => HotelInfo.fromJson(await api.get('/hotels/$_hotel') as Map<String, dynamic>);

  Future<HotelInfo> updateHotel(HotelInfo hotel) async =>
      HotelInfo.fromJson(await api.put('/hotels/$_hotel', hotel.toJson()) as Map<String, dynamic>);

  /// Uploads a photo straight to the image storage with a signature of the backend; returns its URL.
  Future<String> uploadHotelImage(Uint8List bytes, String fileName) async {
    final signature = await api.post('/media/hotel-images/signature') as Map<String, dynamic>;
    final uploaded = await api.uploadTo(
      signature['uploadUrl'].toString(),
      {
        'api_key': signature['apiKey'].toString(),
        'timestamp': signature['timestamp'].toString(),
        'signature': signature['signature'].toString(),
        'upload_preset': signature['uploadPreset'].toString(),
        'folder': signature['folder'].toString(),
      },
      fileField: 'file',
      bytes: bytes,
      fileName: fileName,
    );
    return uploaded['secure_url'].toString();
  }

  /// Hotel categories of the catalog (boutique, business...).
  Future<List<String>> hotelCategories() async =>
      [for (final c in await api.get('/accommodations/options/categories') as List) c.toString()];

  /// Amenities a hotel or a room can offer.
  Future<List<String>> amenityOptions() async =>
      [for (final a in await api.get('/accommodations/options/amenities') as List) a.toString()];

  Future<List<RoomTypeInfo>> roomTypes() async => [
        for (final t in (await api.get('/room-types') as List).cast<Map<String, dynamic>>())
          RoomTypeInfo(t['id'] as int, t['name']?.toString() ?? '', t['description']?.toString() ?? ''),
      ];

  Future<RoomTypeInfo> createRoomType(String name, String description) async {
    final t = await api.post('/room-types', {'name': name.trim(), 'description': description.trim()}) as Map<String, dynamic>;
    return RoomTypeInfo(t['id'] as int, t['name']?.toString() ?? name, t['description']?.toString() ?? description);
  }

  Future<void> createRoom({required String number, required int roomTypeId, required double price, required String description,
      List<String> amenities = const []}) async {
    if (number.trim().isEmpty) throw const DomainException('Ingresa el número de la habitación.');
    if (description.trim().isEmpty) throw const DomainException('Describe la habitación.');
    await api.post('/rooms', {
      'hotelId': _hotel,
      'number': number.trim(),
      'roomTypeId': roomTypeId,
      'price': price,
      'description': description.trim(),
      'amenities': amenities,
    });
    await sync();
  }

  Future<void> updateRoom(Room room, {required String number, required int roomTypeId, required double price,
      required String description, List<String> amenities = const []}) async {
    if (description.trim().isEmpty) throw const DomainException('Describe la habitación.');
    await api.put('/rooms/${room.id}', {
      'number': number.trim(),
      'roomTypeId': roomTypeId,
      'price': price,
      'description': description.trim(),
      'amenities': amenities,
    });
    await sync();
  }

  /// Refused while the room has active bookings.
  Future<void> deleteRoom(Room room) async {
    await api.delete('/rooms/${room.id}');
    await sync();
  }

  // ---------------------------------------------------------------------------
  // Cleaning protocols (US-07)
  // ---------------------------------------------------------------------------

  /// One per configured room type plus the hotel default; only the standard one while nothing is configured.
  Future<List<ChecklistTemplate>> checklistTemplates() async => [
        for (final t in (await api.get('/cleaning-tasks/checklists') as List).cast<Map<String, dynamic>>()) ChecklistTemplate.fromJson(t),
      ];

  /// Replaces the steps of a room type (or the hotel default without [roomTypeId]); tasks created later get them.
  Future<ChecklistTemplate> saveChecklist(int? roomTypeId, List<({String label, bool required})> items) async {
    final steps = items.where((i) => i.label.trim().isNotEmpty).toList();
    if (steps.isEmpty) throw const DomainException('El checklist necesita al menos un paso.');
    final data = await api.put('/cleaning-tasks/checklists${roomTypeId == null ? '' : '?roomTypeId=$roomTypeId'}', {
      'items': [for (final i in steps) {'label': i.label.trim(), 'isRequired': i.required}],
    }) as Map<String, dynamic>;
    return ChecklistTemplate.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // A room: maintenance history, bookings and climate
  // ---------------------------------------------------------------------------

  Future<RoomMaintenanceSummary> maintenanceSummary(int roomId) async {
    final data = await api.get('/rooms/$roomId/maintenance-history') as Map<String, dynamic>;
    return RoomMaintenanceSummary(
      (data['correctiveCount'] as num?)?.toInt() ?? 0,
      (data['preventiveCount'] as num?)?.toInt() ?? 0,
      (data['recurringCount'] as num?)?.toInt() ?? 0,
      [
        for (final p in (data['preventivePlans'] as List? ?? const []).cast<Map<String, dynamic>>())
          (
            title: p['title']?.toString() ?? '',
            frequencyDays: (p['frequencyDays'] as num?)?.toInt() ?? 0,
            nextDue: DateTime.parse(p['nextDueOn'].toString()),
            active: p['isActive'] != false,
          ),
      ],
    );
  }

  /// Every booking of the room, the next ones first.
  Future<List<RoomBooking>> roomBookings(int roomId) async {
    final bookings = [
      for (final b in (await api.get('/bookings/room/$roomId') as List).cast<Map<String, dynamic>>())
        RoomBooking(
          b['id'] as int,
          b['code']?.toString() ?? '',
          b['guestName']?.toString() ?? '',
          DateTime.parse(b['checkInDate'].toString()),
          DateTime.parse(b['checkOutDate'].toString()),
          b['status']?.toString() ?? '',
        ),
    ];
    return bookings..sort((a, b) => b.checkIn.compareTo(a.checkIn));
  }

  Future<RoomClimate> roomClimate(int roomId) async =>
      RoomClimate.fromJson(await api.get('/io-t-emulator/rooms/$roomId/actuators-state') as Map<String, dynamic>);

  /// The guest of the room (or maintenance) sets the temperature; [fan] is Low, Medium or High.
  Future<RoomClimate> setThermostat(int roomId, double celsius, String fan) async {
    if (celsius < 16 || celsius > 30) throw const DomainException('Elige una temperatura entre 16 °C y 30 °C.');
    return RoomClimate.fromJson(await api.post('/io-t-emulator/rooms/$roomId/thermostat', {
      'targetTemperatureCelsius': celsius,
      'fanSpeed': fan,
      'simulationMode': 'CiscoPacketTracer_SBC',
    }) as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Availability and changes of a booking (front desk)
  // ---------------------------------------------------------------------------

  /// Rooms of the hotel free for the whole stay.
  Future<List<AvailableRoom>> availableRooms(DateTime checkIn, DateTime checkOut) async {
    if (!checkOut.isAfter(checkIn)) throw const DomainException('La salida debe ser al menos un día después de la llegada.');
    final hotel = hotelId == null ? '' : '&hotelId=$hotelId';
    final rooms = [
      for (final r in (await api.get('/rooms/available?checkIn=${_day(checkIn)}&checkOut=${_day(checkOut)}$hotel') as List)
          .cast<Map<String, dynamic>>())
        AvailableRoom.fromJson(r),
    ];
    return rooms..sort((a, b) => a.number.compareTo(b.number));
  }

  /// US-27: rooms ready now for a guest whose booked room is not ready, the most similar first.
  Future<List<AvailableRoom>> checkInAlternatives(int bookingId) async => [
        for (final r in (await api.get('/bookings/$bookingId/check-in/alternatives') as List).cast<Map<String, dynamic>>())
          AvailableRoom.fromJson(r),
      ];

  /// New dates and/or room of a Pending or Confirmed booking; a paid one must keep its total. The guest gets an e-mail.
  Future<void> rescheduleBooking(int bookingId, {DateTime? checkIn, DateTime? checkOut, int? roomId}) async {
    if (checkIn == null && checkOut == null && roomId == null) {
      throw const DomainException('Indica la nueva fecha o la nueva habitación.');
    }
    await api.patch('/bookings/$bookingId', {
      if (checkIn != null) 'checkInDate': _day(checkIn),
      if (checkOut != null) 'checkOutDate': _day(checkOut),
      'roomId': ?roomId,
    });
    await sync();
  }

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------

  /// Movements of the hotel's money, newest first; the last 30 days by default.
  Future<List<PaymentHistoryEntry>> paymentHistory({DateTime? from, DateTime? to}) async {
    final query = [
      if (from != null) 'from=${Uri.encodeQueryComponent(from.toUtc().toIso8601String())}',
      if (to != null) 'to=${Uri.encodeQueryComponent(to.toUtc().toIso8601String())}',
    ].join('&');
    return [
      for (final e in (await api.get('/payments/history${query.isEmpty ? '' : '?$query'}') as List).cast<Map<String, dynamic>>())
        PaymentHistoryEntry(
          DateTime.parse(e['occurredAt'].toString()).toLocal(),
          e['type']?.toString() ?? '',
          e['bookingId'] as int,
          (e['amount'] as num).toDouble(),
          e['method']?.toString(),
          e['reference']?.toString(),
          e['receiptId'] as int?,
        ),
    ];
  }

  /// Shifts of the next two weeks without enough people (administrators).
  Future<List<CoverageGap>> coverageGaps() async {
    final today = store.now;
    final data = await api.get('/shifts/coverage-gaps?from=${_day(today)}&to=${_day(today.add(const Duration(days: 13)))}') as List;
    return [
      for (final g in data.cast<Map<String, dynamic>>())
        CoverageGap((g['shift'] as Map<String, dynamic>)['id'] as int, (g['missing'] as num).toInt(), g['isCritical'] == true),
    ];
  }

  /// Sign-ins, role changes and other security events of the hotel's accounts, newest first (administrators).
  Future<AuditPage> auditLog({int page = 1, String? action, int? userId}) async {
    final query = ['page=$page', 'pageSize=30', if (action != null) 'action=$action', if (userId != null) 'userId=$userId'].join('&');
    final data = await api.get('/audit-logs?$query') as Map<String, dynamic>;
    return AuditPage(
      [
        for (final e in (data['items'] as List? ?? const []).cast<Map<String, dynamic>>())
          AuditEntry(
            (e['id'] as num).toInt(),
            DateTime.parse(e['occurredAt'].toString()).toLocal(),
            e['action']?.toString() ?? '',
            e['outcome']?.toString() != 'Failure',
            e['actorEmail']?.toString(),
            e['targetEmail']?.toString(),
            e['ipAddress']?.toString(),
          ),
      ],
      (data['page'] as num?)?.toInt() ?? page,
      (data['totalPages'] as num?)?.toInt() ?? 1,
      (data['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Staff records (administrators)
  // ---------------------------------------------------------------------------

  Future<List<StaffProfile>> staffProfiles() async => [
        for (final p in (await api.get('/staff/hotel/$_hotel') as List).cast<Map<String, dynamic>>()) StaffProfile.fromJson(p),
      ];

  Future<StaffProfile?> staffProfileOf(int userId) =>
      _orNull(() async => StaffProfile.fromJson(await api.get('/staff/user/$userId') as Map<String, dynamic>));

  /// Opens the HR record of an account and assigns it to this hotel with its role.
  Future<StaffProfile> createStaffProfile(AppUser user, {required String position, required String shift,
      ContactData contact = const ContactData(), int? documentType, String documentNumber = ''}) async {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    final data = await api.post('/staff', {
      'userId': user.id,
      'firstName': parts.first,
      'lastName': parts.length > 1 ? parts.skip(1).join(' ') : parts.first,
      'email': user.email,
      'position': position.trim(),
      'shift': kHabitualShifts.keys.toList().indexOf(shift),
      ...contact.toJson(),
      if (documentType != null && documentNumber.trim().isNotEmpty) ...{
        'documentType': documentType,
        'documentNumber': documentNumber.trim(),
      },
    }) as Map<String, dynamic>;
    final profile = StaffProfile.fromJson(data);
    if (profile.assignments.isEmpty && user.role != UserRole.guest) {
      return addStaffAssignment(profile, _assignmentRole(user.role), store.now);
    }
    return profile;
  }

  static String _assignmentRole(UserRole role) => switch (role) {
        UserRole.admin => 'Admin',
        UserRole.reception => 'Reception',
        UserRole.housekeeping => 'Housekeeping',
        UserRole.maintenance => 'Maintenance',
        UserRole.guest => 'Staff',
      };

  Future<StaffProfile> _staffChange(String id, String path, Object? body, {bool put = true}) async {
    await (put ? api.put('/staff/$id/$path', body) : api.post('/staff/$id/$path', body));
    return StaffProfile.fromJson(await api.get('/staff/$id') as Map<String, dynamic>);
  }

  Future<StaffProfile> renameStaff(StaffProfile profile, String firstName, String lastName) =>
      _staffChange(profile.id, 'legal-name', {'firstName': firstName.trim(), 'lastName': lastName.trim()});

  Future<StaffProfile> setStaffContact(StaffProfile profile, ContactData contact) =>
      _staffChange(profile.id, 'personal-contact', contact.toJson());

  Future<StaffProfile> setStaffPosition(StaffProfile profile, String position) =>
      _staffChange(profile.id, 'job-position', {'position': position.trim()});

  Future<StaffProfile> setStaffShift(StaffProfile profile, String shift) =>
      _staffChange(profile.id, 'habitual-shift', {'shift': kHabitualShifts.keys.toList().indexOf(shift)});

  Future<StaffProfile> setStaffDocument(StaffProfile profile, int documentType, String number) =>
      _staffChange(profile.id, 'identification', {'documentType': documentType, 'documentNumber': number.trim()});

  Future<StaffProfile> setStaffProfileActive(StaffProfile profile, bool active) =>
      _staffChange(profile.id, active ? 'activate' : 'deactivate', null, put: false);

  /// A role at this hotel from [start] (`ScopeLevel.Hotel` = 1).
  Future<StaffProfile> addStaffAssignment(StaffProfile profile, String role, DateTime start, {DateTime? end}) =>
      _staffChange(profile.id, 'assignments', {
        'scope': 1,
        'targetId': _hotel,
        'role': kAssignmentRoles.keys.toList().indexOf(role) + 1,
        'startDate': _day(start),
        if (end != null) 'endDate': _day(end),
      }, put: false);

  Future<StaffProfile> suspendAssignment(StaffProfile profile, StaffAssignment assignment) =>
      _staffChange(profile.id, 'assignments/${assignment.id}/suspend', null, put: false);

  Future<StaffProfile> reactivateAssignment(StaffProfile profile, StaffAssignment assignment) =>
      _staffChange(profile.id, 'assignments/${assignment.id}/reactivate', null, put: false);

  Future<StaffProfile> terminateAssignment(StaffProfile profile, StaffAssignment assignment, DateTime date) =>
      _staffChange(profile.id, 'assignments/${assignment.id}/terminate', {'terminationDate': _day(date)}, put: false);

  // ---------------------------------------------------------------------------
  // Guest records
  // ---------------------------------------------------------------------------

  /// The signed-in guest's own record; null until they create it or the hotel registers them.
  Future<GuestProfile?> myGuestProfile() {
    final id = store.currentUser?.id;
    if (id == null) return Future.value();
    return _orNull(() async => GuestProfile.fromJson(await api.get('/guests/user/$id') as Map<String, dynamic>));
  }

  /// The front desk looks a guest up by e-mail.
  Future<GuestProfile?> guestProfileByEmail(String email) => _orNull(() async =>
      GuestProfile.fromJson(await api.get('/guests/email/${Uri.encodeComponent(email.trim())}') as Map<String, dynamic>));

  /// A guest creates their own record (linked to their account); the front desk one for a guest at the desk.
  Future<GuestProfile> createGuestProfile({required String name, required String email, required ContactData contact,
      int? userId}) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) throw const DomainException('Escribe nombre y apellido.');
    if (contact.phone.trim().isEmpty) throw const DomainException('Ingresa un teléfono de contacto.');
    final data = await api.post('/guests', {
      'firstName': parts.first,
      'lastName': parts.skip(1).join(' '),
      'email': _clean(email),
      ...contact.toJson(),
      'userId': ?userId,
    }) as Map<String, dynamic>;
    return GuestProfile.fromJson(data);
  }

  Future<GuestProfile> _guestChange(String id, String path, Object? body, {bool put = true}) async {
    await (put ? api.put('/guests/$id/$path', body) : api.post('/guests/$id/$path', body));
    return GuestProfile.fromJson(await api.get('/guests/$id') as Map<String, dynamic>);
  }

  Future<GuestProfile> setGuestContact(GuestProfile profile, ContactData contact) {
    if (contact.phone.trim().isEmpty) throw const DomainException('Ingresa un teléfono de contacto.');
    return _guestChange(profile.id, 'contact-info', contact.toJson());
  }

  /// The front desk records the document once; afterwards only an administrator corrects it.
  Future<GuestProfile> setGuestDocument(GuestProfile profile, int documentType, String number) =>
      _guestChange(profile.id, 'identification', {'documentType': documentType, 'documentNumber': number.trim()});

  Future<GuestProfile> correctGuestDocument(GuestProfile profile, int documentType, String number, String reason) {
    if (reason.trim().isEmpty) throw const DomainException('Indica el motivo de la corrección.');
    return _guestChange(profile.id, 'correct-identification',
        {'newDocumentType': documentType, 'newDocumentNumber': number.trim(), 'reason': reason.trim()}, put: false);
  }

  Future<GuestProfile> setGuestProfileActive(GuestProfile profile, bool active) =>
      _guestChange(profile.id, active ? 'activate' : 'deactivate', null, put: false);
}
