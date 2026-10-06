import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';
import '../front_desk/check_in_sheet.dart';

/// Only clean, free rooms without open incidents can be assigned (US-28).
class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage({super.key});

  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  RoomType? _type;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final available = store.assignableRooms(type: _type);
      final blocked = store.rooms.where((r) => !store.isAssignable(r) && (_type == null || r.type == _type)).toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Todas'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
              for (final type in RoomType.values)
                ChoiceChip(label: Text(type.label), selected: _type == type, onSelected: (_) => setState(() => _type = type)),
            ],
          ),
          SectionHeader(title: 'Disponibles para asignar', subtitle: '${available.length} limpias y sin ocupar'),
          if (available.isEmpty)
            EmptyState(
              icon: Icons.hourglass_bottom,
              message: 'No hay habitaciones listas. Próxima en ~${store.estimateReadyMinutes(_type ?? RoomType.standard)} min.',
            ),
          for (final room in available)
            AppCard(
              child: Row(
                children: [
                  Text(room.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${room.type.label} · Piso ${room.floor} · \$${room.type.nightlyRate.toStringAsFixed(0)} / noche')),
                  // With the backend each booking already has its room and the guest checks in from the app.
                  if (!store.isRemote) FilledButton(onPressed: () => _assign(context, store, room), child: const Text('Asignar')),
                ],
              ),
            ),
          const SectionHeader(title: 'No asignables'),
          for (final room in blocked)
            AppCard(
              child: Row(
                children: [
                  Text(room.number, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kMuted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(store.hasBlockingIncident(room.id) ? 'Incidencia abierta' : room.status.label,
                        style: const TextStyle(color: kMuted)),
                  ),
                  Icon(room.status.icon, color: room.status.color),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _assign(BuildContext context, HotelStore store, Room room) async {
    final candidates = store.arrivalsToday;
    if (candidates.isEmpty) {
      showAppSnack(context, 'No hay llegadas pendientes. Crea una reserva desde Recepción.', error: true);
      return;
    }
    final stay = await showModalBottomSheet<Stay>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('¿A quién asignas la ${room.number}?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          for (final stay in candidates)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(stay.guestName),
              subtitle: Text('Reservó ${stay.roomType.label}'),
              onTap: () => Navigator.pop(sheetContext, stay),
            ),
        ],
      ),
    );
    if (stay == null || !context.mounted) return;
    await showCheckInSheet(context, stay, preselectedRoom: room);
  }
}
