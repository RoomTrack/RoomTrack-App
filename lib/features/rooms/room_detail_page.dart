import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../core/permissions.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../incidents/incident_detail_page.dart';
import '../incidents/report_incident_page.dart';
import 'room_climate_card.dart';

/// Room status, current guest and incident history (US-04, US-10, US-30).
class RoomDetailPage extends StatelessWidget {
  final int roomId;

  const RoomDetailPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final room = store.roomById(roomId);
      final stay = store.stayInRoom(room.id);
      final task = store.tasks.where((t) => t.roomId == room.id && t.isOpen).firstOrNull;
      final history = store.roomHistory(room.id);
      final role = store.currentUser!.role;
      final recurring = store.roomHasRecurringPattern(room.id) || history.any((i) => i.isOpen && i.recurring);

      return Scaffold(
        appBar: AppBar(title: Text('Habitación ${room.number}', style: const TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pill(text: room.status.label, color: room.status.color, icon: room.status.icon),
                      Text('${room.typeLabel} · Piso ${room.floor}${room.price == null ? '' : ' · ${money(room.price!)} / noche'}',
                          style: const TextStyle(color: kMuted)),
                    ],
                  ),
                  if (stay != null) InfoRow(Icons.person_outline, '${stay.guestName} · sale ${fmtDate(stay.checkOut)}'),
                  if (task != null)
                    InfoRow(Icons.cleaning_services_outlined,
                        'Limpieza ${task.status.label.toLowerCase()} · ${store.userName(task.assigneeId)} · ${task.priority.label}'),
                  if (store.hasBlockingIncident(room.id))
                    const InfoRow(Icons.block, 'Bloqueada para asignación por incidencia abierta', color: kError),
                  if (room.maintenanceOverdue)
                    const InfoRow(Icons.timer_off_outlined, 'Lleva en mantenimiento más tiempo del permitido.', color: kError),
                ],
              ),
            ),
            if (canAccess(role, Feature.assignCleaning)) ...[
              const SectionHeader(title: 'Cambiar estado'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // The backend's room map says where each room can go from its current status.
                  for (final status in RoomStatus.values.where((s) => s == room.status || (room.allowedNext?.contains(s) ?? true)))
                    ChoiceChip(
                      label: Text(status.label),
                      selected: room.status == status,
                      onSelected: (_) => store.remote == null
                          ? store.setRoomStatus(room, status)
                          : runAsync(context, () => store.remote!.changeRoomStatus(room, status),
                              success: 'Estado actualizado para todo el hotel.'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (task == null && stay == null)
                AppButton(
                  text: 'Crear tarea de limpieza',
                  icon: Icons.cleaning_services_outlined,
                  outlined: true,
                  onPressed: () => store.cleaningBackend == null
                      ? runAction(context, () => store.createCleaningTask(room.id), success: 'Tarea creada y asignada.')
                      : runAsync(context, () => store.cleaningBackend!.createCleaningTask(room.id), success: 'Tarea de limpieza creada.'),
                ),
            ],
            const SizedBox(height: 10),
            AppButton(
              text: 'Reportar incidencia',
              icon: Icons.add_alert_outlined,
              outlined: true,
              onPressed: () => openPage(context, Feature.reportIncident, ReportIncidentPage(initialRoomId: room.id, standalone: true)),
            ),
            if (store.remote != null) ...[
              _StatusHistory(roomId: room.id),
              if (role == UserRole.admin || role == UserRole.maintenance) RoomClimateCard(roomId: room.id),
              _RoomBookings(roomId: room.id),
              _MaintenanceSummary(roomId: room.id),
            ],
            SectionHeader(title: 'Historial de mantenimiento', subtitle: '${history.length} registros (correctivos y preventivos)'),
            if (recurring)
              AppCard(
                borderColor: kError,
                child: InfoRow(Icons.repeat, 'Patrón recurrente: más de ${store.recurrenceThreshold} incidencias similares en el último mes.',
                    color: kError),
              ),
            if (history.isEmpty) const EmptyState(message: 'Sin incidencias registradas.'),
            for (final incident in history) IncidentTile(incident: incident, store: store),
          ],
        ),
      );
    });
  }
}

class IncidentTile extends StatelessWidget {
  final Incident incident;
  final HotelStore store;
  final bool showRoom;

  const IncidentTile({super.key, required this.incident, required this.store, this.showRoom = false});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: incident.isOpen && incident.urgency == Priority.urgent ? kError : null,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IncidentDetailPage(incidentId: incident.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${showRoom ? 'Hab. ${store.roomById(incident.roomId).number} · ' : ''}${incident.title}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Pill(text: incident.status.label, color: incident.status.color),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PriorityPill(incident.urgency),
              if (incident.category.isNotEmpty) Pill(text: incident.category, color: kMuted),
              if (incident.preventive) const Pill(text: 'Preventivo', color: kSuccess, icon: Icons.event_repeat),
              if (incident.recurring) const Pill(text: 'Recurrente', color: kError, icon: Icons.repeat),
              if (incident.escalated) const Pill(text: 'Escalada', color: kError, icon: Icons.trending_up),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${fmtDateTime(incident.createdAt)} · '
            '${incident.assigneeId == null ? 'Sin asignar' : store.userById(incident.assigneeId)?.name ?? 'Asignada'}',
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Who changed the status of the room and when, from the backend (US-04).
class _StatusHistory extends StatefulWidget {
  final int roomId;

  const _StatusHistory({required this.roomId});

  @override
  State<_StatusHistory> createState() => _StatusHistoryState();
}

class _StatusHistoryState extends State<_StatusHistory> {
  late Future<List<({DateTime at, String from, String to, String by})>> _history =
      HotelStore.instance.remote!.roomStatusHistory(widget.roomId);

  @override
  void didUpdateWidget(covariant _StatusHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The store notifies after every change: reload so the new line shows up.
    _history = HotelStore.instance.remote!.roomStatusHistory(widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Cambios de estado'),
        FutureBuilder(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
            final items = snapshot.data;
            if (items == null) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
            if (items.isEmpty) return const EmptyState(message: 'Sin cambios registrados.');
            return AppCard(
              child: Column(
                children: [
                  for (final item in items.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.swap_horiz, color: kGold),
                      title: Text('${item.from} → ${item.to}'),
                      subtitle: Text('${fmtDateTime(item.at)} · ${item.by}'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Bookings of the room, next ones first (backend).
class _RoomBookings extends StatefulWidget {
  final int roomId;

  const _RoomBookings({required this.roomId});

  @override
  State<_RoomBookings> createState() => _RoomBookingsState();
}

class _RoomBookingsState extends State<_RoomBookings> {
  late final Future<List<RoomBooking>> _bookings = HotelStore.instance.remote!.roomBookings(widget.roomId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _bookings,
      builder: (context, snapshot) {
        final today = DateUtils.dateOnly(HotelStore.instance.now);
        final items = snapshot.data
            ?.where((b) => !b.checkOut.isBefore(today) && b.status != 'Cancelled' && b.status != 'Expired')
            .toList()
            .reversed
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Reservas', subtitle: 'Actuales y próximas.'),
            if (snapshot.hasError) Text('${snapshot.error}', style: const TextStyle(color: kError))
            else if (items == null) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
            else if (items.isEmpty) const EmptyState(icon: Icons.event_available_outlined, message: 'Sin reservas próximas.')
            else
              AppCard(
                child: Column(
                  children: [
                    for (final booking in items.take(8))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined, color: kGold),
                        title: Text(booking.guestName),
                        subtitle: Text('${fmtDate(booking.checkIn)} → ${fmtDate(booking.checkOut)} · ${booking.code}'),
                        trailing: Text(booking.statusLabel, style: const TextStyle(color: kMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Corrective, preventive and recurring work of the room and its preventive plans, as the backend counts them.
class _MaintenanceSummary extends StatefulWidget {
  final int roomId;

  const _MaintenanceSummary({required this.roomId});

  @override
  State<_MaintenanceSummary> createState() => _MaintenanceSummaryState();
}

class _MaintenanceSummaryState extends State<_MaintenanceSummary> {
  late final Future<RoomMaintenanceSummary?> _summary =
      HotelStore.instance.remote!.maintenanceSummary(widget.roomId).then<RoomMaintenanceSummary?>((s) => s).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _summary,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Resumen de mantenimiento'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(text: '${summary.corrective} correctivos', color: kPrimary),
                      Pill(text: '${summary.preventive} preventivos', color: kSuccess),
                      if (summary.recurring > 0) Pill(text: '${summary.recurring} recurrentes', color: kError, icon: Icons.repeat),
                    ],
                  ),
                  for (final plan in summary.plans.where((p) => p.active))
                    InfoRow(Icons.event_repeat, '${plan.title} · cada ${plan.frequencyDays} días · próximo ${fmtDate(plan.nextDue)}'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
