import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// End-of-shift summary for the next colleague, with read confirmation (US-32).
class HandoverPage extends StatefulWidget {
  const HandoverPage({super.key});

  @override
  State<HandoverPage> createState() => _HandoverPageState();
}

class _HandoverPageState extends State<HandoverPage> {
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      final area = user.role.area;
      final history = store.handovers.where((h) => area == null || h.area == area).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Terminar mi turno', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const Text('Las tareas e incidencias abiertas de tu área se adjuntan solas.', style: TextStyle(color: kMuted)),
                const SizedBox(height: 10),
                TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(hintText: 'Pendientes, avisos o detalles importantes')),
                const SizedBox(height: 10),
                AppButton(
                  text: 'Registrar entrega de turno',
                  icon: Icons.swap_horiz,
                  onPressed: () {
                    final ok = runAction(context, () => store.createHandover(user, _notes.text), success: 'Entrega registrada para el siguiente turno.');
                    if (ok) _notes.clear();
                  },
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Entregas recientes'),
          if (history.isEmpty) const EmptyState(message: 'Aún no hay entregas de turno.'),
          for (final handover in history) HandoverCard(handover: handover),
        ],
      );
    });
  }
}

class HandoverCard extends StatelessWidget {
  final Handover handover;

  const HandoverCard({super.key, required this.handover});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final me = store.currentUser!;
      final read = handover.readBy.containsKey(me.id);
      final isMine = handover.authorId == me.id;
      return AppCard(
        borderColor: !read && !isMine ? kPrimary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${store.userName(handover.authorId)} · ${handover.area.label}', style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(fmtDateTime(handover.createdAt), style: const TextStyle(color: kMuted, fontSize: 12)),
            if (handover.notes.isNotEmpty) ...[const SizedBox(height: 8), Text(handover.notes)],
            if (handover.openItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in handover.openItems) InfoRow(Icons.radio_button_unchecked, item),
            ],
            const SizedBox(height: 8),
            for (final entry in handover.readBy.entries)
              InfoRow(Icons.done_all, 'Leído por ${store.userName(entry.key)} · ${fmtDateTime(entry.value)}', color: kSuccess),
            if (!read && !isMine)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Marcar como leído'),
                  onPressed: () => store.markHandoverRead(handover.id, me.id),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Shown at the top of a staff member's panel when the previous shift left a summary.
class HandoverBanner extends StatelessWidget {
  final AppUser user;

  const HandoverBanner({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final handover = store.latestHandoverFor(user);
      if (handover == null || handover.readBy.containsKey(user.id)) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resumen del turno anterior', style: TextStyle(fontWeight: FontWeight.w900, color: kPrimaryDark)),
            HandoverCard(handover: handover),
          ],
        ),
      );
    });
  }
}
