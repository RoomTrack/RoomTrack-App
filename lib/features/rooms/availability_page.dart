import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
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
          if (store.isRemote) const _DateSearch(),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Todas'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
              for (final type in RoomType.values)
                ChoiceChip(label: Text(type.label), selected: _type == type, onSelected: (_) => setState(() => _type = type)),
            ],
          ),
          SectionHeader(title: store.isRemote ? 'Listas ahora' : 'Disponibles para asignar', subtitle: '${available.length} limpias y sin ocupar'),
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
                  Expanded(child: Text('${room.typeLabel} · Piso ${room.floor} · ${money(room.price ?? room.type.nightlyRate)} / noche')),
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

/// Rooms free for a stay, from the backend (US-28), and a booking for them at the desk (US-27).
class _DateSearch extends StatefulWidget {
  const _DateSearch();

  @override
  State<_DateSearch> createState() => _DateSearchState();
}

class _DateSearchState extends State<_DateSearch> {
  final _remote = HotelStore.instance.remote!;
  late DateTime _from = DateUtils.dateOnly(HotelStore.instance.now);
  late DateTime _to = _from.add(const Duration(days: 1));
  Future<List<AvailableRoom>>? _results;

  void _search() => setState(() => _results = _remote.availableRooms(_from, _to));

  Future<void> _pick() async {
    final today = DateUtils.dateOnly(HotelStore.instance.now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Llegada y salida',
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.start;
      _to = range.end.isAfter(range.start) ? range.end : range.start.add(const Duration(days: 1));
    });
    _search();
  }

  Future<void> _book(AvailableRoom room) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reservar la ${room.number}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${fmtDate(_from)} → ${fmtDate(_to)} · ${money(room.total)}', style: const TextStyle(color: kMuted)),
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del huésped')),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reservar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAsync(
      context,
      () => _remote.createBooking(
          roomId: room.id, checkIn: _from, nights: _to.difference(_from).inDays, guestName: name.text, guestEmail: email.text),
      success: 'Reserva creada con pago pendiente. Registra el pago para confirmarla.',
    );
    if (done) _search();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Buscar por fechas', subtitle: 'Habitaciones libres toda la estadía.'),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.date_range),
          label: Text('${fmtDate(_from)} → ${fmtDate(_to)} · ${_to.difference(_from).inDays} noches'),
        ),
        if (_results == null)
          TextButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Buscar'))
        else
          FutureBuilder(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
              final rooms = snapshot.data;
              if (rooms == null) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
              if (rooms.isEmpty) return const EmptyState(icon: Icons.event_busy_outlined, message: 'No hay habitaciones libres en esas fechas.');
              return Column(
                children: [
                  for (final room in rooms)
                    AppCard(
                      child: Row(
                        children: [
                          Text(room.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(room.typeName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('${money(room.pricePerNight)} / noche · total ${money(room.total)}', style: const TextStyle(color: kMuted)),
                              ],
                            ),
                          ),
                          FilledButton(onPressed: () => _book(room), child: const Text('Reservar')),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
