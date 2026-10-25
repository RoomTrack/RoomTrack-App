import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../rooms/room_detail_page.dart';

/// Follow-up of an incident until it is resolved (US-09).
class IncidentDetailPage extends StatefulWidget {
  final int incidentId;

  const IncidentDetailPage({super.key, required this.incidentId});

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  @override
  void initState() {
    super.initState();
    // The list does not bring the history: it is loaded with the incident.
    HotelStore.instance.remote?.refreshIncident(widget.incidentId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final incident = store.incidents.where((i) => i.id == widget.incidentId).firstOrNull;
      if (incident == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Esta incidencia ya no está disponible.', style: TextStyle(color: kMuted))),
        );
      }
      final room = store.roomById(incident.roomId);
      final user = store.currentUser!;
      final remote = store.remote;
      final isAdmin = user.role == UserRole.admin;
      final canWork = incident.isOpen && (incident.assigneeId == user.id || isAdmin);
      // In the backend, maintenance takes an unassigned incident by starting it.
      final canTake = remote != null && user.role == UserRole.maintenance && incident.assigneeId == null &&
          incident.status == WorkStatus.pending;
      final reporter = store.userById(incident.reportedById)?.name ?? incident.reportedByEmail ?? 'Personal del hotel';
      final assignee = incident.assigneeId == null
          ? 'Sin asignar'
          : store.userById(incident.assigneeId)?.name ?? 'Otro técnico de mantenimiento';
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
                      if (incident.category.isNotEmpty) Pill(text: incident.category, color: kMuted),
                      if (incident.blocksRoom && incident.isOpen) const Pill(text: 'Bloquea la habitación', color: kWarning),
                      if (incident.recurring) const Pill(text: 'Problema recurrente', color: kError, icon: Icons.repeat),
                      if (incident.escalated) const Pill(text: 'Escalada al administrador', color: kError),
                    ],
                  ),
                  InfoRow(Icons.person_outline, 'Reportó: $reporter'),
                  InfoRow(Icons.engineering_outlined, 'Responsable: $assignee'),
                  InfoRow(Icons.schedule, 'Reportada ${fmtDateTime(incident.createdAt)}'),
                  if (incident.resolutionNotes.isNotEmpty) InfoRow(Icons.notes, 'Observaciones: ${incident.resolutionNotes}', color: kSuccess),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (canTake)
              AppButton(
                text: 'Tomar y empezar',
                icon: Icons.play_arrow,
                onPressed: () => runAsync(context, () => remote.startIncident(incident.id), success: 'Incidencia tomada: quedó en proceso.'),
              )
            // The backend only starts an assigned incident: an admin assigns it first.
            else if (canWork && incident.status == WorkStatus.pending && (remote == null || incident.assigneeId != null))
              AppButton(
                text: 'Marcar en proceso',
                icon: Icons.play_arrow,
                onPressed: () => remote == null
                    ? store.startIncident(incident.id)
                    : runAsync(context, () => remote.startIncident(incident.id), success: 'Incidencia en proceso.'),
              ),
            if (canWork && incident.status == WorkStatus.inProgress)
              AppButton(
                text: 'Marcar como resuelta',
                icon: Icons.check_circle_outline,
                dark: true,
                onPressed: () async {
                  final notes = await askText(context, title: 'Cerrar incidencia', label: 'Observaciones de la solución', maxLines: 3);
                  if (notes == null || !context.mounted) return;
                  const success = 'Incidencia resuelta. La habitación quedó disponible para limpieza.';
                  if (remote == null) {
                    runAction(context, () => store.resolveIncident(incident.id, notes), success: success);
                  } else {
                    await runAsync(context, () => remote.resolveIncident(incident.id, notes), success: success);
                  }
                },
              ),
            if (remote != null && canWork) ...[
              const SizedBox(height: 10),
              AppButton(
                text: 'Cambiar prioridad',
                icon: Icons.low_priority,
                outlined: true,
                onPressed: () async {
                  final urgency = await showModalBottomSheet<Priority>(
                    context: context,
                    builder: (sheetContext) => ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('Prioridad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        for (final p in Priority.values)
                          ListTile(
                            title: Text(p.label),
                            trailing: p == incident.urgency ? const Icon(Icons.check, color: kSuccess) : null,
                            onTap: () => Navigator.pop(sheetContext, p),
                          ),
                      ],
                    ),
                  );
                  if (urgency == null || urgency == incident.urgency || !context.mounted) return;
                  await runAsync(context, () => remote.changeIncidentPriority(incident.id, urgency),
                      success: 'Prioridad cambiada a ${urgency.label.toLowerCase()}.');
                },
              ),
            ],
            if (isAdmin && incident.isOpen) ...[
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
                  if (id == null || !context.mounted) return;
                  if (remote == null) {
                    store.assignIncident(incident.id, id);
                  } else {
                    await runAsync(context, () => remote.assignIncident(incident.id, id), success: 'Incidencia asignada a ${store.userName(id)}.');
                  }
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
