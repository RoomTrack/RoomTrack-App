import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'hotel_store.dart';

/// Password shared by every demo account.
const String kDemoPassword = 'demo123';

/// Hotel shown to guests in the mockups.
const String kHotelName = 'Casa Aurora Boutique Hotel';
const String kHotelImage =
    'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1200&q=80';

const List<({String email, UserRole role, String label})> kDemoAccounts = [
  (email: 'admin@roomtrack.com', role: UserRole.admin, label: 'Administrador'),
  (email: 'recepcion@roomtrack.com', role: UserRole.reception, label: 'Recepción'),
  (email: 'limpieza@roomtrack.com', role: UserRole.housekeeping, label: 'Limpieza'),
  (email: 'mantenimiento@roomtrack.com', role: UserRole.maintenance, label: 'Mantenimiento'),
  (email: 'huesped@roomtrack.com', role: UserRole.guest, label: 'Huésped hospedada'),
  (email: 'huesped2@roomtrack.com', role: UserRole.guest, label: 'Huésped con reserva'),
];

/// Fills the store with a believable hotel day plus a month of history for analytics.
void seedDemoData(HotelStore store) {
  final now = store.now;
  final today = DateUtils.dateOnly(now);
  final random = Random(7);
  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  final admin = AppUser(id: 1, name: 'Ana Torres', email: 'admin@roomtrack.com', phone: '987 654 321', role: UserRole.admin, password: kDemoPassword);
  final reception = AppUser(id: 2, name: 'Luis Ramos', email: 'recepcion@roomtrack.com', phone: '987 111 222', role: UserRole.reception, password: kDemoPassword);
  final maria = AppUser(id: 3, name: 'María Quispe', email: 'limpieza@roomtrack.com', phone: '987 333 444', role: UserRole.housekeeping, password: kDemoPassword);
  final jorge = AppUser(id: 4, name: 'Jorge Díaz', email: 'limpieza2@roomtrack.com', phone: '987 555 666', role: UserRole.housekeeping, password: kDemoPassword);
  final carlos = AppUser(id: 5, name: 'Carlos Vega', email: 'mantenimiento@roomtrack.com', phone: '987 777 888', role: UserRole.maintenance, password: kDemoPassword);
  final guest = AppUser(id: 6, name: 'Sofía Herrera', email: 'huesped@roomtrack.com', phone: '999 000 111', role: UserRole.guest, password: kDemoPassword);
  final rosa = AppUser(id: 7, name: 'Rosa Medina', email: 'recepcion2@roomtrack.com', role: UserRole.reception, password: kDemoPassword);
  final andres = AppUser(id: 8, name: 'Andrés Molina', email: 'huesped2@roomtrack.com', role: UserRole.guest, password: kDemoPassword);
  store.users.addAll([admin, reception, maria, jorge, carlos, guest, rosa, andres]);

  Room room(String number, int floor, RoomType type, RoomStatus status) =>
      Room(id: int.parse(number), number: number, floor: floor, type: type, status: status);
  store.rooms.addAll([
    room('101', 1, RoomType.standard, RoomStatus.occupied),
    room('102', 1, RoomType.standard, RoomStatus.dirty),
    room('103', 1, RoomType.standard, RoomStatus.available),
    room('104', 1, RoomType.twin, RoomStatus.cleaning),
    room('201', 2, RoomType.twin, RoomStatus.available),
    room('202', 2, RoomType.twin, RoomStatus.maintenance),
    room('203', 2, RoomType.twin, RoomStatus.occupied),
    room('204', 2, RoomType.twin, RoomStatus.dirty),
    room('301', 3, RoomType.suite, RoomStatus.available),
    room('302', 3, RoomType.suite, RoomStatus.dirty),
    room('303', 3, RoomType.suite, RoomStatus.available),
    room('304', 3, RoomType.suite, RoomStatus.occupied),
  ]);

  // --- A month of history: finished stays, cleanings, incidents and ratings ---
  for (var day = 28; day >= 1; day--) {
    for (final roomItem in store.rooms) {
      if (random.nextInt(3) != 0) continue;
      final housekeeper = random.nextBool() ? maria : jorge;
      final created = ago(days: day, hours: 4 + random.nextInt(4));
      final baseMinutes = switch (roomItem.type) {
        RoomType.standard => 22,
        RoomType.twin => 28,
        RoomType.suite => 45,
      };
      // Cleaning gets a little faster over the month, so the trend chart tells a story.
      final minutes = baseMinutes + random.nextInt(12) + (day ~/ 4);
      final started = created.add(Duration(minutes: 10 + random.nextInt(50)));
      final task = CleaningTask(
        id: store.nextId(),
        roomId: roomItem.id,
        checklist: HotelStore.checklistFor(roomItem.type)..forEach((item) => item.done = true),
        createdAt: created,
        assigneeId: housekeeper.id,
        priority: Priority.values[random.nextInt(3)],
        status: TaskStatus.done,
      )
        ..startedAt = started
        ..completedAt = started.add(Duration(minutes: minutes));
      task.events.add(TimelineEvent(task.completedAt!, 'Habitación marcada como limpia'));
      store.tasks.add(task);

      final stay = Stay(
        id: store.nextId(),
        guestName: _guestNames[random.nextInt(_guestNames.length)],
        guestEmail: 'cliente${random.nextInt(900)}@correo.com',
        roomType: roomItem.type,
        roomId: roomItem.id,
        checkIn: ago(days: day + 2),
        checkOut: ago(days: day),
        status: StayStatus.checkedOut,
        rated: true,
        depositHeld: 150,
        depositRefunded: true,
      )
        ..checkedInAt = ago(days: day + 2)
        ..checkedOutAt = ago(days: day, hours: 1);
      stay.receptionistIds.add(random.nextBool() ? reception.id : rosa.id);
      stay.charges.add(FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 2 noches', amount: roomItem.type.nightlyRate * 2, createdAt: stay.checkIn));
      store.stays.add(stay);
      final payment = Payment(
        id: store.nextId(),
        stayId: stay.id,
        amount: roomItem.type.nightlyRate * 2,
        method: 'Tarjeta •••• ${1000 + random.nextInt(8999)}',
        kind: PaymentKind.reservation,
        status: PaymentStatus.approved,
        createdAt: stay.checkIn,
      );
      store.payments.add(payment);
      store.receipts.add(Receipt(
        id: store.nextId(),
        paymentId: payment.id,
        stayId: stay.id,
        number: 'B001-${(store.receipts.length + 1).toString().padLeft(6, '0')}',
        type: 'Boleta',
        email: stay.guestEmail,
        amount: payment.amount,
        createdAt: payment.createdAt,
      ));
      payment.receiptId = store.receipts.last.id;

      if (random.nextInt(2) == 0) {
        store.ratings.add(Rating(
          stayId: stay.id,
          scores: {
            Area.housekeeping: housekeeper == maria ? 4 + random.nextInt(2) : 3 + random.nextInt(2),
            Area.reception: 4 + random.nextInt(2),
            Area.maintenance: 3 + random.nextInt(3),
          },
          comment: '',
          createdAt: stay.checkedOutAt!,
          staffIds: {
            Area.housekeeping: {housekeeper.id},
            Area.reception: {...stay.receptionistIds},
            Area.maintenance: {carlos.id},
          },
        ));
      }
    }

    if (random.nextInt(3) == 0) {
      final roomItem = store.rooms[random.nextInt(store.rooms.length)];
      final created = ago(days: day, hours: 6);
      final incident = Incident(
        id: store.nextId(),
        roomId: roomItem.id,
        title: _incidentTitles[random.nextInt(_incidentTitles.length)],
        description: '',
        category: HotelStore.incidentCategories[random.nextInt(HotelStore.incidentCategories.length - 1)],
        urgency: Priority.values[random.nextInt(4)],
        reportedById: maria.id,
        createdAt: created,
        assigneeId: carlos.id,
        status: WorkStatus.resolved,
        resolutionNotes: 'Reparado y verificado.',
      )..resolvedAt = created.add(Duration(hours: 1 + random.nextInt(6)));
      store.incidents.add(incident);
    }
  }

  // Room 202 has a recurring plumbing problem (US-10).
  for (final days in [24, 15, 6]) {
    store.incidents.add(Incident(
      id: store.nextId(),
      roomId: 202,
      title: 'Fuga en el lavabo',
      description: 'Goteo constante bajo el lavabo.',
      category: 'Plomería',
      urgency: Priority.high,
      reportedById: maria.id,
      createdAt: ago(days: days),
      assigneeId: carlos.id,
      status: WorkStatus.resolved,
      resolutionNotes: 'Se ajustó la conexión.',
    )..resolvedAt = ago(days: days, hours: -3));
  }

  // --- Today ---
  final pedro = Stay(
    id: store.nextId(),
    guestName: 'Pedro Salas',
    guestEmail: 'pedro.salas@correo.com',
    roomType: RoomType.standard,
    roomId: 101,
    checkIn: ago(days: 2),
    checkOut: DateTime(today.year, today.month, today.day, 12),
    status: StayStatus.checkedIn,
    depositHeld: 150,
  )
    ..checkedInAt = ago(days: 2)
    ..accessCode = '482915';
  pedro.receptionistIds.add(reception.id);
  pedro.charges.addAll([
    FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 2 noches', amount: 240, createdAt: ago(days: 2)),
    FolioCharge(id: store.nextId(), description: 'Minibar', amount: 35, createdAt: ago(hours: 10)),
    FolioCharge(id: store.nextId(), description: 'Lavandería', amount: 25, createdAt: ago(hours: 20)),
  ]);
  store.stays.add(pedro);
  store.payments.add(Payment(
    id: store.nextId(),
    stayId: pedro.id,
    amount: 240,
    method: 'Tarjeta •••• 4242',
    kind: PaymentKind.reservation,
    status: PaymentStatus.approved,
    createdAt: ago(days: 2),
  ));

  final lucia = Stay(
    id: store.nextId(),
    guestName: 'Lucía Fernández',
    guestEmail: 'lucia.f@correo.com',
    roomType: RoomType.twin,
    roomId: 203,
    checkIn: ago(days: 1),
    checkOut: DateTime(today.year, today.month, today.day + 2, 12),
    status: StayStatus.checkedIn,
    depositHeld: 150,
  )
    ..checkedInAt = ago(days: 1)
    ..accessCode = '730264';
  lucia.charges.add(FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 3 noches', amount: 540, createdAt: ago(days: 1)));
  store.stays.add(lucia);
  store.payments.add(Payment(
    id: store.nextId(),
    stayId: lucia.id,
    amount: 540,
    method: 'Tarjeta •••• 1881',
    kind: PaymentKind.reservation,
    status: PaymentStatus.approved,
    createdAt: ago(days: 1),
  ));

  // The guest of the "Mi estadía" mockup: Suite 304, 2 guests, check-out tomorrow at 11:00.
  final sofia = Stay(
    id: store.nextId(),
    guestUserId: guest.id,
    guestName: guest.name,
    guestEmail: guest.email,
    roomType: RoomType.suite,
    guests: 2,
    roomId: 304,
    checkIn: DateTime(today.year, today.month, today.day - 2, 15),
    checkOut: DateTime(today.year, today.month, today.day + 1, 11),
    status: StayStatus.checkedIn,
    depositHeld: 150,
    digital: true,
    documentId: '70123456',
  )
    ..checkedInAt = ago(days: 2)
    ..accessCode = '304911';
  sofia.charges.addAll([
    FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 3 noches', amount: 615, createdAt: ago(days: 2)),
    FolioCharge(id: store.nextId(), description: 'Minibar', amount: 24, createdAt: ago(hours: 20)),
    FolioCharge(id: store.nextId(), description: 'Spa', amount: 85, createdAt: ago(hours: 6)),
  ]);
  store.stays.add(sofia);

  final andresStay = Stay(
    id: store.nextId(),
    guestUserId: andres.id,
    guestName: andres.name,
    guestEmail: andres.email,
    roomType: RoomType.twin,
    guests: 2,
    checkIn: DateTime(today.year, today.month, today.day, 15),
    checkOut: DateTime(today.year, today.month, today.day + 3, 11),
  );
  andresStay.charges.add(FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 3 noches', amount: 420, createdAt: ago(days: 5)));
  store.stays.add(andresStay);

  // Reserved room 302 is still dirty: reception gets alternatives on check-in.
  final early = Stay(
    id: store.nextId(),
    guestName: 'Diego Paredes',
    guestEmail: 'diego.p@correo.com',
    roomType: RoomType.suite,
    roomId: 302,
    checkIn: DateTime(today.year, today.month, today.day, 14),
    checkOut: DateTime(today.year, today.month, today.day + 1, 12),
  );
  early.charges.add(FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 1 noche', amount: 205, createdAt: ago(days: 3)));
  store.stays.add(early);

  final tomorrow = Stay(
    id: store.nextId(),
    guestName: 'Valeria Castro',
    guestEmail: 'valeria.c@correo.com',
    roomType: RoomType.standard,
    checkIn: DateTime(today.year, today.month, today.day + 1, 15),
    checkOut: DateTime(today.year, today.month, today.day + 3, 12),
  );
  tomorrow.charges.add(FolioCharge(id: store.nextId(), description: 'Cargo de habitación · 2 noches', amount: 190, createdAt: ago(days: 2)));
  store.stays.add(tomorrow);

  CleaningTask openTask(int roomId, int? assignee, Priority priority, int minutesAgo, {bool started = false}) {
    final task = CleaningTask(
      id: store.nextId(),
      roomId: roomId,
      checklist: HotelStore.checklistFor(store.roomById(roomId).type),
      createdAt: ago(minutes: minutesAgo),
      assigneeId: assignee,
      priority: priority,
      status: started ? TaskStatus.inProgress : TaskStatus.pending,
    );
    task.events.add(TimelineEvent(task.createdAt, 'Tarea creada'));
    if (assignee != null) task.events.add(TimelineEvent(task.createdAt, 'Asignada a ${store.userName(assignee)}'));
    if (started) {
      task.startedAt = ago(minutes: 12);
      for (final item in task.checklist.take(3)) {
        item.done = true;
      }
      task.events.add(TimelineEvent(task.startedAt!, 'Limpieza iniciada'));
    }
    store.tasks.add(task);
    return task;
  }

  final urgent102 = openTask(102, maria.id, Priority.urgent, 75);
  openTask(104, jorge.id, Priority.high, 40, started: true);
  openTask(204, maria.id, Priority.normal, 30);
  openTask(302, null, Priority.high, 20);

  final leak = Incident(
    id: store.nextId(),
    roomId: 202,
    title: 'Fuga en el lavabo',
    description: 'El agua sale por la base del lavabo y moja el piso.',
    category: 'Plomería',
    urgency: Priority.urgent,
    reportedById: maria.id,
    createdAt: ago(minutes: 45),
    assigneeId: carlos.id,
    recurring: true,
  );
  leak.events.add(TimelineEvent(leak.createdAt, 'Reportada por María Quispe · Urgente'));
  store.incidents.add(leak);

  final ac = Incident(
    id: store.nextId(),
    roomId: 203,
    title: 'Aire acondicionado hace ruido',
    description: 'El huésped reporta un zumbido por la noche.',
    category: 'Aire acondicionado',
    urgency: Priority.normal,
    reportedById: reception.id,
    createdAt: ago(hours: 3),
    assigneeId: carlos.id,
    status: WorkStatus.inProgress,
    blocksRoom: false,
  );
  ac.events.add(TimelineEvent(ac.createdAt, 'Reportada por Luis Ramos · Normal'));
  store.incidents.add(ac);

  store.requests.add(GuestRequest(
    id: store.nextId(),
    roomId: 203,
    stayId: lucia.id,
    description: 'Dos almohadas adicionales',
    area: Area.housekeeping,
    createdAt: ago(minutes: 15),
    etaMinutes: 20,
    createdById: reception.id,
  )..events.add(TimelineEvent(ago(minutes: 15), 'Registrada y derivada a Limpieza')));
  store.requests.add(GuestRequest(
    id: store.nextId(),
    roomId: 101,
    stayId: pedro.id,
    description: 'Taxi al aeropuerto a las 13:00',
    area: Area.reception,
    createdAt: ago(minutes: 50),
    etaMinutes: 10,
    createdById: reception.id,
    status: WorkStatus.inProgress,
  )..events.add(TimelineEvent(ago(minutes: 50), 'Registrada en Recepción')));

  seedCatalog(store);

  store.preventiveTasks.addAll([
    PreventiveTask(id: store.nextId(), title: 'Revisión de aire acondicionado', roomId: 301, frequencyDays: 30, nextDue: now.add(const Duration(days: 1))),
    PreventiveTask(id: store.nextId(), title: 'Purga de calentador de agua', roomId: 202, frequencyDays: 90, nextDue: now.add(const Duration(days: 12))),
  ]);

  Shift shift(int dayOffset, Area area, String label, int start, int end, int minStaff, List<int> staff) => Shift(
        id: store.nextId(),
        date: today.add(Duration(days: dayOffset)),
        area: area,
        label: label,
        startHour: start,
        endHour: end,
        minStaff: minStaff,
        staffIds: staff,
      );
  store.shifts.addAll([
    for (final offset in [0, 1, 2]) ...[
      shift(offset, Area.reception, 'Mañana', 7, 15, 1, [reception.id]),
      shift(offset, Area.reception, 'Tarde', 15, 23, 1, [rosa.id]),
      shift(offset, Area.housekeeping, 'Mañana', 7, 15, 2, [maria.id, jorge.id]),
      shift(offset, Area.housekeeping, 'Tarde', 15, 23, 1, offset == 1 ? [] : [jorge.id]),
      shift(offset, Area.maintenance, 'Mañana', 8, 16, 1, [carlos.id]),
    ],
  ]);

  store.handovers.add(Handover(
    id: store.nextId(),
    authorId: jorge.id,
    area: Area.housekeeping,
    notes: 'Faltan sábanas de suite en el almacén del 3er piso. La 102 tiene llegada temprano.',
    createdAt: ago(hours: 9),
    openItems: ['Limpieza hab. 102 · Pendiente', 'Limpieza hab. 302 · Pendiente'],
  ));

  void say(String channel, AppUser who, String text, int minutesAgo) => store.messages.add(ChatMessage(
        id: store.nextId(),
        channel: channel,
        authorId: who.id,
        authorName: who.name,
        text: text,
        createdAt: ago(minutes: minutesAgo),
      ));
  say(HotelStore.areaChannel(Area.housekeeping), jorge, 'Buenos días equipo, ya repuse amenities en el 2do piso.', 120);
  say(HotelStore.areaChannel(Area.housekeeping), maria, '¡Gracias! Voy con la 102 apenas termine el carrito.', 110);
  say(HotelStore.taskChannel(urgent102.id), reception, 'María, el huésped de la 102 llega a las 14:00, ¿podrás tenerla antes?', 30);
  say(HotelStore.guestChannel(sofia.id), reception, 'Hola Sofía, bienvenida a Casa Aurora. Escríbenos aquí si necesitas algo.', 180);
  say(HotelStore.guestChannel(andresStay.id), reception, 'Hola Andrés, te esperamos hoy. Puedes hacer tu check-in desde la app.', 90);

  store.notifications.addAll([
    AppNotification(id: store.nextId(), userId: maria.id, title: 'Tarea urgente', body: 'Habitación 102 · llegada temprana', type: NotificationType.priority, urgent: true, createdAt: ago(minutes: 30)),
    AppNotification(id: store.nextId(), userId: carlos.id, title: 'Nueva incidencia', body: 'Hab. 202: Fuga en el lavabo (Urgente)', type: NotificationType.incident, urgent: true, createdAt: ago(minutes: 45)),
  ]);

  store.schedules.add(ReportSchedule(
    id: store.nextId(),
    name: 'Resumen operativo semanal',
    kind: 'Operativo',
    frequencyDays: 7,
    recipients: [admin.email],
    format: 'Excel',
    nextSend: today.add(const Duration(days: 3, hours: 8)),
  ));

  store.runChecks();
}

const List<String> _guestNames = [
  'Andrea Rojas',
  'Martín López',
  'Camila Núñez',
  'Javier Soto',
  'Daniela Ríos',
  'Fernando Paz',
  'Gabriela León',
  'Ricardo Vargas',
];

const List<String> _incidentTitles = [
  'Foco quemado',
  'Puerta no cierra bien',
  'Ducha con baja presión',
  'Control de TV no funciona',
  'Silla dañada',
];

/// The eight service categories of the "Servicios" mockup. The backend has no catalog yet, so the app always
/// brings it.
void seedCatalog(HotelStore store) {
  ServiceItem service(String name, String description, double price, Area area, IconData icon) =>
      ServiceItem(id: store.nextId(), name: name, description: description, price: price, area: area, icon: icon);
  store.services.addAll([
    service('Limpieza', 'Limpieza de la habitación cuando lo prefieras.', 0, Area.housekeeping, Icons.cleaning_services_outlined),
    service('Toallas extra', 'Juego adicional de toallas de baño.', 0, Area.housekeeping, Icons.view_agenda_outlined),
    service('Amenidades', 'Shampoo, jabón, kit dental y más.', 0, Area.housekeeping, Icons.bathtub_outlined),
    service('Lavandería', 'Lavado y planchado, entrega en 24 horas.', 25, Area.housekeeping, Icons.local_laundry_service_outlined),
    service('Comida y bebida', 'Desayuno o snacks servidos en tu habitación.', 35, Area.reception, Icons.restaurant_outlined),
    service('Reportar un problema', 'Aire, luces, TV o cualquier desperfecto.', 0, Area.maintenance, Icons.build_outlined),
    service('Salida tardía', 'Check-out hasta las 3:00 p. m., sujeto a disponibilidad.', 40, Area.reception, Icons.schedule),
    service('Conserjería', 'Reservas, taxis y recomendaciones de la ciudad.', 0, Area.reception, Icons.room_service_outlined),
  ]);
}
