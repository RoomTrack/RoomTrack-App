import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Recurring preventive maintenance with reminders (US-30).
class PreventivePage extends StatelessWidget {
  const PreventivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final plans = store.preventiveTasks.toList()..sort((a, b) => a.nextDue.compareTo(b.nextDue));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(text: 'Programar tarea preventiva', icon: Icons.add, onPressed: () => _create(context, store)),
          const SectionHeader(title: 'Programadas', subtitle: 'Se generan automáticamente en cada ciclo.'),
          if (plans.isEmpty) const EmptyState(message: 'No hay tareas preventivas.'),
          for (final plan in plans)
            AppCard(
              borderColor: plan.nextDue.difference(store.now).inDays < 2 ? kWarning : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  InfoRow(Icons.meeting_room_outlined, 'Habitación ${store.roomById(plan.roomId).number}'),
                  InfoRow(Icons.event_repeat, 'Cada ${plan.frequencyDays} días'),
                  InfoRow(Icons.event, 'Próxima: ${fmtDateTime(plan.nextDue)}',
                      color: plan.nextDue.difference(store.now).inDays < 2 ? kWarning : kMuted),
                  if (plan.generated.isNotEmpty) InfoRow(Icons.history, '${plan.generated.length} veces generada'),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _create(BuildContext context, HotelStore store) async {
    final title = TextEditingController();
    var roomId = store.rooms.first.id;
    var frequency = 30;
    var firstDue = store.now.add(const Duration(days: 7));
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
              const Text('Nueva tarea preventiva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Tarea', hintText: 'Ej. Limpieza de filtros')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: roomId,
                decoration: const InputDecoration(labelText: 'Habitación'),
                items: [for (final r in store.rooms) DropdownMenuItem(value: r.id, child: Text(r.number))],
                onChanged: (v) => setLocal(() => roomId = v ?? roomId),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in [7, 15, 30, 90, 180])
                    ChoiceChip(label: Text('$days días'), selected: frequency == days, onSelected: (_) => setLocal(() => frequency = days)),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Primera fecha: ${fmtDate(firstDue)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: firstDue,
                    firstDate: store.now,
                    lastDate: store.now.add(const Duration(days: 365)),
                  );
                  if (picked != null) setLocal(() => firstDue = DateTime(picked.year, picked.month, picked.day, 9));
                },
              ),
              const SizedBox(height: 12),
              AppButton(text: 'Guardar', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    runAction(
      context,
      () => store.schedulePreventive(title: title.text, roomId: roomId, frequencyDays: frequency, firstDue: firstDue),
      success: 'Tarea preventiva programada.',
    );
  }
}
