import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Reception registers guest requests and routes them to the right area (US-11).
/// Housekeeping and maintenance see the requests routed to their area.
class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  bool _showResolved = false;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      final isFrontOffice = user.role == UserRole.admin || user.role == UserRole.reception;
      final list = store.requests
          .where((r) => isFrontOffice || r.area == user.role.area)
          .where((r) => _showResolved || r.status != WorkStatus.resolved)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (isFrontOffice) AppButton(text: 'Registrar solicitud', icon: Icons.add, onPressed: () => _create(context, store)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar resueltas'),
            value: _showResolved,
            onChanged: (v) => setState(() => _showResolved = v),
          ),
          if (list.isEmpty) const EmptyState(icon: Icons.room_service_outlined, message: 'No hay solicitudes pendientes.'),
          for (final request in list) RequestCard(request: request, store: store, canRoute: isFrontOffice),
        ],
      );
    });
  }

  Future<void> _create(BuildContext context, HotelStore store) async {
    final occupied = store.inHouse;
    if (occupied.isEmpty) {
      showAppSnack(context, 'No hay huéspedes hospedados.', error: true);
      return;
    }
    var stay = occupied.first;
    var area = Area.housekeeping;
    final description = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nueva solicitud', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              DropdownButtonFormField<Stay>(
                initialValue: stay,
                decoration: const InputDecoration(labelText: 'Huésped'),
                items: [
                  for (final s in occupied)
                    DropdownMenuItem(value: s, child: Text('${s.guestName} · Hab. ${store.roomById(s.roomId!).number}')),
                ],
                onChanged: (v) => setLocal(() => stay = v ?? stay),
              ),
              const SizedBox(height: 12),
              TextField(controller: description, decoration: const InputDecoration(labelText: '¿Qué necesita?')),
              const SizedBox(height: 12),
              const Text('Derivar a', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in Area.values)
                    ChoiceChip(
                      avatar: Icon(a.icon, size: 18),
                      label: Text(a.label),
                      selected: area == a,
                      onSelected: (_) => setLocal(() => area = a),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppButton(text: 'Registrar y derivar', icon: Icons.send, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final remote = store.remote;
    if (remote != null && remote.hasGuestRequests) {
      await runAsync(context, () => remote.createRequest(title: description.text, area: area, roomId: stay.roomId),
          success: 'Solicitud enviada a ${area.label}.');
      return;
    }
    runAction(
      context,
      () => store.createRequest(
        roomId: stay.roomId!,
        stayId: stay.id,
        description: description.text,
        area: area,
        createdById: store.currentUser!.id,
      ),
      success: 'Solicitud enviada a ${area.label}.',
    );
  }
}

class RequestCard extends StatelessWidget {
  final GuestRequest request;
  final HotelStore store;
  final bool canRoute;
  final bool readOnly;

  const RequestCard({super.key, required this.request, required this.store, this.canRoute = false, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final late = request.status != WorkStatus.resolved && store.now.difference(request.createdAt).inMinutes > request.etaMinutes;
    final cloud = store.remote?.hasGuestRequests == true ? store.remote : null;
    final me = store.currentUser!;
    return AppCard(
      borderColor: late ? kWarning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(request.description, style: const TextStyle(fontWeight: FontWeight.w800))),
              Pill(text: request.status.label, color: request.status.color),
            ],
          ),
          InfoRow(Icons.meeting_room_outlined, 'Hab. ${store.roomById(request.roomId).number} · ${request.area.label}'),
          if (request.assigneeId != null) InfoRow(Icons.person_outline, 'A cargo de ${store.userName(request.assigneeId)}'),
          InfoRow(
            Icons.schedule,
            '${timeAgo(request.createdAt, store.now)} · estimado ${request.etaMinutes} min${late ? ' · demorada' : ''}',
            color: late ? kWarning : kMuted,
          ),
          if (!readOnly && request.status != WorkStatus.resolved)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                if (canRoute)
                  PopupMenuButton<Area>(
                    tooltip: 'Derivar',
                    onSelected: (area) => cloud == null
                        ? store.deriveRequest(request.id, area)
                        : runAsync(context, () => cloud.routeRequest(request.id, area), success: 'Solicitud derivada a ${area.label}.'),
                    itemBuilder: (_) => [for (final a in Area.values) PopupMenuItem(value: a, child: Text('Derivar a ${a.label}'))],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(children: [Icon(Icons.alt_route, size: 18), SizedBox(width: 4), Text('Derivar')]),
                    ),
                  ),
                // The admin knows the staff of each area; someone of the area takes an unassigned request.
                if (cloud != null && me.role == UserRole.admin && store.staffOf(request.area.role).isNotEmpty)
                  PopupMenuButton<int>(
                    tooltip: 'Asignar',
                    onSelected: (userId) => runAsync(context, () => cloud.assignRequest(request.id, userId),
                        success: 'Solicitud asignada a ${store.userName(userId)}.'),
                    itemBuilder: (_) => [
                      for (final member in store.staffOf(request.area.role)) PopupMenuItem(value: member.id, child: Text(member.name)),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(children: [Icon(Icons.person_add_alt, size: 18), SizedBox(width: 4), Text('Asignar')]),
                    ),
                  ),
                if (cloud != null && request.assigneeId == null && me.role.area == request.area && me.role != UserRole.admin)
                  TextButton(
                    onPressed: () => runAsync(context, () => cloud.assignRequest(request.id, me.id), success: 'La solicitud quedó a tu cargo.'),
                    child: const Text('Tomar'),
                  ),
                if (canRoute && cloud != null)
                  TextButton(
                    onPressed: () async {
                      final note = await askText(context, title: 'Cancelar solicitud', label: 'Motivo (opcional)');
                      if (note != null && context.mounted) {
                        await runAsync(context, () => cloud.cancelRequest(request.id, note: note), success: 'Solicitud cancelada.');
                      }
                    },
                    child: const Text('Cancelar'),
                  ),
                if (request.status == WorkStatus.pending)
                  TextButton(
                    onPressed: () => cloud == null
                        ? store.updateRequestStatus(request.id, WorkStatus.inProgress)
                        : runAsync(context, () => cloud.startRequest(request.id), success: 'Solicitud en proceso: el huésped ya lo ve.'),
                    child: const Text('En proceso'),
                  ),
                FilledButton(
                  onPressed: () => cloud == null
                      ? store.updateRequestStatus(request.id, WorkStatus.resolved)
                      : runAsync(context, () => cloud.resolveRequest(request.id), success: 'Solicitud atendida: avisamos al huésped.'),
                  child: const Text('Resuelta'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
