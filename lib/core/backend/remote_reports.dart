import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../hotel_store.dart';
import 'api_client.dart';
import 'remote_hotel.dart';

// Sprint 4 of the backend: the administrator's panel (US-18), the evaluation of the stays and the satisfaction by area
// (US-21, US-26), the staff reports and their CSV export (US-24, US-25, US-34), the scheduled delivery of the reports
// by e-mail (US-34) and the service catalog of the hotel (US-33).

DateTime? _time(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toLocal();

double? _double(Object? value) => value is num ? value.toDouble() : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// The backend's work areas: `FrontDesk`/`Reception`, `Housekeeping`, `Maintenance` (or 0, 1, 2).
Area workArea(Object? value) => switch (value) {
      'FrontDesk' || 'Reception' || 0 => Area.reception,
      'Maintenance' || 2 => Area.maintenance,
      _ => Area.housekeeping,
    };

// ---------------------------------------------------------------------------
// US-18: administrator's panel
// ---------------------------------------------------------------------------

/// Something the administrator should look at first.
class AttentionEntry {
  final String kind;
  final int referenceId;
  final String? roomNumber;
  final String title;

  /// Escalated, Critical or Late.
  final String reason;
  final DateTime since;

  const AttentionEntry(this.kind, this.referenceId, this.roomNumber, this.title, this.reason, this.since);

  bool get isIncident => kind == 'Incident';

  String get reasonLabel => switch (reason) {
        'Escalated' => 'Escalada',
        'Critical' => 'Crítica',
        _ => 'Atrasada',
      };
}

/// The front desk of today and what the guests said lately (from the Bookings service).
class FrontDeskSnapshot {
  final int arrivals;
  final int inHouse;
  final int departures;
  final int reviewsLast30Days;
  final double? averageLast30Days;
  final List<Rating> latestReviews;

  const FrontDeskSnapshot(this.arrivals, this.inHouse, this.departures, this.reviewsLast30Days, this.averageLast30Days,
      this.latestReviews);
}

/// `GET /hotels/{id}/dashboard`: every counter of the panel, calculated by the backend.
class DashboardSnapshot {
  final int roomsTotal;
  final int roomsOccupied;
  final int roomsCleaning;
  final int roomsMaintenance;
  final double occupancyPercent;
  final int cleaningOpen;
  final int cleaningUnassigned;
  final int cleaningOverdue;
  final int overdueAfterMinutes;
  final int incidentsOpen;
  final int incidentsCritical;
  final int incidentsEscalated;
  final int requestsOpen;
  final int requestsLate;

  /// Null when the backend could not reach its Bookings service.
  final FrontDeskSnapshot? frontDesk;
  final List<AttentionEntry> attention;

  const DashboardSnapshot({
    required this.roomsTotal,
    required this.roomsOccupied,
    required this.roomsCleaning,
    required this.roomsMaintenance,
    required this.occupancyPercent,
    required this.cleaningOpen,
    required this.cleaningUnassigned,
    required this.cleaningOverdue,
    required this.overdueAfterMinutes,
    required this.incidentsOpen,
    required this.incidentsCritical,
    required this.incidentsEscalated,
    required this.requestsOpen,
    required this.requestsLate,
    required this.frontDesk,
    required this.attention,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> data) {
    final rooms = data['rooms'] as Map<String, dynamic>? ?? const {};
    final cleaning = data['cleaning'] as Map<String, dynamic>? ?? const {};
    final incidents = data['incidents'] as Map<String, dynamic>? ?? const {};
    final requests = data['guestRequests'] as Map<String, dynamic>? ?? const {};
    final frontDesk = data['frontDesk'] as Map<String, dynamic>?;
    return DashboardSnapshot(
      roomsTotal: _int(rooms['total']),
      roomsOccupied: _int(rooms['occupied']),
      roomsCleaning: _int(rooms['cleaning']),
      roomsMaintenance: _int(rooms['maintenance']),
      occupancyPercent: _double(rooms['occupancyPercent']) ?? 0,
      cleaningOpen: _int(cleaning['open']),
      cleaningUnassigned: _int(cleaning['unassigned']),
      cleaningOverdue: _int(cleaning['overdue']),
      overdueAfterMinutes: _int(cleaning['overdueAfterMinutes']),
      incidentsOpen: _int(incidents['open']),
      incidentsCritical: _int(incidents['critical']),
      incidentsEscalated: _int(incidents['escalated']),
      requestsOpen: _int(requests['open']),
      requestsLate: _int(requests['late']),
      frontDesk: frontDesk == null
          ? null
          : FrontDeskSnapshot(
              _int(frontDesk['arrivalsToday']),
              _int(frontDesk['inHouse']),
              _int(frontDesk['departuresToday']),
              _int(frontDesk['reviewsLast30Days']),
              _double(frontDesk['averageRatingLast30Days']),
              [for (final r in (frontDesk['latestReviews'] as List? ?? const [])) stayRating(r as Map<String, dynamic>)],
            ),
      attention: [
        for (final a in (data['attention'] as List? ?? const []).cast<Map<String, dynamic>>())
          AttentionEntry(a['kind']?.toString() ?? '', _int(a['referenceId']), a['roomNumber']?.toString(),
              a['title']?.toString() ?? '', a['reason']?.toString() ?? '', _time(a['since']) ?? DateTime.now()),
      ],
    );
  }
}

/// An evaluation of a stay (`StayReviewResource` or the panel's `ReviewSnippet`) as the app keeps it.
Rating stayRating(Map<String, dynamic> data) => Rating(
      stayId: _int(data['bookingId']),
      overall: (data['overallRating'] as num?)?.toInt(),
      scores: {
        if (data['frontDeskRating'] case final num score) Area.reception: score.toInt(),
        if (data['housekeepingRating'] case final num score) Area.housekeeping: score.toInt(),
        if (data['maintenanceRating'] case final num score) Area.maintenance: score.toInt(),
      },
      comment: data['comment']?.toString() ?? '',
      createdAt: _time(data['submittedAt']) ?? DateTime.now(),
      staffIds: const {},
    );

// ---------------------------------------------------------------------------
// US-24 / US-25 / US-26: reports
// ---------------------------------------------------------------------------

/// The work a staff member finished in the period.
class CollaboratorStats {
  final int userId;
  final String name;
  final String role;
  final int cleanings;
  final int incidents;
  final int requests;
  final int total;
  final double? avgWorkMinutes;

  const CollaboratorStats(this.userId, this.name, this.role, this.cleanings, this.incidents, this.requests, this.total,
      this.avgWorkMinutes);
}

/// The work an area finished in the period.
class AreaWorkStats {
  final Area area;
  final int completed;
  final int collaborators;
  final double perCollaborator;
  final double? avgWorkMinutes;

  const AreaWorkStats(this.area, this.completed, this.collaborators, this.perCollaborator, this.avgWorkMinutes);
}

/// US-24: `GET /staff-performance/productivity`.
class StaffReport {
  final int totalCompleted;
  final List<CollaboratorStats> collaborators;
  final List<AreaWorkStats> areas;

  const StaffReport(this.totalCompleted, this.collaborators, this.areas);

  factory StaffReport.fromJson(Map<String, dynamic> data) => StaffReport(
        _int(data['totalCompleted']),
        [
          for (final c in (data['collaborators'] as List? ?? const []).cast<Map<String, dynamic>>())
            CollaboratorStats(
              _int(c['userId']),
              c['fullName']?.toString() ?? c['email']?.toString() ?? 'Usuario ${c['userId']}',
              c['role']?.toString() ?? '',
              _int(c['cleaningTasksCompleted']),
              _int(c['incidentsResolved']),
              _int(c['guestRequestsResolved']),
              _int(c['totalCompleted']),
              _double(c['averageWorkMinutes']),
            ),
        ],
        [
          for (final a in (data['areas'] as List? ?? const []).cast<Map<String, dynamic>>())
            AreaWorkStats(workArea(a['area']), _int(a['completed']), _int(a['collaborators']),
                _double(a['averagePerCollaborator']) ?? 0, _double(a['averageWorkMinutes'])),
        ],
      );
}

/// How long a kind of work takes, in minutes (null without measures).
class TimeIndicator {
  final int count;
  final double? response;
  final double? work;
  final double? total;
  final double? longest;

  const TimeIndicator(this.count, this.response, this.work, this.total, this.longest);

  factory TimeIndicator.fromJson(Map<String, dynamic>? data) => TimeIndicator(
        _int(data?['count']),
        _double(data?['averageResponseMinutes']),
        _double(data?['averageWorkMinutes']),
        _double(data?['averageTotalMinutes']),
        _double(data?['longestTotalMinutes']),
      );
}

/// US-25: `GET /staff-performance/service-times`.
class ServiceTimes {
  final TimeIndicator cleaning;
  final TimeIndicator incidents;
  final TimeIndicator requests;
  final Map<Area, TimeIndicator> requestsByArea;

  const ServiceTimes(this.cleaning, this.incidents, this.requests, this.requestsByArea);

  factory ServiceTimes.fromJson(Map<String, dynamic> data) => ServiceTimes(
        TimeIndicator.fromJson(data['cleaning'] as Map<String, dynamic>?),
        TimeIndicator.fromJson(data['incidents'] as Map<String, dynamic>?),
        TimeIndicator.fromJson(data['guestRequests'] as Map<String, dynamic>?),
        {
          for (final a in (data['guestRequestsByArea'] as List? ?? const []).cast<Map<String, dynamic>>())
            workArea(a['area']): TimeIndicator.fromJson(a),
        },
      );
}

/// What the guests said about the stay or an area.
class SatisfactionScore {
  final int count;
  final double? average;
  final double? satisfiedPercent;

  const SatisfactionScore(this.count, this.average, this.satisfiedPercent);

  factory SatisfactionScore.fromJson(Map<String, dynamic>? data) =>
      SatisfactionScore(_int(data?['count']), _double(data?['average']), _double(data?['satisfiedPercent']));
}

/// US-26: `GET /stay-reviews/satisfaction`.
class Satisfaction {
  final SatisfactionScore overall;
  final Map<Area, SatisfactionScore> byArea;

  const Satisfaction(this.overall, this.byArea);

  factory Satisfaction.fromJson(Map<String, dynamic> data) => Satisfaction(
        SatisfactionScore.fromJson(data['overall'] as Map<String, dynamic>?),
        {
          for (final a in (data['areas'] as List? ?? const []).cast<Map<String, dynamic>>())
            workArea(a['area']): SatisfactionScore.fromJson(a),
        },
      );
}

/// The reports the backend downloads as CSV (US-34).
enum CsvReport { productivity, serviceTimes, satisfaction, reviews }

extension CsvReportX on CsvReport {
  String get label => switch (this) {
        CsvReport.productivity => 'Productividad del personal',
        CsvReport.serviceTimes => 'Tiempos de atención',
        CsvReport.satisfaction => 'Satisfacción por área',
        CsvReport.reviews => 'Evaluaciones con comentarios',
      };

  String get path => switch (this) {
        CsvReport.productivity => '/staff-performance/productivity/export',
        CsvReport.serviceTimes => '/staff-performance/service-times/export',
        CsvReport.satisfaction => '/stay-reviews/satisfaction/export',
        CsvReport.reviews => '/stay-reviews/export',
      };
}

// ---------------------------------------------------------------------------
// Calls and sync
// ---------------------------------------------------------------------------

extension RemoteReports on RemoteHotel {
  /// `hotelId`, `from` and `to` of a report. The backend's end is exclusive: the last second of the period counts.
  String _query(Period period) {
    final to = period.end.add(const Duration(seconds: 1));
    return [
      if (hotelId != null) 'hotelId=$hotelId',
      'from=${Uri.encodeQueryComponent(period.start.toUtc().toIso8601String())}',
      'to=${Uri.encodeQueryComponent(to.toUtc().toIso8601String())}',
    ].join('&');
  }

  /// Copies the Sprint 4 modules into the store. Each one is skipped on a backend that does not have it yet (404).
  Future<void> syncReports() async {
    final role = store.currentUser?.role;
    final admin = role == UserRole.admin;

    // US-33: the catalog of the hotel (a guest: the available services of the hotel of their stay).
    if (role == UserRole.guest || hotelId != null) {
      try {
        final items = (await api.get('/service-catalog') as List).cast<Map<String, dynamic>>();
        store.services
          ..clear()
          ..addAll(items.map(serviceItem));
        hasServiceCatalog = true;
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          hasServiceCatalog = false;
        } else if (e.statusCode == 400 && role == UserRole.guest) {
          // A guest without a stay today has no hotel to browse.
          store.services.clear();
          hasServiceCatalog = true;
        } else {
          rethrow;
        }
      }
    }

    // US-21: the evaluations. The administrator sees those of the hotel; a guest knows which stays they evaluated.
    if (admin) {
      try {
        final reviews = (await api.get('/stay-reviews?${hotelId == null ? '' : 'hotelId=$hotelId&'}limit=200') as List)
            .cast<Map<String, dynamic>>();
        store.ratings
          ..clear()
          ..addAll(reviews.map(stayRating));
        hasStayReviews = true;
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        hasStayReviews = false;
      }
    } else if (role == UserRole.guest) {
      for (final stay in store.stays.where((s) => s.status == StayStatus.checkedOut && !s.rated)) {
        try {
          final review = await api.get('/bookings/${stay.id}/review') as Map<String, dynamic>;
          stay.rated = true;
          store.ratings
            ..removeWhere((r) => r.stayId == stay.id)
            ..add(stayRating(review));
        } on ApiException catch (e) {
          // 404: not evaluated yet (or a backend without evaluations).
          if (e.statusCode != 404) rethrow;
        }
      }
      hasStayReviews = true;
    }

    if (admin && hotelId != null) {
      // US-34: the scheduled deliveries of the staff reports.
      try {
        final schedules = (await api.get('/staff-performance/report-schedules?hotelId=$hotelId') as List)
            .cast<Map<String, dynamic>>();
        store.schedules
          ..clear()
          ..addAll(schedules.map(reportSchedule));
        hasReportSchedules = true;
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        hasReportSchedules = false;
      }

      // US-18: the counters of the panel.
      try {
        dashboard = DashboardSnapshot.fromJson(await api.get('/hotels/$hotelId/dashboard') as Map<String, dynamic>);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        dashboard = null;
      }
    }
  }

  // ── US-21 ──────────────────────────────────────────────────────────────────

  /// The guest evaluates their finished stay: overall (required) and the three areas, 1 to 5.
  Future<void> submitStayReview(int bookingId,
      {required int overall, int? frontDesk, int? housekeeping, int? maintenance, String comment = ''}) async {
    final review = await api.post('/bookings/$bookingId/review', {
      'overallRating': overall,
      'frontDeskRating': ?frontDesk,
      'housekeepingRating': ?housekeeping,
      'maintenanceRating': ?maintenance,
      if (comment.trim().isNotEmpty) 'comment': comment.trim(),
    }) as Map<String, dynamic>;
    store.stays.where((s) => s.id == bookingId).firstOrNull?.rated = true;
    store.ratings
      ..removeWhere((r) => r.stayId == bookingId)
      ..add(stayRating(review));
    store.refresh();
  }

  // ── US-24 / US-25 / US-26 / US-34 ──────────────────────────────────────────

  Future<StaffReport> staffReport(Period period) async =>
      StaffReport.fromJson(await api.get('/staff-performance/productivity?${_query(period)}') as Map<String, dynamic>);

  Future<ServiceTimes> serviceTimes(Period period) async =>
      ServiceTimes.fromJson(await api.get('/staff-performance/service-times?${_query(period)}') as Map<String, dynamic>);

  Future<Satisfaction> satisfaction(Period period) async =>
      Satisfaction.fromJson(await api.get('/stay-reviews/satisfaction?${_query(period)}') as Map<String, dynamic>);

  /// The CSV the backend builds for [report] (UTF-8, comma separated).
  Future<String> exportCsv(CsvReport report, Period period) async {
    final text = await api.getText('${report.path}?${_query(period)}');
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

  // ── US-34: scheduled deliveries ───────────────────────────────────────────

  static ReportSchedule reportSchedule(Map<String, dynamic> data) {
    final monthly = data['frequency'] == 'Monthly' || data['frequency'] == 1;
    final reports = [
      if (data['includeProductivity'] == true) 'Productividad',
      if (data['includeServiceTimes'] == true) 'Tiempos de atención',
    ];
    return ReportSchedule(
      id: _int(data['id']),
      name: 'Reporte ${monthly ? 'mensual' : 'semanal'} del personal',
      kind: reports.join(' y '),
      frequencyDays: monthly ? 30 : 7,
      recipients: [for (final r in (data['recipients'] as List? ?? const [])) r.toString()],
      format: data['isActive'] == false ? 'Pausado' : 'Correo',
      nextSend: _time(data['nextRunAt']) ?? DateTime.now(),
    )..lastSent = _time(data['lastSentAt']);
  }

  /// Weekly (Mondays, the previous 7 days) or monthly (the 1st, the previous month), at 08:00.
  Future<void> createReportSchedule({required bool monthly, required List<String> recipients,
      bool productivity = true, bool serviceTimes = true}) async {
    final data = await api.post('/staff-performance/report-schedules?hotelId=$hotelId', {
      'frequency': monthly ? 'Monthly' : 'Weekly',
      'recipients': recipients,
      'includeProductivity': productivity,
      'includeServiceTimes': serviceTimes,
    }) as Map<String, dynamic>;
    store.schedules.add(reportSchedule(data));
    store.refresh();
  }

  Future<void> deleteReportSchedule(int id) async {
    await api.delete('/staff-performance/report-schedules/$id');
    store.schedules.removeWhere((s) => s.id == id);
    store.refresh();
  }

  /// Sends the reports of the schedule right away (the last week or month until now).
  Future<void> sendReportNow(int id) async {
    final data = await api.post('/staff-performance/report-schedules/$id/send') as Map<String, dynamic>;
    final index = store.schedules.indexWhere((s) => s.id == id);
    if (index >= 0) store.schedules[index] = reportSchedule(data)..lastSent = DateTime.now();
    store.refresh();
  }

  // ── US-33: service catalog ────────────────────────────────────────────────

  static ServiceItem serviceItem(Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? '';
    final area = workArea(data['area']);
    return ServiceItem(
      id: _int(data['id']),
      name: name,
      description: data['description']?.toString() ?? '',
      price: _double(data['price']) ?? 0,
      area: area,
      icon: serviceIcon(name, area),
      available: data['isAvailable'] != false,
      etaMinutes: (data['estimatedMinutes'] as num?)?.toInt(),
    );
  }

  /// An icon for a service of the catalog, from its name (the backend does not keep one).
  static IconData serviceIcon(String name, Area area) {
    final text = name.toLowerCase();
    if (text.contains('toalla')) return Icons.view_agenda_outlined;
    if (text.contains('lavander')) return Icons.local_laundry_service_outlined;
    if (text.contains('amenid')) return Icons.bathtub_outlined;
    if (text.contains('desayun') || text.contains('comida') || text.contains('bebida') || text.contains('cena')) {
      return Icons.restaurant_outlined;
    }
    if (text.contains('salida') || text.contains('check-out')) return Icons.schedule;
    if (text.contains('taxi') || text.contains('transporte')) return Icons.local_taxi_outlined;
    if (text.contains('spa') || text.contains('masaje')) return Icons.spa_outlined;
    return switch (area) {
      Area.housekeeping => Icons.cleaning_services_outlined,
      Area.maintenance => Icons.build_outlined,
      Area.reception => Icons.room_service_outlined,
    };
  }

  /// The guest asks for a service of the catalog: it goes to the area of the service, with its price.
  Future<void> requestCatalogService(ServiceItem service) async {
    if (!service.available) throw const DomainException('Este servicio no está disponible por ahora.');
    final request = await api.post('/guest-requests', {'serviceItemId': service.id}) as Map<String, dynamic>;
    upsertRequest(request);
  }

  /// The administrator adds a service ([existing] null) or changes one.
  Future<void> saveService({ServiceItem? existing, required String name, String description = '', required Area area,
      required double price, int? etaMinutes, bool available = true}) async {
    final body = {
      'name': name.trim(),
      if (description.trim().isNotEmpty) 'description': description.trim(),
      'area': RemoteHotel.backendArea(area),
      'price': price,
      'estimatedMinutes': ?etaMinutes,
      'isAvailable': available,
    };
    final data = existing == null
        ? await api.post('/service-catalog?hotelId=$hotelId', body) as Map<String, dynamic>
        : await api.put('/service-catalog/${existing.id}', body) as Map<String, dynamic>;
    final item = serviceItem(data);
    final index = store.services.indexWhere((s) => s.id == item.id);
    if (index >= 0) {
      store.services[index] = item;
    } else {
      store.services.add(item);
    }
    store.refresh();
  }

  Future<void> deleteService(int id) async {
    await api.delete('/service-catalog/$id');
    store.services.removeWhere((s) => s.id == id);
    store.refresh();
  }
}
