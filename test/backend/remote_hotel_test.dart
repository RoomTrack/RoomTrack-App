import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roomtrack/core/backend/api_client.dart';
import 'package:roomtrack/core/backend/remote_hotel.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/domain/models.dart';

/// A fake gateway answering the routes the app uses, with the shapes of the real backend. A route can map to a
/// function to answer with what earlier calls changed.
RemoteHotel fakeBackend({required Map<String, Object?> me, Map<String, Object?> signIn = const {},
    Map<String, Object?> extra = const {}, List<String>? calls}) {
  final routes = <String, Object?>{
    'POST /authentication/sign-in': signIn,
    'GET /users/me': me,
    'GET /users': [
      {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'status': 'Active', 'hotelId': 1},
      {'id': 3, 'email': 'limpieza@roomtrack.pe', 'firstName': 'María', 'lastName': 'Quispe', 'role': 'housekeeping', 'status': 'Inactive', 'hotelId': 1},
    ],
    'GET /rooms': [
      {'id': 10, 'hotelId': 1, 'roomTypeId': 1, 'roomTypeName': 'Suite', 'price': 205, 'status': 'Occupied', 'number': '304'},
      {'id': 11, 'hotelId': 1, 'roomTypeId': 2, 'roomTypeName': 'Doble', 'price': 140, 'status': 'Cleaning', 'number': '201'},
      {'id': 12, 'hotelId': 2, 'roomTypeId': 2, 'roomTypeName': 'Doble', 'price': 140, 'status': 'Available', 'number': '101'},
    ],
    'GET /bookings': [
      {
        'id': 7, 'code': 'SS-AAAA1111', 'hotelId': 1, 'roomId': 10, 'roomNumber': '304', 'guestName': 'Sofía Herrera',
        'guestEmail': 'huesped@roomtrack.pe', 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-08T00:00:00',
        'nights': 3, 'pricePerNight': 205, 'totalPrice': 615, 'status': 'CheckedIn', 'createdAt': '2026-10-01T10:00:00Z',
        'checkedInAt': '2026-10-05T15:10:00Z', 'userId': 6,
      },
      {
        'id': 8, 'code': 'SS-BBBB2222', 'hotelId': 1, 'roomId': 11, 'roomNumber': '201', 'guestName': 'Andrés Molina',
        'guestEmail': 'huesped2@roomtrack.pe', 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-06T00:00:00',
        'nights': 1, 'pricePerNight': 140, 'totalPrice': 140, 'status': 'Pending', 'createdAt': '2026-10-02T10:00:00Z',
        'paymentDueAt': '2026-10-06T10:00:00Z', 'userId': 8,
      },
      {'id': 9, 'status': 'Cancelled', 'roomId': 11, 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-06T00:00:00', 'totalPrice': 1},
    ],
    'GET /payments/booking/7': {
      'id': 70, 'bookingId': 7, 'transactionId': 'YAPE-1', 'amount': 615, 'status': 'Completed', 'method': 'Yape',
      'paymentDate': '2026-10-01 10:05:00',
    },
    'GET /bookings/7/check-in': {'accessCode': '304911'},
    ...extra,
  };
  final client = MockClient((request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^.*?(?=/[a-z])'), '');
    final key = '${request.method} $path';
    calls?.add(request.body.isEmpty ? key : '$key ${request.body}');
    if (!routes.containsKey(key)) return http.Response(jsonEncode({'title': 'Not found', 'status': 404}), 404);
    // A function answers with the current state of the fake backend.
    final body = switch (routes[key]) { final Object? Function() answer => answer(), final value => value };
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final store = HotelStore(seed: false);
  final remote = RemoteHotel(store, ApiClient(client: client));
  store.remote = remote;
  return remote;
}

void main() {
  test('el personal con autenticador pide el código de 6 dígitos', () async {
    final remote = fakeBackend(
      me: const {},
      signIn: {'id': 1, 'email': 'admin@roomtrack.pe', 'token': null, 'mfaRequired': true, 'mfaToken': 'mfa-token'},
    );
    final outcome = await remote.signIn('admin@roomtrack.pe', 'x');
    expect(outcome, isA<MfaCodeNeeded>().having((o) => o.mfaToken, 'mfaToken', 'mfa-token'));
  });

  test('el administrador sincroniza su hotel: habitaciones, personal, reservas y pagos', () async {
    final remote = fakeBackend(
      me: {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1},
      signIn: {'id': 1, 'token': 'access', 'refreshToken': 'refresh'},
    );
    final outcome = await remote.signIn('admin@roomtrack.pe', 'x');
    final store = remote.store;

    expect(outcome, isA<SignedIn>());
    expect(store.currentUser!.name, 'Ana Torres');
    // Only the rooms of the admin's hotel; Cleaning is shown as pending cleaning.
    expect(store.rooms.map((r) => r.number), ['201', '304']);
    expect(store.rooms.firstWhere((r) => r.number == '201').status, RoomStatus.dirty);
    expect(store.rooms.firstWhere((r) => r.number == '304').type, RoomType.suite);
    expect(store.users.firstWhere((u) => u.id == 3).active, isFalse);

    // Cancelled bookings disappear; Pending ones wait for the front desk to register the payment.
    expect(store.stays.map((s) => s.id), [7, 8]);
    final sofia = store.stayById(7);
    expect(sofia.status, StayStatus.checkedIn);
    expect(sofia.code, 'SS-AAAA1111');
    expect(store.totalCharges(sofia), 615);
    expect(store.balanceOf(sofia), 0);
    expect(store.stayById(8).awaitingPayment, isTrue);
    expect(store.payments.single.method, 'Yape');
  });

  test('el huésped recibe su código de acceso', () async {
    final remote = fakeBackend(
      me: {'id': 6, 'email': 'huesped@roomtrack.pe', 'firstName': 'Sofía', 'lastName': 'Herrera', 'role': 'guest', 'hotelId': null},
      signIn: {'id': 6, 'token': 'access'},
    );
    await remote.signIn('huesped@roomtrack.pe', 'x');
    final stay = remote.store.activeStayOf(6)!;
    expect(stay.accessCode, '304911');
  });

  test('los errores del backend llegan en español', () {
    final error = ApiClient.problem(401, jsonEncode({'title': 'Invalid credentials', 'code': 'mfa.code_already_used'}));
    expect(error.message, 'Ese código ya se usó. Espera el siguiente de tu app autenticadora.');
    final validation = ApiClient.problem(400, jsonEncode({'errors': {'email': ['El correo no es válido.']}}));
    expect(validation.message, 'El correo no es válido.');
  });

  test('el administrador configura los medios de pago del hotel', () async {
    final calls = <String>[];
    final settings = {
      'hotelId': 1, 'acceptsBookings': true, 'accountHolder': 'Casa Aurora S.A.C.', 'yapeNumber': '987654321',
      'plinNumber': null, 'bankName': null, 'bankAccountNumber': null, 'bankAccountCci': null,
    };
    final remote = fakeBackend(
      me: {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1},
      signIn: {'id': 1, 'token': 'access'},
      extra: {'GET /hotels/1/payment-settings': {...settings, 'acceptsBookings': false}, 'PUT /hotels/1/payment-settings': settings},
      calls: calls,
    );
    await remote.signIn('admin@roomtrack.pe', 'x');

    expect((await remote.paymentSettings()).acceptsBookings, isFalse);
    final saved = await remote.updatePaymentSettings(
        const HotelPaymentSettings(accountHolder: ' Casa Aurora S.A.C. ', yapeNumber: '987654321', plinNumber: ' '));
    expect(saved.acceptsBookings, isTrue);
    // Blank methods go as null: not offered.
    final put = jsonDecode(calls.last.substring('PUT /hotels/1/payment-settings '.length)) as Map<String, dynamic>;
    expect(put, {
      'accountHolder': 'Casa Aurora S.A.C.', 'yapeNumber': '987654321', 'plinNumber': null,
      'bankName': null, 'bankAccountNumber': null, 'bankAccountCci': null,
    });
  });

  test('cancelar una reserva, restablecer el MFA y cerrar todas las sesiones', () async {
    final calls = <String>[];
    final remote = fakeBackend(
      me: {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1},
      signIn: {'id': 1, 'token': 'access', 'refreshToken': 'refresh'},
      extra: {'POST /bookings/8/cancel': {'id': 8, 'status': 'Cancelled'}, 'POST /users/3/mfa/reset': {'message': 'ok'}, 'POST /authentication/sign-out-all': null},
      calls: calls,
    );
    await remote.signIn('admin@roomtrack.pe', 'x');

    await remote.cancelBooking(8);
    await remote.resetMfa(remote.store.users.firstWhere((u) => u.id == 3));
    await remote.signOutEverywhere();

    expect(calls, containsAllInOrder(['POST /bookings/8/cancel', 'POST /users/3/mfa/reset', 'POST /authentication/sign-out-all']));
    expect(remote.api.session, isNull);
    expect(remote.store.currentUser, isNull);
  });

  test('cada regla rota de los medios de pago llega en español', () {
    final error = ApiClient.problem(400, jsonEncode({
      'code': 'validation.failed',
      'errors': {'yapeNumber': ['Yape must be a 9-digit mobile.']},
      'violations': [
        {'field': 'accountHolder', 'code': 'payment_settings.account_holder_required', 'message': 'Required.'},
        {'field': 'yapeNumber', 'code': 'payment_settings.yape_number_invalid', 'message': 'Yape must be a 9-digit mobile.'},
      ],
    }));
    expect(error.message,
        'Indica a nombre de quién se paga.\nEl número de Yape debe ser un celular de 9 dígitos que empiece con 9.');
  });

  Map<String, Object?> incident({int id = 40, String status = 'Pending', int? assignee, List<Object?>? history}) => {
        'id': id, 'hotelId': 1, 'roomId': 10, 'title': 'Ducha sin agua caliente', 'description': null, 'priority': 'Critical',
        'status': status, 'blocksRoom': true, 'reportedByUserId': 2, 'reportedByEmail': 'recepcion@roomtrack.pe',
        'reportedAt': '2026-10-25T13:00:00+00:00', 'assigneeUserId': assignee, 'assignedAt': null, 'startedAt': null,
        'resolvedAt': status == 'Resolved' ? '2026-10-25T15:00:00+00:00' : null, 'resolvedByUserId': null,
        'resolutionNotes': status == 'Resolved' ? 'Se cambió la resistencia.' : null, 'escalatedAt': null, 'history': history,
      };

  test('el personal sincroniza las incidencias del hotel y conserva el preventivo local', () async {
    final remote = fakeBackend(
      me: {'id': 4, 'email': 'mantenimiento@roomtrack.pe', 'firstName': 'Luis', 'lastName': 'Paredes', 'role': 'maintenance', 'hotelId': 1},
      signIn: {'id': 4, 'token': 'access'},
      extra: {'GET /incidents': [incident(), incident(id: 41, status: 'Resolved', assignee: 4)]},
    );
    remote.store.incidents.add(Incident(id: 1000001, roomId: 10, title: 'Preventivo: aire', description: '', category: 'Preventivo',
        urgency: Priority.normal, reportedById: 1, createdAt: DateTime(2026, 10, 1), preventive: true, blocksRoom: false));
    await remote.signIn('mantenimiento@roomtrack.pe', 'x');
    final store = remote.store;

    expect(store.incidents.map((i) => i.id), containsAll([40, 41, 1000001]));
    final open = store.incidentById(40);
    expect(open.urgency, Priority.urgent);
    expect(open.status, WorkStatus.pending);
    expect(open.assigneeId, isNull);
    expect(open.reportedByEmail, 'recepcion@roomtrack.pe');
    expect(store.incidentById(41).resolvedAt, isNotNull);
    expect(store.hasBlockingIncident(10), isTrue);
  });

  test('reportar, tomar y resolver una incidencia van al backend con su historial en español', () async {
    final calls = <String>[];
    // What the backend lists (without history) after each call.
    var listed = <Object?>[];
    Object? answer(Map<String, Object?> data) {
      listed = [{...data, 'history': null}];
      return data;
    }
    final remote = fakeBackend(
      me: {'id': 4, 'email': 'mantenimiento@roomtrack.pe', 'firstName': 'Luis', 'lastName': 'Paredes', 'role': 'maintenance', 'hotelId': 1},
      signIn: {'id': 4, 'token': 'access'},
      extra: {
        'GET /incidents': () => listed,
        'POST /incidents': () => answer(incident()),
        'POST /incidents/40/start': () => answer(incident(status: 'InProgress', assignee: 4, history: [
          {'action': 'Reported', 'status': 'Pending', 'detail': 'Priority Critical, blocks the room', 'actorUserId': 2,
            'actorEmail': 'recepcion@roomtrack.pe', 'occurredAt': '2026-10-25T13:00:00+00:00'},
          {'action': 'Assigned', 'status': 'Pending', 'detail': 'Assigned to user 4', 'actorUserId': 4,
            'actorEmail': 'mantenimiento@roomtrack.pe', 'occurredAt': '2026-10-25T13:05:00+00:00'},
          {'action': 'PriorityChanged', 'status': 'Pending', 'detail': 'Critical → High', 'actorUserId': 4,
            'actorEmail': 'mantenimiento@roomtrack.pe', 'occurredAt': '2026-10-25T13:06:00+00:00'},
        ])),
        'POST /incidents/40/resolve': () => answer(incident(status: 'Resolved', assignee: 4)),
      },
      calls: calls,
    );
    await remote.signIn('mantenimiento@roomtrack.pe', 'x');

    await remote.reportIncident(roomId: 10, title: ' Ducha sin agua caliente ', description: '', urgency: Priority.urgent, blocksRoom: true);
    final report = jsonDecode(calls.firstWhere((c) => c.startsWith('POST /incidents ')).substring('POST /incidents '.length));
    expect(report, {'roomId': 10, 'title': 'Ducha sin agua caliente', 'priority': 'Critical', 'blocksRoom': true});

    await remote.startIncident(40);
    final started = remote.store.incidentById(40);
    expect(started.status, WorkStatus.inProgress);
    expect(started.events.map((e) => e.text), [
      'Reportada · recepcion@roomtrack.pe',
      'Asignada a Luis Paredes · mantenimiento@roomtrack.pe',
      'Prioridad: Urgente → Alta · mantenimiento@roomtrack.pe',
    ]);

    await expectLater(remote.resolveIncident(40, '  '), throwsA(isA<DomainException>()));
    await remote.resolveIncident(40, 'Se cambió la resistencia.');
    expect(calls, contains('POST /incidents/40/resolve {"resolutionNotes":"Se cambió la resistencia."}'));
    expect(remote.store.incidentById(40).isOpen, isFalse);
    // The history loaded with the incident survives the list sync.
    expect(remote.store.incidentById(40).events, isNotEmpty);
  });

  Map<String, Object?> cleaningTask({int id = 60, int roomId = 11, String status = 'Pending', int? assignee, List<Object?>? history}) => {
        'id': id, 'hotelId': 1, 'roomId': roomId, 'priority': 'High', 'status': status, 'notes': 'Llega un huésped a las 15:00',
        'createdByUserId': null, 'createdAt': '2026-10-25T12:00:00+00:00', 'assigneeUserId': assignee, 'assignedAt': null,
        'assignedAutomatically': false, 'startedAt': status == 'Pending' ? null : '2026-10-25T12:10:00+00:00',
        'completedAt': status == 'Completed' ? '2026-10-25T12:40:00+00:00' : null, 'completedByUserId': null,
        'cancelledAt': null, 'cancellationReason': null, 'impedimentIncidentIds': const [], 'history': history,
      };

  const housekeeper = {'id': 3, 'email': 'limpieza@roomtrack.pe', 'firstName': 'María', 'lastName': 'Quispe', 'role': 'housekeeping', 'hotelId': 1};

  test('sin el módulo de limpieza en el backend las tareas siguen en el dispositivo', () async {
    final remote = fakeBackend(me: housekeeper, signIn: {'id': 3, 'token': 'access'});
    await remote.signIn('limpieza@roomtrack.pe', 'x');
    final local = remote.store.createCleaningTask(11);
    await remote.sync();

    expect(remote.hasCleaningTasks, isFalse);
    expect(remote.store.cleaningBackend, isNull);
    expect(remote.store.tasks, contains(local));
  });

  test('con el módulo de limpieza las tareas vienen del backend y el checklist queda en el dispositivo', () async {
    final calls = <String>[];
    var listed = <Object?>[cleaningTask(), cleaningTask(id: 61, roomId: 10, status: 'Cancelled')];
    Object? answer(Map<String, Object?> data) {
      listed = [{...data, 'history': null}];
      return data;
    }
    final remote = fakeBackend(
      me: housekeeper,
      signIn: {'id': 3, 'token': 'access'},
      extra: {
        'GET /cleaning-tasks': () => listed,
        'POST /cleaning-tasks/60/start': () => answer(cleaningTask(status: 'InProgress', assignee: 3, history: [
              {'action': 'Created', 'status': 'Pending', 'detail': 'Priority High, the room went to Cleaning', 'incidentId': null,
                'actorUserId': null, 'actorEmail': null, 'occurredAt': '2026-10-25T12:00:00+00:00'},
              {'action': 'Assigned', 'status': 'Pending', 'detail': 'Assigned to user 3', 'incidentId': null, 'actorUserId': 3,
                'actorEmail': 'limpieza@roomtrack.pe', 'occurredAt': '2026-10-25T12:09:00+00:00'},
              {'action': 'Started', 'status': 'InProgress', 'detail': null, 'incidentId': null, 'actorUserId': 3,
                'actorEmail': 'limpieza@roomtrack.pe', 'occurredAt': '2026-10-25T12:10:00+00:00'},
            ])),
        'POST /cleaning-tasks/60/impediments': () => answer(cleaningTask(status: 'InProgress', assignee: 3)),
        'POST /cleaning-tasks/60/complete': () => answer(cleaningTask(status: 'Completed', assignee: 3)),
      },
      calls: calls,
    );
    await remote.signIn('limpieza@roomtrack.pe', 'x');
    final store = remote.store;

    expect(remote.hasCleaningTasks, isTrue);
    // Cancelled tasks are left out; the checklist is the one of the room type.
    expect(store.tasks.map((t) => t.id), [60]);
    final task = store.taskById(60);
    expect(task.priority, Priority.high);
    expect(task.notes, 'Llega un huésped a las 15:00');
    expect(task.checklist, isNotEmpty);

    // A housekeeper takes the unassigned task by starting it; the room is "en limpieza" for everyone.
    await remote.startCleaningTask(60);
    expect(store.taskById(60).status, TaskStatus.inProgress);
    expect(store.taskById(60).events.map((e) => e.text), [
      'Tarea creada al pasar la habitación a limpieza · prioridad alta',
      'Asignada a María Quispe · limpieza@roomtrack.pe',
      'Limpieza iniciada · limpieza@roomtrack.pe',
    ]);
    expect(store.rooms.firstWhere((r) => r.id == 11).status, RoomStatus.cleaning);

    // The checklist stays on this device across syncs and must be done before completing.
    store.toggleChecklistItem(60, 0, true);
    await remote.sync();
    expect(store.taskById(60).checklist.first.done, isTrue);
    await expectLater(remote.completeCleaningTask(60), throwsA(isA<DomainException>()));
    expect(calls, isNot(contains('POST /cleaning-tasks/60/complete')));

    await remote.reportImpediment(60, description: ' Espejo roto ', urgency: Priority.urgent);
    expect(jsonDecode(calls.firstWhere((c) => c.startsWith('POST /cleaning-tasks/60/impediments ')).substring(36)), {
      'title': 'Desperfecto detectado en limpieza', 'description': 'Espejo roto', 'priority': 'Critical', 'blocksRoom': true,
    });

    for (final item in store.taskById(60).checklist.where((i) => i.required)) {
      item.done = true;
    }
    await remote.completeCleaningTask(60);
    expect(store.taskById(60).status, TaskStatus.done);
  });

  test('crear una tarea sin responsable deja que el backend la asigne por carga', () async {
    final calls = <String>[];
    final remote = fakeBackend(
      me: {'id': 2, 'email': 'recepcion@roomtrack.pe', 'firstName': 'Rosa', 'lastName': 'Díaz', 'role': 'reception', 'hotelId': 1},
      signIn: {'id': 2, 'token': 'access'},
      extra: {
        'GET /cleaning-tasks': const [],
        'GET /cleaning-tasks/settings': {'hotelId': 1, 'autoAssign': true, 'updatedAt': null, 'updatedByUserId': null},
        'POST /cleaning-tasks': cleaningTask(roomId: 10, assignee: 3),
      },
      calls: calls,
    );
    await remote.signIn('recepcion@roomtrack.pe', 'x');
    expect(remote.store.autoAssignCleaning, isTrue);

    await remote.createCleaningTask(10, priority: Priority.urgent);
    expect(calls, contains('POST /cleaning-tasks {"roomId":10,"priority":"Urgent"}'));
  });
}

