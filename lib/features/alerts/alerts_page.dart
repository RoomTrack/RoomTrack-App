import 'package:flutter/material.dart';

import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Automatic delay alerts and their history (US-23).
class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final active = store.activeAlerts;
      final history = store.alerts.where((a) => a.resolved).toList()
        ..sort((a, b) => (b.resolvedAt ?? b.createdAt).compareTo(a.resolvedAt ?? a.createdAt));
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: 'Activas',
            subtitle: 'Incidencias críticas, limpiezas atrasadas y llegadas sin habitación lista.',
            trailing: IconButton(tooltip: 'Revisar ahora', onPressed: store.runChecks, icon: const Icon(Icons.refresh)),
          ),
          if (active.isEmpty) const EmptyState(icon: Icons.verified_outlined, message: 'Sin alertas activas.'),
          for (final alert in active)
            AppCard(
              borderColor: kError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(alert.detail),
                  const SizedBox(height: 4),
                  Text(timeAgo(alert.createdAt, store.now), style: const TextStyle(color: kMuted, fontSize: 12)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Marcar atendida'),
                      onPressed: () async {
                        final note = await askText(context, title: 'Resolución', label: '¿Qué se hizo?');
                        if (note != null) store.resolveAlert(alert.id, note);
                      },
                    ),
                  ),
                ],
              ),
            ),
          const SectionHeader(title: 'Historial'),
          if (history.isEmpty) const EmptyState(message: 'Todavía no hay alertas resueltas.'),
          for (final alert in history)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(alert.detail, style: const TextStyle(color: kMuted)),
                  const SizedBox(height: 6),
                  InfoRow(Icons.check_circle_outline, '${alert.resolution} · ${fmtDateTime(alert.resolvedAt ?? alert.createdAt)}', color: kSuccess),
                ],
              ),
            ),
        ],
      );
    });
  }
}
