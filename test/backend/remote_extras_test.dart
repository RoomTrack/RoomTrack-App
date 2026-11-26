import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/backend/remote_extras.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/domain/models.dart';

import 'remote_hotel_test.dart' show fakeBackend;

const _admin = {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1};
const _reception = {'id': 2, 'email': 'recepcion@roomtrack.pe', 'firstName': 'Luis', 'lastName': 'Paz', 'role': 'reception', 'hotelId': 1};
const _guest = {'id': 6, 'email': 'huesped@roomtrack.pe', 'firstName': 'Sofía', 'lastName': 'Herrera', 'role': 'guest'};

Map<String, Object?> _staffJson({List<Map<String, Object?>> assignments = const [], String position = 'Camarera'}) => {
      'id': 'a1b2c3d4-0000-0000-0000-000000000001', 'userId': 3, 'code': 'EMP-0003', 'firstName': 'María', 'lastName': 'Quispe',
      'fullName': 'María Quispe', 'email': 'limpieza@roomtrack.pe', 'phone': '987654321', 'position': position, 'shift': 'Night',
      'documentType': 0, 'documentNumber': '45678912', 'street': 'Av. Sol', 'number': '120', 'city': 'Cusco', 'postalCode': null,
      'country': 'PE', 'status': 'Active', 'createdAt': '2026-11-20T10:00:00Z', 'updatedAt': null, 'assignments': assignments,
    };

/// The JSON body sent with the last call to [route].
Map<String, dynamic> _bodyOf(List<String> calls, String route) {
  final call = calls.lastWhere((c) => c.startsWith('$route {'));
  return jsonDecode(call.substring(route.length + 1)) as Map<String, dynamic>;
}

void main() {
  test('US-04: el mapa de habitaciones dice a qué estados puede pasar cada una y cuáles llevan mucho en mantenimiento', () async {
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, extra: {
      'GET /rooms/map': {
        'hotelId': 1, 'hotelName': 'Casa Andina', 'generatedAt': '2026-11-25T10:00:00Z', 'summary': {'Occupied': 1, 'Cleaning': 1},
        'rooms': [
          {'id': 10, 'number': '304', 'roomTypeName': 'Suite', 'description': '', 'price': 205, 'status': 'Occupied',
            'statusSince': '2026-11-25T09:00:00Z', 'maintenanceOverdue': false, 'allowedNextStatuses': ['Cleaning'], 'blockedByIncident': false},
          {'id': 11, 'number': '201', 'roomTypeName': 'Doble', 'description': '', 'price': 140, 'status': 'Cleaning',
            'statusSince': '2026-11-20T09:00:00Z', 'maintenanceOverdue': true, 'allowedNextStatuses': ['Available', 'Maintenance'], 'blockedByIncident': false},
        ],
      },
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    final store = remote.store;

    final suite = store.roomById(10);
    expect(suite.typeLabel, 'Suite');
    expect(suite.price, 205);
    expect(suite.allowedNext, {RoomStatus.dirty, RoomStatus.cleaning});
    expect(store.roomById(11).allowedNext, {RoomStatus.available, RoomStatus.maintenance});
    expect(store.roomById(11).maintenanceOverdue, isTrue);
  });

  test('sin mapa de habitaciones (backend antiguo) se ofrecen todos los estados', () async {
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'});
    await remote.signIn('admin@roomtrack.pe', 'x');
    expect(remote.store.roomById(10).allowedNext, isNull);
  });

  test('US-19: el administrador asigna una solicitud a alguien del área', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'POST /guest-requests/40/assign': {
        'id': 40, 'hotelId': 1, 'roomId': 10, 'bookingId': 7, 'title': 'Toallas', 'area': 1, 'status': 0,
        'createdByUserId': 6, 'assigneeUserId': 3, 'createdAt': '2026-11-25T10:00:00Z',
      },
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    await remote.assignRequest(40, 3);
    expect(_bodyOf(calls, 'POST /guest-requests/40/assign'), {'assigneeUserId': 3});
    expect(remote.store.requests.single.assigneeId, 3);
  });

  test('US-07: protocolos de limpieza por tipo de habitación', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'GET /cleaning-tasks/checklists': [
        {'hotelId': 1, 'roomTypeId': null, 'isStandard': true, 'items': [
          {'position': 1, 'label': 'Cambiar sábanas', 'isRequired': true},
          {'position': 2, 'label': 'Reponer amenities', 'isRequired': false},
        ]},
      ],
      'PUT /cleaning-tasks/checklists': {'hotelId': 1, 'roomTypeId': 3, 'isStandard': false, 'updatedAt': '2026-11-25T15:00:00Z',
        'items': [{'position': 1, 'label': 'Revisar el jacuzzi', 'isRequired': true}]},
    });
    await remote.signIn('admin@roomtrack.pe', 'x');

    final templates = await remote.checklistTemplates();
    expect(templates.single.isStandard, isTrue);
    expect(templates.single.items.map((i) => (i.label, i.required)), [('Cambiar sábanas', true), ('Reponer amenities', false)]);

    final saved = await remote.saveChecklist(3, [(label: ' Revisar el jacuzzi ', required: true), (label: '  ', required: false)]);
    expect(saved.roomTypeId, 3);
    expect(_bodyOf(calls, 'PUT /cleaning-tasks/checklists'), {
      'items': [{'label': 'Revisar el jacuzzi', 'isRequired': true}],
    });
    expect(() => remote.saveChecklist(null, const []), throwsA(isA<DomainException>()));
  });

  test('datos del hotel: la ubicación se separa en dirección, ciudad y país', () async {
    final calls = <String>[];
    final hotel = {
      'id': 1, 'hostId': 1, 'name': 'Casa Andina', 'location': 'Av. El Sol 954, Of. 2, Cusco, Perú', 'imageUrl': 'https://img/1.jpg',
      'description': 'Boutique', 'basePrice': 120, 'type': 'Boutique', 'amenities': ['Wifi'], 'acceptsBookings': true,
    };
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'GET /hotels/1': hotel,
      'PUT /hotels/1': hotel,
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    final info = await remote.hotel();
    expect((info.address, info.city, info.country), ('Av. El Sol 954, Of. 2', 'Cusco', 'Perú'));
    await remote.updateHotel(info);
    expect(_bodyOf(calls, 'PUT /hotels/1'), containsPair('address', 'Av. El Sol 954, Of. 2'));
    expect(_bodyOf(calls, 'PUT /hotels/1'), containsPair('city', 'Cusco'));
  });

  test('alta y edición de habitaciones del hotel', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'POST /rooms': const {},
      'PUT /rooms/11': const {},
      'DELETE /rooms/11': null,
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    await remote.createRoom(number: ' 305 ', roomTypeId: 2, price: 150, description: 'Vista al patio', amenities: ['Wifi']);
    expect(_bodyOf(calls, 'POST /rooms'), {
      'hotelId': 1, 'number': '305', 'roomTypeId': 2, 'price': 150.0, 'description': 'Vista al patio', 'amenities': ['Wifi'],
    });
    final room = remote.store.roomById(11);
    await remote.updateRoom(room, number: '201', roomTypeId: 2, price: 160, description: 'Doble');
    expect(_bodyOf(calls, 'PUT /rooms/11'), containsPair('price', 160.0));
    await remote.deleteRoom(room);
    expect(calls, contains('DELETE /rooms/11'));
  });

  test('US-27 / US-28: disponibilidad por fechas, alternativas y cambio de reserva', () async {
    final calls = <String>[];
    final free = {
      'id': 12, 'hotelId': 1, 'roomTypeId': 1, 'roomTypeName': 'Suite', 'description': '', 'amenities': const [], 'status': 'Available',
      'available': true, 'pricePerNight': 205, 'nights': 2, 'totalPrice': 410, 'checkInDate': '2026-12-01', 'checkOutDate': '2026-12-03',
      'number': '305',
    };
    final remote = fakeBackend(me: _reception, signIn: {'id': 2, 'token': 'access'}, calls: calls, extra: {
      'GET /rooms/available': [free],
      'GET /bookings/8/check-in/alternatives': [free],
      'PATCH /bookings/8': const {},
    });
    await remote.signIn('recepcion@roomtrack.pe', 'x');

    final rooms = await remote.availableRooms(DateTime(2026, 12, 1), DateTime(2026, 12, 3));
    expect(rooms.single.number, '305');
    expect(rooms.single.total, 410);
    expect(() => remote.availableRooms(DateTime(2026, 12, 3), DateTime(2026, 12, 3)), throwsA(isA<DomainException>()));

    expect((await remote.checkInAlternatives(8)).single.id, 12);
    await remote.rescheduleBooking(8, checkIn: DateTime(2026, 12, 1), checkOut: DateTime(2026, 12, 3), roomId: 12);
    expect(_bodyOf(calls, 'PATCH /bookings/8'), {'checkInDate': '2026-12-01', 'checkOutDate': '2026-12-03', 'roomId': 12});
  });

  test('US-17: historial de pagos del hotel', () async {
    final remote = fakeBackend(me: _reception, signIn: {'id': 2, 'token': 'access'}, extra: {
      'GET /payments/history': [
        {'occurredAt': '2026-11-26T15:00:00+00:00', 'type': 'FolioPayment', 'bookingId': 7, 'amount': 30.0, 'method': 'Yape',
          'reference': 'OP-1', 'receiptId': 5},
        {'occurredAt': '2026-11-26T14:30:00+00:00', 'type': 'DepositReleased', 'bookingId': 7, 'amount': -100.0, 'method': null,
          'reference': null, 'receiptId': null},
      ],
    });
    await remote.signIn('recepcion@roomtrack.pe', 'x');
    final history = await remote.paymentHistory();
    expect(history.map((e) => (e.typeLabel, e.amount, e.receiptId)), [('Pago de consumos', 30.0, 5), ('Garantía liberada', -100.0, null)]);
  });

  test('auditoría, huecos de cobertura, mantenimiento y climatización', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'GET /audit-logs': {
        'items': [
          {'id': 9, 'occurredAt': '2026-11-25T08:00:00Z', 'action': 'SignInFailed', 'outcome': 'Failure', 'actorUserId': null,
            'actorEmail': 'x@roomtrack.pe', 'targetUserId': 3, 'targetEmail': 'limpieza@roomtrack.pe', 'hotelId': 1, 'ipAddress': '10.0.0.1',
            'details': null},
        ],
        'page': 1, 'pageSize': 30, 'totalCount': 41, 'totalPages': 2,
      },
      'GET /shifts/coverage-gaps': [
        {'shift': {'id': 20, 'hotelId': 1, 'date': '2026-12-01', 'period': 'Morning', 'area': 'FrontDesk', 'minimumStaff': 2,
          'coverageGap': 2, 'assignees': const []}, 'missing': 2, 'isCritical': true},
      ],
      'GET /rooms/10/maintenance-history': {
        'roomId': 10, 'correctiveCount': 4, 'preventiveCount': 2, 'recurringCount': 1, 'incidents': const [],
        'preventivePlans': [{'id': 1, 'hotelId': 1, 'roomId': 10, 'title': 'Revisar aire', 'frequencyDays': 30, 'nextDueOn': '2026-12-10',
          'reminderDaysBefore': 2, 'isActive': true}],
      },
      'GET /io-t-emulator/rooms/10/actuators-state': {'roomId': 10, 'emulatedDevice': 'Cisco_SBC_Board_Virtual', 'currentTemperature': 22.0,
        'motionDetected': false, 'lastCommandReceived': 'AUTO_POWER_SAVING_MODE_TRIGGERED', 'hardwareStatus': 'OPERATIONAL_EMULATED',
        'timestamp': '2026-11-25T10:00:00Z'},
      'POST /io-t-emulator/rooms/10/thermostat': {'roomId': 10, 'currentTemperature': 20.0, 'motionDetected': true,
        'lastCommandReceived': 'SET_TEMPERATURE_20C_FAN_HIGH', 'hardwareStatus': 'OPERATIONAL_EMULATED', 'timestamp': '2026-11-25T10:05:00Z'},
    });
    await remote.signIn('admin@roomtrack.pe', 'x');

    final audit = await remote.auditLog(action: 'SignInFailed');
    expect((audit.total, audit.totalPages), (41, 2));
    expect(audit.items.single.actionLabel, 'Inicio de sesión fallido');
    expect(audit.items.single.succeeded, isFalse);

    final gap = (await remote.coverageGaps()).single;
    expect((gap.shiftId, gap.missing, gap.critical), (20, 2, true));

    final summary = await remote.maintenanceSummary(10);
    expect((summary.corrective, summary.preventive, summary.recurring), (4, 2, 1));
    expect(summary.plans.single.title, 'Revisar aire');

    final climate = await remote.roomClimate(10);
    expect(climate.powerSaving, isTrue);
    final set = await remote.setThermostat(10, 20, 'High');
    expect((set.temperature, set.fanSpeed), (20.0, 'HIGH'));
    expect(_bodyOf(calls, 'POST /io-t-emulator/rooms/10/thermostat'),
        {'targetTemperatureCelsius': 20.0, 'fanSpeed': 'High', 'simulationMode': 'CiscoPacketTracer_SBC'});
    expect(() => remote.setThermostat(10, 40, 'Low'), throwsA(isA<DomainException>()));
  });

  test('ficha de personal: se crea con su asignación al hotel y se edita', () async {
    final calls = <String>[];
    var profile = _staffJson();
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'POST /staff': () => profile,
      'POST /staff/a1b2c3d4-0000-0000-0000-000000000001/assignments': () {
        profile = _staffJson(assignments: [
          {'id': 'f0000000-0000-0000-0000-000000000009', 'scope': 'Hotel', 'targetId': 1, 'role': 'Housekeeping',
            'startDate': '2026-11-25', 'endDate': null, 'status': 'Active'},
        ]);
        return profile;
      },
      'GET /staff/a1b2c3d4-0000-0000-0000-000000000001': () => profile,
      'PUT /staff/a1b2c3d4-0000-0000-0000-000000000001/job-position': () {
        profile = _staffJson(position: 'Supervisora', assignments: profile['assignments']! as List<Map<String, Object?>>);
        return null;
      },
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    final user = AppUser(id: 3, name: 'María Quispe', email: 'limpieza@roomtrack.pe', role: UserRole.housekeeping, password: '');

    final created = await remote.createStaffProfile(user,
        position: 'Camarera', shift: 'Night', contact: const ContactData(phone: '987654321', city: 'Cusco'), documentType: 0,
        documentNumber: '45678912');
    final body = _bodyOf(calls, 'POST /staff');
    expect(body, containsPair('shift', 2));
    expect(body, containsPair('documentType', 0));
    expect(body, containsPair('phone', '987654321'));
    expect(body['street'], isNull);
    // The account's role becomes its assignment at this hotel (ScopeLevel.Hotel = 1, StaffRole.Housekeeping = 3).
    expect(_bodyOf(calls, 'POST /staff/a1b2c3d4-0000-0000-0000-000000000001/assignments'),
        allOf(containsPair('scope', 1), containsPair('targetId', 1), containsPair('role', 3)));
    expect(created.assignments.single.roleLabel, 'Limpieza');
    expect(created.shiftLabel, 'Noche');

    final updated = await remote.setStaffPosition(created, 'Supervisora');
    expect(updated.position, 'Supervisora');
  });

  test('ficha del huésped: sin ficha es null y el huésped crea la suya', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _guest, signIn: {'id': 6, 'token': 'access'}, calls: calls, extra: {
      'POST /guests': {
        'id': 'b0000000-0000-0000-0000-000000000001', 'userId': 6, 'firstName': 'Sofía', 'lastName': 'Herrera', 'fullName': 'Sofía Herrera',
        'email': 'huesped@roomtrack.pe', 'phone': '912345678', 'documentType': 'Passport', 'documentNumber': 'X1234567', 'status': 'Active',
        'createdAt': '2026-11-25T10:00:00Z',
      },
    });
    await remote.signIn('huesped@roomtrack.pe', 'x');
    expect(await remote.myGuestProfile(), isNull);

    final created = await remote.createGuestProfile(
        name: 'Sofía Herrera', email: 'huesped@roomtrack.pe', contact: const ContactData(phone: '912345678'), userId: 6);
    expect(_bodyOf(calls, 'POST /guests'), allOf(containsPair('firstName', 'Sofía'), containsPair('userId', 6), containsPair('phone', '912345678')));
    expect(created.document, 'Pasaporte X1234567');
    expect(() => remote.createGuestProfile(name: 'Sofía', email: '', contact: const ContactData(phone: '1')), throwsA(isA<DomainException>()));
  });
}
