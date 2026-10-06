import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../rooms/room_detail_page.dart';

/// Follow-up of an incident until it is resolved (US-09).
class IncidentDetailPage extends StatelessWidget {
  final int incidentId;

  const IncidentDetailPage({super.key, required this.incidentId});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final incident = store.incidentById(incidentId);
      final room = store.roomById(incident.roomId);
      final user = store.currentUser!;
      final canWork = incident.isOpen && (incident.assigneeId == user.id || user.role == UserRole.admin);
      return Scaffold(
        appBar: AppBar(title: Text('Hab. ${room.number}', style: const TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(incident.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  if (incident.description.isNotEmpty) ...[const SizedBox(height: 6), Text(incident.description)],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(text: incident.status.label, color: incident.status.color),
                      PriorityPill(incident.urgency),
                      Pill(text: incident.category, color: kMuted),
                      if (incident.recurring) const Pill(text: 'Problema recurrente', color: kError, icon: Icons.repeat),
                      if (incident.escalated) const Pill(text: 'Escalada al administrador', color: kError),
                    ],
                  ),
                  InfoRow(Icons.person_outline, 'Reportó: ${store.userName(incident.reportedById)}'),
                  InfoRow(Icons.engineering_outlined, 'Responsable: ${store.userName(incident.assigneeId)}'),
                  InfoRow(Icons.schedule, 'Reportada ${fmtDateTime(incident.createdAt)}'),
                  if (incident.resolutionNotes.isNotEmpty) InfoRow(Icons.notes, 'Observaciones: ${incident.resolutionNotes}', color: kSuccess),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (canWork && incident.status == WorkStatus.pending)
              AppButton(text: 'Marcar en proceso', icon: Icons.play_arrow, onPressed: () => store.startIncident(incident.id)),
            if (canWork && incident.status == WorkStatus.inProgress)
              AppButton(
                text: 'Marcar como resuelta',
                icon: Icons.check_circle_outline,
                dark: true,
                onPressed: () async {
                  final notes = await askText(context, title: 'Cerrar incidencia', label: 'Observaciones de la solución', maxLines: 3);
                  if (notes == null || !context.mounted) return;
                  runAction(context, () => store.resolveIncident(incident.id, notes),
                      success: 'Incidencia resuelta. La habitación quedó disponible para limpieza.');
                },
              ),
            if (user.role == UserRole.admin && incident.isOpen) ...[
              const SizedBox(height: 10),
              AppButton(
                text: 'Reasignar técnico',
                icon: Icons.person_search_outlined,
                outlined: true,
                onPressed: () async {
                  final id = await showModalBottomSheet<int>(
                    context: context,
                    builder: (sheetContext) => ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tech in store.staffOf(UserRole.maintenance))
                          ListTile(
                            leading: UserAvatar(tech),
                            title: Text(tech.name),
                            subtitle: Text('${store.openLoad(tech.id)} pendientes'),
                            onTap: () => Navigator.pop(sheetContext, tech.id),
                          ),
                      ],
                    ),
                  );
                  if (id != null) store.assignIncident(incident.id, id);
                },
              ),
            ],
            const SizedBox(height: 10),
            AppButton(
              text: 'Ver historial de la habitación',
              icon: Icons.history,
              outlined: true,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoomDetailPage(roomId: room.id))),
            ),
            const SectionHeader(title: 'Seguimiento'),
            for (final event in incident.events.reversed)
              ListTile(
                dense: true,
                leading: const Icon(Icons.timeline, size: 18),
                title: Text(event.text),
                subtitle: Text(fmtDateTime(event.at)),
              ),
          ],
        ),
      );
    });
  }
}
