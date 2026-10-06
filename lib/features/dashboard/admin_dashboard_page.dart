import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../incidents/incident_detail_page.dart';
import '../shell/role_shell.dart';

/// Key indicators of the day, refreshed live (US-18).
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final alerts = store.activeAlerts;
      final criticalIncidents = store.openIncidents.where((i) => i.urgency == Priority.urgent).toList();
      final recentRatings = store.ratings.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final occupied = store.rooms.where((r) => r.status == RoomStatus.occupied).length;

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
                value: '${(store.occupancyRate * 100).round()}%',
                detail: '$occupied de ${store.rooms.length} habitaciones',
                icon: Icons.hotel_outlined,
                color: kPrimary,
                onTap: () => openFeature(context, Feature.roomsBoard),
              ),
              _Kpi(
                label: 'Por limpiar',
                value: '${store.pendingCleaning}',
                detail: '${store.openTasks.length} tareas abiertas',
                icon: Icons.cleaning_services_outlined,
                color: kWarning,
                onTap: () => openFeature(context, Feature.assignCleaning),
              ),
              _Kpi(
                label: 'Incidencias abiertas',
                value: '${store.openIncidents.length}',
                detail: '${criticalIncidents.length} urgentes',
                icon: Icons.report_problem_outlined,
                color: kError,
                onTap: () => openFeature(context, Feature.incidents),
              ),
              _Kpi(
                label: 'Tareas atrasadas',
                value: '${store.overdueTasks.length}',
                detail: 'más de ${store.overdueTaskLimit.inMinutes} min',
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
                _MiniStat('Llegadas', store.arrivalsToday.length),
                _MiniStat('Hospedados', store.inHouse.length),
                _MiniStat('Solicitudes', store.requests.where((r) => r.status != WorkStatus.resolved).length),
              ],
            ),
          ),
          const SectionHeader(title: 'Últimas evaluaciones'),
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
