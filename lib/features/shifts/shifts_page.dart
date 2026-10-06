import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Shift planning with coverage gaps and swaps (US-31). Staff see their own schedule.
class ShiftsPage extends StatefulWidget {
  const ShiftsPage({super.key});

  @override
  State<ShiftsPage> createState() => _ShiftsPageState();
}

class _ShiftsPageState extends State<ShiftsPage> {
  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      final isAdmin = user.role == UserRole.admin;
      final days = (store.shifts.map((s) => s.date).toSet().toList()..sort());
      final pendingSwaps = store.swaps.where((s) => s.approved == null).toList();
      final mine = store.shiftsOf(user.id);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!isAdmin) ...[
            const SectionHeader(title: 'Mis turnos'),
            if (mine.isEmpty) const EmptyState(message: 'No tienes turnos asignados.'),
            for (final shift in mine)
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_dayLabel(store, shift.date)} · ${shift.label} · ${shift.hours}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    TextButton(onPressed: () => _requestSwap(context, store, shift), child: const Text('Pedir cambio')),
                  ],
                ),
              ),
          ],
          if (isAdmin) ...[
            AppButton(text: 'Crear turno', icon: Icons.add, onPressed: () => _create(context, store)),
            if (pendingSwaps.isNotEmpty) ...[
              const SectionHeader(title: 'Solicitudes de cambio'),
              for (final swap in pendingSwaps)
                AppCard(
                  borderColor: kPrimary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${store.userName(swap.requesterId)} ↔ ${store.userName(swap.targetUserId)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(_swapDetail(store, swap), style: const TextStyle(color: kMuted)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => store.decideSwap(swap.id, false), child: const Text('Rechazar')),
                          FilledButton(onPressed: () => store.decideSwap(swap.id, true), child: const Text('Aprobar')),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SectionHeader(title: 'Planificación', subtitle: 'Los huecos de cobertura se resaltan en rojo.'),
          for (final day in days) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(_dayLabel(store, day), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            for (final shift in store.shifts.where((s) => s.date == day))
              AppCard(
                borderColor: shift.hasCoverageGap ? kError : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(shift.area.icon, size: 18, color: kPrimaryDark),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${shift.area.label} · ${shift.label} (${shift.hours})', style: const TextStyle(fontWeight: FontWeight.w800))),
                        if (shift.hasCoverageGap) Pill(text: 'Faltan ${shift.minStaff - shift.staffIds.length}', color: kError),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final member in store.staffOf(shift.area.role))
                          isAdmin
                              ? FilterChip(
                                  label: Text(member.firstName),
                                  selected: shift.staffIds.contains(member.id),
                                  onSelected: (_) => store.toggleShiftMember(shift.id, member.id),
                                )
                              : shift.staffIds.contains(member.id)
                                  ? Chip(label: Text(member.firstName))
                                  : const SizedBox.shrink(),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
    });
  }

  String _dayLabel(HotelStore store, DateTime day) {
    final today = DateUtils.dateOnly(store.now);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Mañana';
    return fmtDate(day);
  }

  String _swapDetail(HotelStore store, ShiftSwap swap) {
    final from = store.shifts.firstWhere((s) => s.id == swap.fromShiftId);
    final to = store.shifts.firstWhere((s) => s.id == swap.toShiftId);
    return '${_dayLabel(store, from.date)} ${from.label} por ${_dayLabel(store, to.date)} ${to.label}';
  }

  Future<void> _requestSwap(BuildContext context, HotelStore store, Shift mine) async {
    final user = store.currentUser!;
    final options = store.shifts
        .where((s) => s.area == mine.area && s.id != mine.id && !s.staffIds.contains(user.id) && s.staffIds.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      showAppSnack(context, 'No hay turnos de compañeros para intercambiar.', error: true);
      return;
    }
    final choice = await showModalBottomSheet<({Shift shift, int userId})>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Cambiar con', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          for (final shift in options)
            for (final id in shift.staffIds)
              ListTile(
                title: Text(store.userName(id)),
                subtitle: Text('${_dayLabel(store, shift.date)} · ${shift.label} · ${shift.hours}'),
                onTap: () => Navigator.pop(sheetContext, (shift: shift, userId: id)),
              ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    runAction(
      context,
      () => store.requestSwap(requesterId: user.id, fromShiftId: mine.id, targetUserId: choice.userId, toShiftId: choice.shift.id),
      success: 'Solicitud enviada al administrador.',
    );
  }

  Future<void> _create(BuildContext context, HotelStore store) async {
    var area = Area.housekeeping;
    var label = 'Mañana';
    var dayOffset = 0;
    var minStaff = 1;
    final selected = <int>{};
    const hours = {'Mañana': (7, 15), 'Tarde': (15, 23), 'Noche': (23, 7)};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nuevo turno', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final a in Area.values)
                  ChoiceChip(label: Text(a.label), selected: area == a, onSelected: (_) => setLocal(() {
                        area = a;
                        selected.clear();
                      })),
              ]),
              Wrap(spacing: 8, children: [
                for (final l in hours.keys) ChoiceChip(label: Text(l), selected: label == l, onSelected: (_) => setLocal(() => label = l)),
              ]),
              Wrap(spacing: 8, children: [
                for (final d in [0, 1, 2, 3, 4, 5, 6])
                  ChoiceChip(
                    label: Text(_dayLabel(store, DateUtils.dateOnly(store.now).add(Duration(days: d)))),
                    selected: dayOffset == d,
                    onSelected: (_) => setLocal(() => dayOffset = d),
                  ),
              ]),
              Row(
                children: [
                  const Text('Personal mínimo', style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(onPressed: minStaff > 1 ? () => setLocal(() => minStaff--) : null, icon: const Icon(Icons.remove)),
                  Text('$minStaff'),
                  IconButton(onPressed: () => setLocal(() => minStaff++), icon: const Icon(Icons.add)),
                ],
              ),
              Wrap(spacing: 6, children: [
                for (final member in store.staffOf(area.role))
                  FilterChip(
                    label: Text(member.firstName),
                    selected: selected.contains(member.id),
                    onSelected: (v) => setLocal(() => v ? selected.add(member.id) : selected.remove(member.id)),
                  ),
              ]),
              const SizedBox(height: 12),
              AppButton(text: 'Crear', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    store.createShift(
      date: DateUtils.dateOnly(store.now).add(Duration(days: dayOffset)),
      area: area,
      label: label,
      startHour: hours[label]!.$1,
      endHour: hours[label]!.$2,
      minStaff: minStaff,
      staffIds: selected.toList(),
    );
  }
}
