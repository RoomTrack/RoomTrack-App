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
    Map<String, Object?> extra = const {}, List<String>? calls, List<Uri>? urls}) {
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
    urls?.add(request.url);
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

  test('US-07: el checklist del backend llega con la tarea y cada ítem se marca allí', () async {
    final calls = <String>[];
    Map<String, Object?> withChecklist({bool done = false}) => {
          ...cleaningTask(status: 'InProgress', assignee: 3, history: const []),
          'checklistProgress': done ? 50 : 0,
          'checklist': [
            {'id': 501, 'position': 1, 'label': 'Cambiar la ropa de cama', 'isRequired': true, 'isDone': done, 'doneAt': null, 'doneByUserId': null},
            {'id': 502, 'position': 2, 'label': 'Revisar el minibar', 'isRequired': false, 'isDone': false, 'doneAt': null, 'doneByUserId': null},
          ],
        };
    final remote = fakeBackend(
      me: housekeeper,
      signIn: {'id': 3, 'token': 'access'},
      extra: {
        'GET /cleaning-tasks': [{...cleaningTask(status: 'InProgress', assignee: 3), 'checklistProgress': 0}],
        'GET /cleaning-tasks/60': withChecklist(),
        'PUT /cleaning-tasks/60/checklist/501': () => withChecklist(done: true),
      },
      calls: calls,
    );
    await remote.signIn('limpieza@roomtrack.pe', 'x');
    final store = remote.store;

    // The list brings only the percentage.
    expect(store.taskById(60).reportedProgress, 0);
    await remote.refreshCleaningTask(60);
    final task = store.taskById(60);
    expect(task.reportedProgress, isNull);
    expect(task.checklist.map((i) => i.label), ['Cambiar la ropa de cama', 'Revisar el minibar']);
    await expectLater(remote.completeCleaningTask(60), throwsA(isA<DomainException>()));

    await remote.markChecklistItem(60, 0, true);
    expect(calls, contains('PUT /cleaning-tasks/60/checklist/501 {"done":true}'));
    expect(store.taskById(60).checklist.first.done, isTrue);
    // The items survive the list sync.
    await remote.sync();
    expect(store.taskById(60).checklist.first.remoteId, 501);
  });

  test('US-30 / US-10 / US-23: planes preventivos, incidencias recurrentes y alertas del backend', () async {
    final calls = <String>[];
    final remote = fakeBackend(
      me: {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1},
      signIn: {'id': 1, 'token': 'access'},
      extra: {
        'GET /incidents': [
          {...incident(), 'kind': 'Corrective', 'isRecurring': true, 'recurrenceCount': 4},
          {...incident(id: 42, status: 'Pending'), 'kind': 'Preventive', 'preventivePlanId': 4, 'blocksRoom': false},
        ],
        'GET /preventive-maintenance-plans': [
          {'id': 4, 'hotelId': 1, 'roomId': 10, 'title': 'Limpiar filtros', 'description': null, 'frequencyDays': 90,
            'nextDueOn': '2027-03-01', 'reminderDaysBefore': 3, 'isActive': true, 'generatedCount': 1, 'lastIncidentId': 42,
            'lastGeneratedAt': null, 'createdByUserId': 4, 'createdAt': '2026-11-25T14:00:00+00:00'},
        ],
        'GET /incidents/alerts': [
          {'kind': 'Escalation', 'raisedAt': '2026-11-25T16:00:00+00:00', 'incidentId': 40, 'roomId': 10, 'title': 'Ducha sin agua caliente',
            'priority': 'Critical', 'status': 'Resolved', 'resolvedAt': '2026-11-25T16:40:00+00:00', 'resolvedByUserId': 4,
            'resolutionNotes': 'Resistencia cambiada'},
        ],
        'POST /preventive-maintenance-plans': const {},
      },
      calls: calls,
    );
    remote.store.preventiveTasks.add(PreventiveTask(id: 1000001, title: 'Local', roomId: 10, frequencyDays: 7, nextDue: DateTime(2026)));
    await remote.signIn('admin@roomtrack.pe', 'x');
    final store = remote.store;

    expect(remote.hasPreventivePlans, isTrue);
    expect(store.preventiveTasks.map((p) => (p.id, p.timesGenerated, p.reminderDaysBefore)), [(4, 1, 3)]);
    expect(store.incidentById(42).preventive, isTrue);
    expect(store.incidentById(40).recurring, isTrue);
    expect(store.roomHasRecurringPattern(10), isTrue);
    final alert = store.alerts.single;
    expect(alert.incidentId, 40);
    expect(alert.resolved, isTrue);
    expect(alert.resolution, 'Resistencia cambiada');

    // The backend generates the tasks: the device does not.
    store.runChecks();
    expect(store.incidents.where((i) => i.preventive).map((i) => i.id), [42]);

    await remote.schedulePreventive(title: 'Purgar calentador', roomId: 10, frequencyDays: 30, firstDue: DateTime(2026, 12, 3));
    expect(calls, contains('POST /preventive-maintenance-plans '
        '{"roomId":10,"title":"Purgar calentador","frequencyDays":30,"firstDueOn":"2026-12-03","reminderDaysBefore":2}'));
  });

  test('US-11 / US-19: las solicitudes vienen del backend con áreas numéricas', () async {
    final calls = <String>[];
    Map<String, Object?> request({int status = 0, int area = 0}) => {
          'id': 90, 'hotelId': 1, 'roomId': 10, 'bookingId': 7, 'guestUserId': 6, 'title': 'Almohada extra', 'description': null,
          'area': area, 'status': status, 'createdByUserId': 6, 'createdByGuest': true, 'createdAt': '2026-11-25T15:00:00+00:00',
          'estimatedAttentionBy': '2026-11-25T15:20:00+00:00', 'assigneeUserId': null, 'startedAt': null, 'resolvedAt': null,
          'cancelledAt': null, 'closingNote': null, 'history': null,
        };
    var listed = [request(), {...request(status: 3), 'id': 91}];
    final remote = fakeBackend(
      me: {'id': 2, 'email': 'recepcion@roomtrack.pe', 'firstName': 'Rosa', 'lastName': 'Díaz', 'role': 'reception', 'hotelId': 1},
      signIn: {'id': 2, 'token': 'access'},
      extra: {
        'GET /guest-requests': () => listed,
        'POST /guest-requests/90/route': () {
          listed = [request(area: 1)];
          return {...request(area: 1), 'history': [
            {'action': 0, 'status': 0, 'detail': 'For Reception', 'actorUserId': 6, 'actorEmail': 'huesped@roomtrack.pe', 'occurredAt': '2026-11-25T15:00:00+00:00'},
            {'action': 1, 'status': 0, 'detail': 'Reception → Housekeeping', 'actorUserId': 2, 'actorEmail': 'recepcion@roomtrack.pe', 'occurredAt': '2026-11-25T15:02:00+00:00'},
          ]};
        },
      },
      calls: calls,
    );
    await remote.signIn('recepcion@roomtrack.pe', 'x');
    final store = remote.store;

    // Cancelled requests leave the list; the promised time comes from the backend.
    expect(store.requests.map((r) => r.id), [90]);
    expect(store.requestById(90).area, Area.reception);
    expect(store.requestById(90).etaMinutes, 20);
    expect(store.requestById(90).stayId, 7);

    await remote.routeRequest(90, Area.housekeeping);
    expect(calls, contains('POST /guest-requests/90/route {"area":1}'));
    expect(store.requestById(90).area, Area.housekeeping);
    expect(store.requestById(90).events.map((e) => e.text),
        ['Registrada para Recepción · huesped@roomtrack.pe', 'Derivada a Limpieza · recepcion@roomtrack.pe']);
  });

  test('US-12 / US-20: los canales de mensajes son conversaciones del backend', () async {
    final calls = <String>[];
    final remote = fakeBackend(
      me: housekeeper,
      signIn: {'id': 3, 'token': 'access'},
      extra: {
        'GET /conversations': [
          {'id': 5, 'hotelId': 1, 'kind': 1, 'guestUserId': null, 'area': 1, 'subject': null, 'subjectId': null,
            'createdAt': '2026-11-25T10:00:00+00:00', 'lastMessageAt': '2026-11-25T10:05:00+00:00', 'messageCount': 1},
        ],
        'GET /conversations/5': {
          'conversation': {'id': 5, 'lastMessageAt': '2026-11-25T10:05:00+00:00'},
          'messages': [
            {'id': 800, 'conversationId': 5, 'senderUserId': 1, 'senderName': 'Ana Torres', 'senderIsGuest': false,
              'body': 'Hoy llegan 12 huéspedes', 'sentAt': '2026-11-25T10:05:00+00:00'},
          ],
        },
        'POST /conversations/areas/Housekeeping/messages': {'id': 801, 'conversationId': 5},
      },
      calls: calls,
    );
    await remote.signIn('limpieza@roomtrack.pe', 'x');
    final store = remote.store;

    expect(remote.hasConversations, isTrue);
    expect(store.messagesIn(HotelStore.areaChannel(Area.housekeeping)).map((m) => m.text), ['Hoy llegan 12 huéspedes']);

    await remote.sendMessage(HotelStore.areaChannel(Area.housekeeping), ' Entendido ');
    expect(calls, contains('POST /conversations/areas/Housekeeping/messages {"body":"Entendido"}'));
  });

  test('US-14 a US-17: folio, pago dividido y check-out en el backend', () async {
    final calls = <String>[];
    var balance = 48.5;
    Map<String, Object?> folio() => {
          'bookingId': 7, 'bookingCode': 'SS-AAAA1111', 'status': balance > 0 ? 'Open' : 'Settled', 'chargesTotal': 48.5,
          'paidTotal': 48.5 - balance, 'balance': balance,
          'charges': [
            {'id': 3, 'description': 'Minibar', 'category': 'Minibar', 'amount': 48.5, 'postedByUserId': 2, 'postedAt': '2026-10-06T20:00:00+00:00'},
          ],
          'payments': [
            if (balance == 0) {'id': 9, 'amount': 48.5, 'method': 'Yape', 'operationNumber': '123', 'paidAt': '2026-10-07T10:00:00+00:00'},
          ],
          'deposit': {'amount': 150, 'status': 'Held', 'method': 'Cash', 'heldAt': '2026-10-05T15:00:00+00:00', 'releasedAt': null},
          'invoiceData': null,
        };
    final remote = fakeBackend(
      me: {'id': 2, 'email': 'recepcion@roomtrack.pe', 'firstName': 'Rosa', 'lastName': 'Díaz', 'role': 'reception', 'hotelId': 1},
      signIn: {'id': 2, 'token': 'access'},
      extra: {
        'GET /bookings/7/folio': folio,
        'GET /bookings/7/receipts': const [],
        'POST /bookings/7/folio/payments': () {
          balance = 0;
          return {'folio': folio(), 'receipts': const []};
        },
        'POST /bookings/7/check-out': const {},
      },
      calls: calls,
    );
    await remote.signIn('recepcion@roomtrack.pe', 'x');
    final store = remote.store;
    final stay = store.stayById(7);

    expect(remote.hasFolios, isTrue);
    expect(stay.depositHeld, 150);
    expect(stay.charges.map((c) => c.description), contains('Minibar'));
    expect(store.balanceOf(stay), 48.5);

    await remote.payFolio(7, [(amount: 30, method: 'Yape', operationNumber: '123'), (amount: 18.5, method: 'Cash', operationNumber: '')]);
    expect(calls, contains('POST /bookings/7/folio/payments '
        '{"parts":[{"amount":30.0,"method":"Yape","operationNumber":"123"},{"amount":18.5,"method":"Cash"}]}'));
    expect(store.balanceOf(stay), 0);
    // The folio payments survive the sync.
    await remote.sync();
    expect(store.balanceOf(store.stayById(7)), 0);

    await remote.checkOut(7);
    expect(calls, contains('POST /bookings/7/check-out'));
  });

  test('US-31 / US-32: turnos, cambios y entregas de turno del backend', () async {
    final calls = <String>[];
    final remote = fakeBackend(
      me: housekeeper,
      signIn: {'id': 3, 'token': 'access'},
      extra: {
        'GET /shifts': [
          {'id': 20, 'hotelId': 1, 'date': '2026-12-01', 'period': 'Morning', 'area': 'Housekeeping', 'minimumStaff': 2, 'coverageGap': 1,
            'assignees': [{'userId': 3, 'displayName': 'María Quispe'}]},
          {'id': 21, 'hotelId': 1, 'date': '2026-12-02', 'period': 'Night', 'area': 'Housekeeping', 'minimumStaff': 1, 'coverageGap': 0,
            'assignees': [{'userId': 9, 'displayName': 'Pedro Ruiz'}]},
        ],
        'GET /shift-swaps': const [],
        'POST /shift-swaps': const {},
        'GET /shift-handovers': [
          {'id': 30, 'hotelId': 1, 'area': 'Housekeeping', 'authorUserId': 9, 'authorEmail': 'pedro@roomtrack.pe', 'notes': 'Falta la 201',
            'createdAt': '2026-11-25T07:00:00+00:00',
            'items': [{'kind': 'CleaningTask', 'referenceId': 60, 'roomId': 11, 'summary': 'Cleaning', 'status': 'Pending', 'priority': 'High', 'assigneeUserId': null}],
            'acknowledgements': const [], 'acknowledgedByMe': false},
        ],
        'POST /shift-handovers/30/acknowledge': {
          'id': 30, 'hotelId': 1, 'area': 'Housekeeping', 'authorUserId': 9, 'authorEmail': 'pedro@roomtrack.pe', 'notes': 'Falta la 201',
          'createdAt': '2026-11-25T07:00:00+00:00', 'items': const [],
          'acknowledgements': [{'userId': 3, 'email': 'limpieza@roomtrack.pe', 'acknowledgedAt': '2026-11-25T07:10:00+00:00'}],
          'acknowledgedByMe': true,
        },
      },
      calls: calls,
    );
    await remote.signIn('limpieza@roomtrack.pe', 'x');
    final store = remote.store;

    expect(remote.hasShifts, isTrue);
    expect(store.shiftsOf(3).map((s) => (s.id, s.label, s.hours)), [(20, 'Mañana', '07:00 - 15:00')]);
    expect(store.shifts.firstWhere((s) => s.id == 21).staffNames[9], 'Pedro Ruiz');
    expect(store.shifts.firstWhere((s) => s.id == 20).hasCoverageGap, isTrue);

    await remote.requestSwap(myShiftId: 20, colleagueUserId: 9, colleagueShiftId: 21);
    expect(calls, contains('POST /shift-swaps {"myShiftId":20,"colleagueUserId":9,"colleagueShiftId":21}'));

    final handover = store.latestHandoverFor(store.currentUser!)!;
    expect(handover.authorEmail, 'pedro@roomtrack.pe');
    expect(handover.openItems.single, startsWith('Limpieza hab. 201 · pendiente · alta'));
    await remote.acknowledgeHandover(30);
    expect(store.handovers.single.readBy.keys, [3]);
  });

  test('un administrador sin hotel registra el suyo y sigue con la sesión renovada', () async {
    int? hotelId;
    final calls = <String>[];
    final remote = fakeBackend(
      me: const {},
      signIn: {'id': 1, 'token': 'access', 'refreshToken': 'refresh'},
      calls: calls,
      extra: {
        'GET /users/me': () => {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': hotelId},
        'POST /hotels': () {
          hotelId = 1;
          return {
            'hotel': {'id': 1, 'name': 'Casa Aurora', 'location': 'Av. Larco 1150, Lima, Perú', 'acceptsBookings': false},
            'session': {'token': 'access-with-hotel', 'tokenType': 'Bearer', 'refreshToken': 'refresh-2'},
          };
        },
      },
    );
    await remote.signIn('admin@roomtrack.pe', 'x');
    expect(remote.needsHotel, isTrue);
    expect(calls, isNot(contains('GET /rooms')), reason: 'sin hotel no hay nada que sincronizar');

    await remote.createHotel({'name': 'Casa Aurora'});
    expect(remote.api.session?.accessToken, 'access-with-hotel');
    expect(remote.api.session?.refreshToken, 'refresh-2');
    expect(remote.hotelId, 1);
    expect(remote.needsHotel, isFalse);
    expect(remote.store.rooms.map((r) => r.number), ['201', '304']);
  });

  test('el administrador de cadena elige un hotel y todo lo que lee queda en ese hotel', () async {
    final urls = <Uri>[];
    final remote = fakeBackend(
      me: {'id': 2, 'email': 'cadena@roomtrack.pe', 'firstName': 'Carla', 'lastName': 'Ríos', 'role': 'chain_admin', 'hotelId': null},
      signIn: {'id': 2, 'token': 'access', 'refreshToken': 'refresh'},
      urls: urls,
      extra: {
        'GET /hotels': [
          {'id': 2, 'name': 'Wasi Cusco', 'location': 'Calle Plateros 3, Cusco, Perú', 'imageUrl': '', 'acceptsBookings': true},
          {'id': 1, 'name': 'Casa Aurora', 'location': 'Av. Larco 1150, Lima, Perú', 'imageUrl': '', 'acceptsBookings': false},
        ],
      },
    );
    final chosen = <int?>[];
    remote.onHotelChosen = chosen.add;
    await remote.signIn('cadena@roomtrack.pe', 'x');
    expect(remote.isChainAdmin, isTrue);
    expect(remote.needsHotel, isTrue);

    final hotels = await remote.chainHotels();
    expect(hotels.map((h) => h.name), ['Casa Aurora', 'Wasi Cusco']);

    urls.clear();
    await remote.chooseHotel(hotels.last);
    expect(chosen, [2]);
    expect(remote.hotelId, 2);
    expect(remote.needsHotel, isFalse);
    expect(remote.store.rooms.map((r) => r.number), ['101']);
    final reads = urls.where((u) => !u.path.contains('/hotels')).toList();
    expect(reads, isNotEmpty);
    expect(reads.every((u) => u.queryParameters['hotelId'] == '2'), isTrue, reason: '${reads.where((u) => u.queryParameters['hotelId'] != '2')}');

    remote.leaveHotel();
    expect(chosen, [2, null]);
    expect(remote.needsHotel, isTrue);
    expect(remote.store.rooms, isEmpty);
    expect(remote.api.scopeHotelId, isNull);
  });
}
