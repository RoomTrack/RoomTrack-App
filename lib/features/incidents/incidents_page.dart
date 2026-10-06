import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/ui.dart';
import '../handover/handover_page.dart';
import '../rooms/room_detail_page.dart';

/// Maintenance sees its own queue by urgency and date (US-09); the admin sees everything.
class IncidentsPage extends StatefulWidget {
  final bool onlyMine;

  const IncidentsPage({super.key, this.onlyMine = false});

  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  WorkStatus? _status;
  bool _onlyCritical = false;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      var list = widget.onlyMine
          ? store.incidentsFor(user.id)
          : (store.incidents.toList()
            ..sort((a, b) {
              final open = (b.isOpen ? 1 : 0).compareTo(a.isOpen ? 1 : 0);
              if (open != 0) return open;
              final urgency = b.urgency.index.compareTo(a.urgency.index);
              return urgency != 0 ? urgency : b.createdAt.compareTo(a.createdAt);
            }));
      if (_status != null) list = list.where((i) => i.status == _status).toList();
      if (_onlyCritical) list = list.where((i) => i.urgency.isCritical).toList();

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.onlyMine) HandoverBanner(user: user),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (!widget.onlyMine) ...[
                ChoiceChip(label: const Text('Todas'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                for (final status in WorkStatus.values)
                  ChoiceChip(label: Text(status.label), selected: _status == status, onSelected: (_) => setState(() => _status = status)),
              ],
              FilterChip(label: const Text('Urgencia alta'), selected: _onlyCritical, onSelected: (v) => setState(() => _onlyCritical = v)),
            ],
          ),
          const SizedBox(height: 8),
          if (list.isEmpty) const EmptyState(icon: Icons.handyman_outlined, message: 'No hay incidencias para mostrar.'),
          for (final incident in list.take(60)) IncidentTile(incident: incident, store: store, showRoom: true),
        ],
      );
    });
  }
}
