import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/core/permissions.dart';
import 'package:roomtrack/core/seed.dart';
import 'package:roomtrack/domain/models.dart';

const _okCard = CardInfo(number: '4242 4242 4242 4242', holder: 'Sofía Herrera', expiry: '12/30', cvv: '123');
const _declinedCard = CardInfo(number: '4000 0000 0000 0002', holder: 'Sofía Herrera', expiry: '12/30', cvv: '123');

void main() {
  late DateTime now;
  late HotelStore store;

  setUp(() {
    now = DateTime(2026, 10, 5, 10);
    store = HotelStore(clock: () => now);
  });

  AppUser user(String email) => store.users.firstWhere((u) => u.email == email);

  group('US-01 / US-03 acceso por rol', () {
    test('credenciales inválidas no revelan qué dato falló', () {
      expect(
        () => store.signIn('admin@roomtrack.com', 'mala'),
        throwsA(isA<DomainException>().having((e) => e.message, 'message', 'Correo o contraseña incorrectos.')),
      );
      expect(
        () => store.signIn('nadie@roomtrack.com', kDemoPassword),
        throwsA(isA<DomainException>().having((e) => e.message, 'message', 'Correo o contraseña incorrectos.')),
      );
    });

    test('limpieza no accede a funciones de administrador', () {
      expect(canAccess(UserRole.housekeeping, Feature.staffAdmin), isFalse);
      expect(canAccess(UserRole.housekeeping, Feature.myTasks), isTrue);
      expect(canAccess(UserRole.admin, Feature.staffAdmin), isTrue);
    });

    test('una cuenta desactivada pierde el acceso', () {
      store.signIn('admin@roomtrack.com', kDemoPassword);
      store.setActive(user('limpieza@roomtrack.com'), false);
      expect(() => store.signIn('limpieza@roomtrack.com', kDemoPassword), throwsA(isA<DomainException>()));
    });

    test('recuperación de contraseña con enlace de un solo uso', () {
      store.requestPasswordReset('recepcion@roomtrack.com');
      final token = store.lastResetToken('recepcion@roomtrack.com')!;
      store.resetPassword(token, 'nueva123');
      expect(store.signIn('recepcion@roomtrack.com', 'nueva123').role, UserRole.reception);
      expect(() => store.resetPassword(token, 'otra123'), throwsA(isA<DomainException>()));
    });
  });

  group('US-02 perfil', () {
    test('rechaza correos inválidos y exige la contraseña actual', () {
      final me = user('limpieza@roomtrack.com');
      expect(() => store.updateProfile(me, name: 'María', email: 'sin-arroba', phone: '', photoUrl: ''), throwsA(isA<DomainException>()));
      expect(me.email, 'limpieza@roomtrack.com');
      expect(() => store.changePassword(me, 'equivocada', 'nueva123'), throwsA(isA<DomainException>()));
      store.changePassword(me, kDemoPassword, 'nueva123');
      expect(me.password, 'nueva123');
    });
  });

  group('US-05 / US-06 / US-07 limpieza', () {
    test('la asignación automática elige al colaborador con menos carga', () {
      final maria = user('limpieza@roomtrack.com');
      final jorge = user('limpieza2@roomtrack.com');
      final lighter = store.openLoad(maria.id) <= store.openLoad(jorge.id) ? maria : jorge;
      final task = store.createCleaningTask(103);
      expect(task.assigneeId, lighter.id);
    });

    test('reasignar mueve la tarea de una lista a otra', () {
      final maria = user('limpieza@roomtrack.com');
      final jorge = user('limpieza2@roomtrack.com');
      final task = store.tasksFor(maria.id).first;
      store.assignTask(task.id, jorge.id);
      expect(store.tasksFor(maria.id).map((t) => t.id), isNot(contains(task.id)));
      expect(store.tasksFor(jorge.id).map((t) => t.id), contains(task.id));
    });

    test('la lista sale ordenada por prioridad', () {
      final tasks = store.tasksFor(user('limpieza@roomtrack.com').id);
      for (var i = 1; i < tasks.length; i++) {
        expect(tasks[i - 1].priority.index, greaterThanOrEqualTo(tasks[i].priority.index));
      }
    });

    test('no se puede marcar limpia sin la checklist obligatoria', () {
      final task = store.tasks.firstWhere((t) => t.roomId == 102 && t.isOpen);
      store.startTask(task.id);
      expect(store.roomById(102).status, RoomStatus.cleaning);
      expect(() => store.completeTask(task.id), throwsA(isA<DomainException>()));
      for (var i = 0; i < task.checklist.length; i++) {
        if (task.checklist[i].required) store.toggleChecklistItem(task.id, i, true);
      }
      expect(task.progress, lessThan(1));
      store.completeTask(task.id);
      expect(store.roomById(102).status, RoomStatus.available);
    });

    test('la checklist depende del tipo de habitación', () {
      expect(HotelStore.checklistFor(RoomType.suite).map((i) => i.label), contains('Limpiar jacuzzi'));
      expect(HotelStore.checklistFor(RoomType.standard).map((i) => i.label), isNot(contains('Limpiar jacuzzi')));
    });

    test('un impedimento genera una incidencia para mantenimiento', () {
      final task = store.tasks.firstWhere((t) => t.roomId == 204 && t.isOpen);
      final incident = store.reportImpediment(task.id, description: 'Grifo roto', urgency: Priority.high, reporterId: 3);
      expect(incident.status, WorkStatus.pending);
      expect(store.notifications.where((n) => n.userId == 5 && n.body.contains('204')), isNotEmpty);
    });
  });

  group('US-08 / US-09 / US-10 incidencias', () {
    test('una incidencia abierta bloquea la habitación y al resolverla pasa a limpieza', () {
      final incident = store.createIncident(
        roomId: 201,
        title: 'Puerta trabada',
        description: '',
        category: 'Cerrajería',
        urgency: Priority.normal,
        reporterId: 2,
      );
      expect(store.isAssignable(store.roomById(201)), isFalse);
      store.startIncident(incident.id);
      store.resolveIncident(incident.id, 'Cerradura cambiada');
      expect(store.roomById(201).status, RoomStatus.dirty);
      expect(store.tasks.any((t) => t.roomId == 201 && t.isOpen), isTrue);
    });

    test('marca patrón recurrente con más de 3 incidencias similares en un mes', () {
      final incident = store.createIncident(
        roomId: 202,
        title: 'Otra fuga',
        description: '',
        category: 'Plomería',
        urgency: Priority.high,
        reporterId: 3,
      );
      expect(incident.recurring, isTrue);
      expect(store.activeAlerts.any((a) => a.key == 'recurrence-202-Plomería'), isTrue);
    });

    test('una incidencia crítica sin atender se escala al administrador', () {
      final incident = store.createIncident(
        roomId: 103,
        title: 'Cortocircuito',
        description: '',
        category: 'Electricidad',
        urgency: Priority.urgent,
        reporterId: 2,
      );
      store.runChecks();
      expect(incident.escalated, isFalse);
      now = now.add(const Duration(minutes: 31));
      store.runChecks();
      expect(incident.escalated, isTrue);
      expect(store.notificationsFor(1).any((n) => n.title == 'Incidencia crítica sin resolver' && n.body.contains('103')), isTrue);
    });
  });

  group('US-13 / US-15 check-in digital', () {
    test('requiere depósito y asigna habitación con código de acceso', () {
      final stay = store.activeStayOf(8)!;
      store.startDigitalCheckIn(stay.id, '70123456');
      expect(stay.status, StayStatus.checkInInProgress);
      expect(() => store.confirmArrival(stay.id, '70123456'), throwsA(isA<DomainException>()));

      expect(() => store.payDeposit(stay.id, _declinedCard), throwsA(isA<PaymentDeclinedException>()));
      expect(store.paymentsOf(stay.id).first.status, PaymentStatus.rejected);
      store.payDeposit(stay.id, _okCard);
      expect(stay.depositHeld, stay.depositRequired);
      expect(store.receipts.any((r) => r.stayId == stay.id), isTrue);

      expect(() => store.confirmArrival(stay.id, '00000000'), throwsA(isA<DomainException>()));
      store.confirmArrival(stay.id, '70123456');
      expect(stay.status, StayStatus.checkedIn);
      expect(stay.accessCode, hasLength(6));
      expect(store.roomById(stay.roomId!).status, RoomStatus.occupied);
    });

    test('informa el tiempo de espera si no hay habitación lista', () {
      final stay = store.activeStayOf(8)!;
      store.rooms.firstWhere((r) => r.number == '201').status = RoomStatus.dirty;
      store.startDigitalCheckIn(stay.id, '70123456');
      store.payDeposit(stay.id, _okCard);
      expect(() => store.confirmArrival(stay.id, '70123456'), throwsA(isA<RoomNotReadyException>()));
    });
  });

  group('US-14 / US-16 / US-17 check-out y pagos', () {
    Stay pedro() => store.stays.firstWhere((s) => s.guestName == 'Pedro Salas');

    test('no permite el check-out con cargos pendientes', () {
      expect(() => store.checkOut(pedro().id), throwsA(isA<PendingChargesException>()));
    });

    test('pago dividido, check-out, devolución del depósito y habitación por limpiar', () {
      final stay = pedro();
      final balance = store.balanceOf(stay);
      expect(balance, 60);
      store.payBalance(stay.id, [(amount: 40, card: _okCard), (amount: 20, card: null)]);
      expect(store.balanceOf(stay), 0);
      store.checkOut(stay.id);
      expect(stay.status, StayStatus.checkedOut);
      expect(stay.depositRefunded, isTrue);
      expect(store.roomById(101).status, RoomStatus.dirty);
      expect(store.paymentsOf(stay.id).any((p) => p.kind == PaymentKind.refund), isTrue);
      expect(store.outbox.any((m) => m.to == stay.guestEmail && m.subject == 'Comprobante de tu estancia'), isTrue);
    });

    test('los montos divididos deben cubrir el saldo exacto', () {
      expect(() => store.payBalance(pedro().id, [(amount: 10, card: _okCard)]), throwsA(isA<DomainException>()));
    });

    test('con datos fiscales emite factura y se puede reenviar', () {
      final stay = pedro();
      store.setFiscalData(stay.id, const FiscalData(ruc: '20123456789', businessName: 'Viajes SAC', address: 'Lima'));
      store.payBalance(stay.id, [(amount: 60, card: _okCard)]);
      final receipt = store.receipts.last;
      expect(receipt.type, 'Factura');
      store.resendReceipt(receipt.id);
      expect(receipt.sentCount, 2);
    });

    test('extender la estancia agrega noches al folio', () {
      final stay = store.stays.firstWhere((s) => s.guestName == 'Lucía Fernández');
      final before = store.totalCharges(stay);
      store.extendStay(stay.id, 2);
      expect(store.totalCharges(stay), before + 2 * RoomType.twin.nightlyRate);
    });
  });

  group('US-27 / US-28 recepción', () {
    test('sugiere alternativas si la habitación reservada no está lista', () {
      final diego = store.stays.firstWhere((s) => s.guestName == 'Diego Paredes');
      try {
        store.assistedCheckIn(diego.id, 302, receptionistId: 2);
        fail('Debió avisar que la habitación no está lista');
      } on RoomNotReadyException catch (e) {
        expect(e.alternatives.map((r) => r.number), contains('301'));
      }
      store.assistedCheckIn(diego.id, 301, receptionistId: 2);
      expect(store.roomById(301).status, RoomStatus.occupied);
      expect(store.isAssignable(store.roomById(301)), isFalse);
    });
  });

  group('US-19 / US-33 solicitudes y servicios', () {
    test('un servicio con costo crea la solicitud y el cargo en el folio', () {
      final lucia = store.stays.firstWhere((s) => s.guestName == 'Lucía Fernández');
      final laundry = store.services.firstWhere((s) => s.name == 'Lavandería');
      final before = store.totalCharges(lucia);
      final request = store.requestService(lucia.id, laundry.id);
      expect(request.area, Area.housekeeping);
      expect(store.totalCharges(lucia), before + laundry.price);
    });

    test('resolver una solicitud confirma al huésped', () {
      final guest = user('huesped@roomtrack.com');
      final stay = store.activeStayOf(guest.id)!;
      expect(stay.status, StayStatus.checkedIn);
      final request = store.createRequest(roomId: stay.roomId!, stayId: stay.id, description: 'Almohada', area: Area.reception, createdById: guest.id);
      store.deriveRequest(request.id, Area.housekeeping);
      store.updateRequestStatus(request.id, WorkStatus.resolved);
      expect(store.notificationsFor(guest.id).any((n) => n.title == 'Solicitud atendida'), isTrue);
    });
  });

  group('US-21 / US-26 evaluaciones', () {
    test('la evaluación queda asociada a las áreas y colaboradores', () {
      final stay = store.stays.firstWhere((s) => s.guestName == 'Lucía Fernández');
      store.checkOut(stay.id, receptionistId: 2);
      store.submitRating(stay.id, cleaning: 5, attention: 4, maintenance: 3, comment: 'Muy bien');
      final rating = store.ratings.last;
      expect(rating.staffIds[Area.reception], contains(2));
      expect(() => store.submitRating(stay.id, cleaning: 5, attention: 5, maintenance: 5), throwsA(isA<DomainException>()));
    });
  });

  group('US-22 preferencias de notificación', () {
    test('no notifica tipos desactivados', () {
      final maria = user('limpieza@roomtrack.com');
      store.setNotificationPref(maria, NotificationType.task, false);
      final before = store.notificationsFor(maria.id).length;
      store.createCleaningTask(103, assigneeId: maria.id);
      expect(store.notificationsFor(maria.id).length, before);
    });
  });

  group('US-30 / US-31 / US-32 operación diaria', () {
    test('el preventivo vencido se genera y se reprograma', () {
      final plan = store.schedulePreventive(title: 'Filtros', roomId: 103, frequencyDays: 7, firstDue: now.add(const Duration(hours: 1)));
      now = now.add(const Duration(hours: 2));
      store.runChecks();
      expect(store.incidents.any((i) => i.preventive && i.title == 'Preventivo: Filtros'), isTrue);
      expect(plan.nextDue.isAfter(now), isTrue);
      expect(store.isAssignable(store.roomById(103)), isTrue, reason: 'el preventivo no bloquea la habitación');
    });

    test('detecta huecos de cobertura y aprueba cambios de turno', () {
      expect(store.shifts.any((s) => s.hasCoverageGap), isTrue);
      final reception = store.shifts.where((s) => s.area == Area.reception).toList();
      final mine = reception.firstWhere((s) => s.staffIds.contains(2));
      final theirs = reception.firstWhere((s) => s.staffIds.contains(7) && s.date == mine.date);
      final swap = store.requestSwap(requesterId: 2, fromShiftId: mine.id, targetUserId: 7, toShiftId: theirs.id);
      store.decideSwap(swap.id, true);
      expect(mine.staffIds, contains(7));
      expect(theirs.staffIds, contains(2));
    });

    test('la entrega de turno registra quién la leyó', () {
      final maria = user('limpieza@roomtrack.com');
      final handover = store.latestHandoverFor(maria)!;
      store.markHandoverRead(handover.id, maria.id);
      expect(handover.readBy[maria.id], now);
    });
  });

  group('US-24 / US-25 / US-34 analítica', () {
    test('calcula productividad, tiempos y exporta CSV', () {
      final period = Period.lastDays(now, 30);
      expect(store.productivity(period).where((p) => p.completed > 0), isNotEmpty);
      expect(store.cleaningMinutesByType(period)[RoomType.suite], greaterThan(store.cleaningMinutesByType(period)[RoomType.standard]!));
      expect(store.incidentResolutionHours(period), greaterThan(0));
      expect(store.exportCsv(period), contains('Colaborador;Rol;Completadas'));
    });

    test('envía los reportes programados al vencer', () {
      store.scheduleReport(name: 'Diario', kind: 'Financiero', frequencyDays: 1, recipients: ['jefe@roomtrack.com'], format: 'PDF');
      now = now.add(const Duration(days: 1, minutes: 1));
      store.runChecks();
      expect(store.outbox.any((m) => m.to == 'jefe@roomtrack.com' && m.subject.startsWith('Diario')), isTrue);
    });
  });
}
