import 'package:flutter/material.dart';

import '../../core/backend/remote_reports.dart';
import '../../core/permissions.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../incidents/incident_detail_page.dart';
import '../requests/requests_page.dart';
import '../shell/role_shell.dart';

/// Key indicators of the day, refreshed live (US-18). With the backend they are the ones it calculates for the hotel
/// (`GET /hotels/{id}/dashboard`, refreshed on every sync); in the demo the app calculates them.
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final remote = store.remote?.dashboard;
      final alerts = remote == null ? store.activeAlerts : const <OperationalAlert>[];
      final criticalIncidents =
          remote == null ? store.openIncidents.where((i) => i.urgency == Priority.urgent).toList() : const <Incident>[];
      final recentRatings = remote?.frontDesk?.latestReviews ??
          (store.ratings.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
      final occupied = remote?.roomsOccupied ?? store.rooms.where((r) => r.status == RoomStatus.occupied).length;
      final totalRooms = remote?.roomsTotal ?? store.rooms.length;
      final occupancy = remote == null ? (store.occupancyRate * 100).round() : remote.occupancyPercent.round();

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (remote != null && remote.attention.isNotEmpty) ...[
            const SectionHeader(title: 'Requiere atención', subtitle: 'Lo crítico aparece primero.'),
            for (final item in remote.attention) _AttentionCard(item),
          ],
          if (alerts.isNotEmpty || criticalIncidents.isNotEmpty) ...[
            const SectionHeader(title: 'Requiere atención', subtitle: 'Lo crítico aparece primero.'),
            for (final alert in alerts.take(4))
              AppCard(
                borderColor: kError,
                onTap: () => openFeature(context, Feature.alerts),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: kError),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(alert.detail, style: const TextStyle(color: kMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            for (final incident in criticalIncidents.where((i) => !alerts.any((a) => a.key == 'incident-${i.id}')))
              AppCard(
                borderColor: kWarning,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IncidentDetailPage(incidentId: incident.id))),
                child: Row(
                  children: [
                    const Icon(Icons.build_circle_outlined, color: kWarning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Hab. ${store.roomById(incident.roomId).number}: ${incident.title}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Text(timeAgo(incident.createdAt, store.now), style: const TextStyle(color: kMuted)),
                  ],
                ),
              ),
          ],
          const SectionHeader(title: 'Operación de hoy'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              _Kpi(
                label: 'Ocupación',
                value: '$occupancy%',
                detail: '$occupied de $totalRooms habitaciones',
                icon: Icons.hotel_outlined,
                color: kPrimary,
                onTap: () => openFeature(context, Feature.roomsBoard),
              ),
              _Kpi(
                label: 'Por limpiar',
                value: '${remote?.roomsCleaning ?? store.pendingCleaning}',
                detail: '${remote?.cleaningOpen ?? store.openTasks.length} tareas abiertas',
                icon: Icons.cleaning_services_outlined,
                color: kWarning,
                onTap: () => openFeature(context, Feature.assignCleaning),
              ),
              _Kpi(
                label: 'Incidencias abiertas',
                value: '${remote?.incidentsOpen ?? store.openIncidents.length}',
                detail: remote == null
                    ? '${criticalIncidents.length} urgentes'
                    : '${remote.incidentsCritical} críticas · ${remote.incidentsEscalated} escaladas',
                icon: Icons.report_problem_outlined,
                color: kError,
                onTap: () => openFeature(context, Feature.incidents),
              ),
              _Kpi(
                label: 'Tareas atrasadas',
                value: '${remote?.cleaningOverdue ?? store.overdueTasks.length}',
                detail: 'más de ${remote?.overdueAfterMinutes ?? store.overdueTaskLimit.inMinutes} min',
                icon: Icons.timer_outlined,
                color: const Color(0xFF8E6CC9),
                onTap: () => openFeature(context, Feature.assignCleaning),
              ),
            ],
          ),
          const SectionHeader(title: 'Recepción'),
          AppCard(
            onTap: () => openFeature(context, Feature.frontDesk),
            child: Row(
              children: [
                _MiniStat('Llegadas', remote?.frontDesk?.arrivals ?? store.arrivalsToday.length),
                _MiniStat('Hospedados', remote?.frontDesk?.inHouse ?? store.inHouse.length),
                if (remote?.frontDesk != null) _MiniStat('Salidas', remote!.frontDesk!.departures),
                _MiniStat('Solicitudes', remote?.requestsOpen ?? store.requests.where((r) => r.status != WorkStatus.resolved).length),
              ],
            ),
          ),
          if (remote != null && remote.frontDesk == null)
            const InfoRow(Icons.cloud_off_outlined, 'Las reservas no respondieron: llegadas y salidas se muestran sin actualizar.',
                color: kWarning),
          if (remote != null && remote.requestsLate > 0)
            InfoRow(Icons.timer_off_outlined, '${remote.requestsLate} solicitudes pasaron el tiempo prometido al huésped.',
                color: kWarning),
          SectionHeader(
            title: 'Últimas evaluaciones',
            subtitle: switch (remote?.frontDesk) {
              final FrontDeskSnapshot f? when f.averageLast30Days != null =>
                'Promedio ${f.averageLast30Days!.toStringAsFixed(1)} ★ en ${f.reviewsLast30Days} evaluaciones (30 días)',
              _ => '',
            },
          ),
          if (recentRatings.isEmpty) const EmptyState(message: 'Aún no hay evaluaciones.'),
          for (final rating in recentRatings.take(3))
            AppCard(
              onTap: () => openFeature(context, Feature.analytics),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (rating.overall case final int overall)
                        Pill(text: 'General $overall★', color: overall >= 4 ? kSuccess : kWarning),
                      for (final entry in rating.scores.entries)
                        Pill(text: '${entry.key.label} ${entry.value}★', color: entry.value >= 4 ? kSuccess : kWarning),
                    ],
                  ),
                  if (rating.comment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('"${rating.comment}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 4),
                  Text(fmtDateTime(rating.createdAt), style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// An escalated or critical incident, or a late request, as the backend lists them (US-18).
class _AttentionCard extends StatelessWidget {
  final AttentionEntry item;

  const _AttentionCard(this.item);

  @override
  Widget build(BuildContext context) {
    final color = item.reason == 'Late' ? kWarning : kError;
    return AppCard(
      borderColor: color,
      onTap: () => item.isIncident
          ? Navigator.push(context, MaterialPageRoute(builder: (_) => IncidentDetailPage(incidentId: item.referenceId)))
          : Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestsPage())),
      child: Row(
        children: [
          Icon(item.isIncident ? Icons.build_circle_outlined : Icons.room_service_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${item.roomNumber == null ? '' : 'Hab. ${item.roomNumber}: '}${item.title}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Pill(text: item.reasonLabel, color: color),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _Kpi({required this.label, required this.value, required this.detail, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700))),
            ],
          ),
          Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color)),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;

  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}
