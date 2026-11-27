import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/backend/remote_reports.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/domain/models.dart';

import 'remote_hotel_test.dart' show fakeBackend;

const _admin = {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1};
const _guest = {'id': 6, 'email': 'huesped@roomtrack.pe', 'firstName': 'Sofía', 'lastName': 'Herrera', 'role': 'guest'};

/// A stay of the guest already checked out (booking 20).
const _finishedStay = {
  'id': 20, 'code': 'SS-CCCC3333', 'hotelId': 1, 'roomId': 10, 'roomNumber': '304', 'guestName': 'Sofía Herrera',
  'guestEmail': 'huesped@roomtrack.pe', 'checkInDate': '2026-11-01T00:00:00', 'checkOutDate': '2026-11-03T00:00:00',
  'nights': 2, 'pricePerNight': 205, 'totalPrice': 410, 'status': 'Completed', 'createdAt': '2026-10-20T10:00:00Z',
  'checkedInAt': '2026-11-01T15:00:00Z', 'checkedOutAt': '2026-11-03T11:00:00Z', 'userId': 6,
};

const _review = {
  'id': 5, 'bookingId': 20, 'hotelId': 1, 'roomId': 10, 'guestUserId': 6, 'overallRating': 4, 'frontDeskRating': 5,
  'housekeepingRating': 3, 'maintenanceRating': null, 'comment': 'La ducha tardaba en calentar',
  'submittedAt': '2026-11-03T18:00:00Z',
};

const _breakfast = {
  'id': 3, 'hotelId': 1, 'name': 'Desayuno a la habitación', 'description': 'Continental, de 7:00 a 10:30', 'area': 'Reception',
  'price': 35.0, 'isIncluded': false, 'estimatedMinutes': 30, 'isAvailable': true,
};

/// The JSON body sent with the last call to [route].
Map<String, dynamic> _bodyOf(List<String> calls, String route) {
  final call = calls.lastWhere((c) => c.startsWith('$route {'));
  return jsonDecode(call.substring(route.length + 1)) as Map<String, dynamic>;
}

void main() {
  test('US-18: el panel del administrador trae los contadores que calcula el backend', () async {
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, extra: {
      'GET /hotels/1/dashboard': {
        'hotelId': 1, 'generatedAt': '2026-11-26T15:00:00Z',
        'rooms': {'total': 20, 'available': 8, 'occupied': 9, 'cleaning': 2, 'maintenance': 1, 'occupancyPercent': 45.0},
        'cleaning': {'open': 4, 'unassigned': 1, 'overdue': 1, 'overdueAfterMinutes': 60},
        'incidents': {'open': 3, 'critical': 1, 'high': 1, 'blockingRooms': 1, 'escalated': 1, 'recurring': 0},
        'guestRequests': {'open': 2, 'pending': 1, 'late': 1},
        'frontDesk': {
          'arrivalsToday': 3, 'inHouse': 9, 'departuresToday': 2, 'reviewsLast30Days': 12, 'averageRatingLast30Days': 4.33,
          'latestReviews': [_review],
        },
        'attention': [
          {'kind': 'Incident', 'referenceId': 52, 'roomId': 12, 'roomNumber': '204', 'title': 'Cerradura rota',
            'reason': 'Escalated', 'since': '2026-11-26T13:40:00Z'},
        ],
      },
    });
    await remote.signIn('admin@roomtrack.pe', 'x');

    final panel = remote.dashboard!;
    expect((panel.roomsOccupied, panel.roomsTotal, panel.occupancyPercent), (9, 20, 45.0));
    expect((panel.cleaningOpen, panel.cleaningOverdue, panel.incidentsCritical, panel.requestsLate), (4, 1, 1, 1));
    expect((panel.frontDesk!.arrivals, panel.frontDesk!.inHouse, panel.frontDesk!.departures), (3, 9, 2));
    final review = panel.frontDesk!.latestReviews.single;
    expect(review.overall, 4);
    expect(review.scores, {Area.reception: 5, Area.housekeeping: 3});
    expect(panel.attention.single.reasonLabel, 'Escalada');
    expect(panel.attention.single.roomNumber, '204');
  });

  test('sin el módulo del Sprint 4 (backend antiguo) la app sigue con lo del dispositivo', () async {
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'});
    await remote.signIn('admin@roomtrack.pe', 'x');

    expect(remote.dashboard, isNull);
    expect(remote.hasServiceCatalog, isFalse);
    expect(remote.hasReportSchedules, isFalse);
    expect(remote.store.services, isNotEmpty, reason: 'the demo catalog stays');
  });

  test('US-33: el huésped ve el catálogo del hotel y su pedido viaja con el servicio', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _guest, signIn: {'id': 6, 'token': 'access'}, calls: calls, extra: {
      'GET /service-catalog': [_breakfast],
      'POST /guest-requests': {
        'id': 41, 'hotelId': 1, 'roomId': 10, 'bookingId': 7, 'guestUserId': 6, 'title': 'Desayuno a la habitación',
        'description': null, 'area': 'Reception', 'status': 'Pending', 'createdByUserId': 6, 'createdByGuest': true,
        'createdAt': '2026-11-26T10:00:00Z', 'estimatedAttentionBy': '2026-11-26T10:30:00Z', 'serviceItemId': 3,
        'servicePrice': 35.0, 'history': [],
      },
    });
    await remote.signIn('huesped@roomtrack.pe', 'x');
    final store = remote.store;

    final breakfast = store.services.single;
    expect((breakfast.id, breakfast.name, breakfast.price, breakfast.area, breakfast.minutes),
        (3, 'Desayuno a la habitación', 35.0, Area.reception, 30));

    await remote.requestCatalogService(breakfast);

    expect(_bodyOf(calls, 'POST /guest-requests'), {'serviceItemId': 3});
    expect(store.requests.any((r) => r.id == 41), isTrue);
  });

  test('US-21: el huésped evalúa su estancia y el backend la guarda', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _guest, signIn: {'id': 6, 'token': 'access'}, calls: calls, extra: {
      'GET /bookings': [_finishedStay],
      'POST /bookings/20/review': _review,
    });
    await remote.signIn('huesped@roomtrack.pe', 'x');
    final store = remote.store;
    expect(store.stayById(20).rated, isFalse);

    await remote.submitStayReview(20, overall: 4, frontDesk: 5, housekeeping: 3, maintenance: 4, comment: ' La ducha tardaba ');

    expect(_bodyOf(calls, 'POST /bookings/20/review'), {
      'overallRating': 4, 'frontDeskRating': 5, 'housekeepingRating': 3, 'maintenanceRating': 4, 'comment': 'La ducha tardaba',
    });
    expect(store.stayById(20).rated, isTrue);
    expect(store.ratings.single.comment, 'La ducha tardaba en calentar');
  });

  test('US-21: al sincronizar, una estancia ya evaluada no vuelve a pedir la evaluación', () async {
    final remote = fakeBackend(me: _guest, signIn: {'id': 6, 'token': 'access'}, extra: {
      'GET /bookings': [_finishedStay],
      'GET /bookings/20/review': _review,
    });
    await remote.signIn('huesped@roomtrack.pe', 'x');

    expect(remote.store.stayById(20).rated, isTrue);
  });

  test('US-24/25/26: los reportes del período se leen del backend', () async {
    final calls = <String>[];
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'GET /staff-performance/productivity': {
        'hotelId': 1, 'from': '2026-11-01T00:00:00Z', 'to': '2026-12-01T00:00:00Z', 'totalCompleted': 4,
        'collaborators': [
          {'userId': 7, 'fullName': 'Rosa Quispe', 'email': 'rosa@roomtrack.pe', 'role': 'Housekeeping', 'cleaningTasksCompleted': 3,
            'incidentsResolved': 0, 'guestRequestsResolved': 1, 'totalCompleted': 4, 'averageWorkMinutes': 32.5},
        ],
        'areas': [
          {'area': 'FrontDesk', 'completed': 0, 'collaborators': 0, 'averagePerCollaborator': 0, 'averageWorkMinutes': null},
          {'area': 'Housekeeping', 'completed': 4, 'collaborators': 1, 'averagePerCollaborator': 4, 'averageWorkMinutes': 32.5},
        ],
      },
      'GET /staff-performance/service-times': {
        'cleaning': {'count': 3, 'averageResponseMinutes': 12.3, 'averageWorkMinutes': 31.7, 'averageTotalMinutes': 44, 'longestTotalMinutes': 70},
        'incidents': {'count': 0},
        'guestRequests': {'count': 1, 'averageTotalMinutes': 15},
        'guestRequestsByArea': [
          {'area': 'Housekeeping', 'count': 1, 'averageTotalMinutes': 15},
        ],
      },
      'GET /stay-reviews/satisfaction': {
        'overall': {'count': 3, 'average': 4, 'satisfiedPercent': 66.7, 'distribution': [0, 0, 1, 1, 1]},
        'areas': [
          {'area': 'Maintenance', 'count': 3, 'average': 2.33, 'satisfiedPercent': 0, 'distribution': [0, 2, 1, 0, 0]},
        ],
      },
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    final period = Period(DateTime(2026, 11, 1), DateTime(2026, 11, 30, 23, 59, 59));

    final staff = await remote.staffReport(period);
    final times = await remote.serviceTimes(period);
    final satisfaction = await remote.satisfaction(period);

    expect(staff.collaborators.single.name, 'Rosa Quispe');
    expect(staff.areas.map((a) => a.area), [Area.reception, Area.housekeeping]);
    expect((times.cleaning.count, times.cleaning.work, times.incidents.total), (3, 31.7, null));
    expect(times.requestsByArea[Area.housekeeping]!.total, 15);
    expect((satisfaction.overall.average, satisfaction.byArea[Area.maintenance]!.average), (4.0, 2.33));
    expect(calls.any((c) => c.startsWith('GET /staff-performance/productivity')), isTrue);
  });

  test('US-34: el administrador ve y programa el envío de los reportes', () async {
    final calls = <String>[];
    final schedule = {
      'id': 9, 'hotelId': 1, 'frequency': 'Weekly', 'recipients': ['gerencia@hotel.pe'], 'includeProductivity': true,
      'includeServiceTimes': true, 'isActive': true, 'nextRunAt': '2026-11-30T13:00:00Z', 'lastSentAt': null,
    };
    final remote = fakeBackend(me: _admin, signIn: {'id': 1, 'token': 'access'}, calls: calls, extra: {
      'GET /staff-performance/report-schedules': [schedule],
      'POST /staff-performance/report-schedules': {...schedule, 'id': 10, 'frequency': 'Monthly', 'nextRunAt': '2026-12-01T13:00:00Z'},
    });
    await remote.signIn('admin@roomtrack.pe', 'x');
    final store = remote.store;

    final weekly = store.schedules.single;
    expect((weekly.id, weekly.frequencyDays), (9, 7));
    expect(weekly.recipients, ['gerencia@hotel.pe']);
    expect(weekly.kind, 'Productividad y Tiempos de atención');

    await remote.createReportSchedule(monthly: true, recipients: ['gerencia@hotel.pe'], serviceTimes: false);

    expect(_bodyOf(calls, 'POST /staff-performance/report-schedules'), {
      'frequency': 'Monthly', 'recipients': ['gerencia@hotel.pe'], 'includeProductivity': true, 'includeServiceTimes': false,
    });
    expect(store.schedules.map((s) => s.frequencyDays), [7, 30]);
  });
}
