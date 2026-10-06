import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Reports e-mailed automatically on a schedule (US-34).
class ReportSchedulesPage extends StatelessWidget {
  const ReportSchedulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final sent = store.outbox.where((m) => store.schedules.any((s) => m.subject.startsWith(s.name))).toList().reversed;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(text: 'Programar reporte', icon: Icons.add, onPressed: () => _create(context, store)),
          const SectionHeader(title: 'Programados'),
          if (store.schedules.isEmpty) const EmptyState(message: 'No hay envíos programados.'),
          for (final s in store.schedules)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w900))),
                      IconButton(tooltip: 'Eliminar', onPressed: () => store.deleteSchedule(s.id), icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
                  InfoRow(Icons.category_outlined, '${s.kind} · ${s.format}'),
                  InfoRow(Icons.event_repeat, 'Cada ${s.frequencyDays} días · próximo ${fmtDateTime(s.nextSend)}'),
                  InfoRow(Icons.group_outlined, s.recipients.join(', ')),
                  if (s.lastSent != null) InfoRow(Icons.done_all, 'Último envío ${fmtDateTime(s.lastSent!)}', color: kSuccess),
                ],
              ),
            ),
          if (sent.isNotEmpty) ...[
            const SectionHeader(title: 'Enviados'),
            for (final mail in sent.take(10))
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: Text(mail.subject),
                subtitle: Text('${mail.to} · ${fmtDateTime(mail.createdAt)}'),
              ),
          ],
        ],
      );
    });
  }

  Future<void> _create(BuildContext context, HotelStore store) async {
    final name = TextEditingController();
    final recipients = TextEditingController(text: store.currentUser!.email);
    var kind = 'Operativo';
    var frequency = 7;
    var format = 'PDF';
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
              const Text('Nuevo envío programado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del reporte')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final k in ['Operativo', 'Financiero'])
                  ChoiceChip(label: Text(k), selected: kind == k, onSelected: (_) => setLocal(() => kind = k)),
              ]),
              Wrap(spacing: 8, children: [
                for (final entry in {1: 'Diario', 7: 'Semanal', 30: 'Mensual'}.entries)
                  ChoiceChip(label: Text(entry.value), selected: frequency == entry.key, onSelected: (_) => setLocal(() => frequency = entry.key)),
              ]),
              Wrap(spacing: 8, children: [
                for (final f in ['PDF', 'Excel'])
                  ChoiceChip(label: Text(f), selected: format == f, onSelected: (_) => setLocal(() => format = f)),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: recipients,
                decoration: const InputDecoration(labelText: 'Destinatarios', helperText: 'Separa los correos con comas'),
              ),
              const SizedBox(height: 14),
              AppButton(text: 'Guardar', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    runAction(
      context,
      () => store.scheduleReport(
        name: name.text,
        kind: kind,
        frequencyDays: frequency,
        recipients: recipients.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        format: format,
      ),
      success: 'Reporte programado.',
    );
  }
}
