import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/backend/remote_reports.dart';
import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Reports e-mailed automatically on a schedule (US-34). With the backend it sends them itself: the staff productivity
/// and the attention times, every Monday or every 1st of the month at 08:00.
class ReportSchedulesPage extends StatelessWidget {
  const ReportSchedulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final remote = store.remote?.hasReportSchedules == true ? store.remote : null;
      final sent = store.outbox.where((m) => store.schedules.any((s) => m.subject.startsWith(s.name))).toList().reversed;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(
            text: 'Programar reporte',
            icon: Icons.add,
            onPressed: () => remote == null ? _create(context, store) : _createRemote(context, store, remote),
          ),
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
                      if (remote != null)
                        IconButton(
                          tooltip: 'Enviar ahora',
                          onPressed: () => runAsync(context, () => remote.sendReportNow(s.id), success: 'Reporte enviado a ${s.recipients.join(', ')}.'),
                          icon: const Icon(Icons.send_outlined),
                        ),
                      IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => remote == null ? store.deleteSchedule(s.id) : runAsync(context, () => remote.deleteReportSchedule(s.id)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  InfoRow(Icons.category_outlined, '${s.kind} · ${s.format}'),
                  InfoRow(
                    Icons.event_repeat,
                    remote == null
                        ? 'Cada ${s.frequencyDays} días · próximo ${fmtDateTime(s.nextSend)}'
                        : '${s.frequencyDays == 7 ? 'Cada lunes' : 'Cada día 1 del mes'} · próximo ${fmtDateTime(s.nextSend)}',
                  ),
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

  /// US-34 with the backend: weekly or monthly, the reports to include and up to 10 recipients.
  Future<void> _createRemote(BuildContext context, HotelStore store, RemoteHotel remote) async {
    final recipients = TextEditingController(text: store.currentUser!.email);
    var monthly = false;
    var productivity = true;
    var serviceTimes = true;
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
              const SizedBox(height: 4),
              const Text('El servidor lo envía por correo a las 08:00 con el período que terminó.', style: TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Semanal (lunes)'), selected: !monthly, onSelected: (_) => setLocal(() => monthly = false)),
                ChoiceChip(label: const Text('Mensual (día 1)'), selected: monthly, onSelected: (_) => setLocal(() => monthly = true)),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: productivity,
                onChanged: (value) => setLocal(() => productivity = value ?? false),
                title: const Text('Productividad del personal'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: serviceTimes,
                onChanged: (value) => setLocal(() => serviceTimes = value ?? false),
                title: const Text('Tiempos de atención'),
              ),
              TextField(
                controller: recipients,
                decoration: const InputDecoration(labelText: 'Destinatarios', helperText: 'Hasta 10 correos, separados con comas'),
              ),
              const SizedBox(height: 14),
              AppButton(text: 'Guardar', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    await runAsync(
      context,
      () => remote.createReportSchedule(
        monthly: monthly,
        recipients: recipients.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        productivity: productivity,
        serviceTimes: serviceTimes,
      ),
      success: 'Reporte programado.',
    );
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
