import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Any staff member reports damage; maintenance is notified at once (US-08).
class ReportIncidentPage extends StatefulWidget {
  final int? initialRoomId;

  /// True when pushed as its own route instead of living in a tab.
  final bool standalone;

  const ReportIncidentPage({super.key, this.initialRoomId, this.standalone = false});

  @override
  State<ReportIncidentPage> createState() => _ReportIncidentPageState();
}

class _ReportIncidentPageState extends State<ReportIncidentPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  late int _roomId = widget.initialRoomId ?? HotelStore.instance.rooms.first.id;
  String _category = HotelStore.incidentCategories.first;
  Priority _urgency = Priority.normal;
  bool _blocksRoom = true;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final store = HotelStore.instance;
    final ok = runAction(
      context,
      () => store.createIncident(
        roomId: _roomId,
        title: _title.text,
        description: _description.text,
        category: _category,
        urgency: _urgency,
        reporterId: store.currentUser!.id,
        blocksRoom: _blocksRoom,
      ),
      success: 'Incidencia registrada como pendiente. Mantenimiento ya fue notificado.',
    );
    if (!ok) return;
    if (widget.standalone) {
      Navigator.pop(context);
    } else {
      setState(() {
        _title.clear();
        _description.clear();
        _urgency = Priority.normal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HotelStore.instance;
    final form = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          initialValue: _roomId,
          decoration: const InputDecoration(labelText: 'Habitación', prefixIcon: Icon(Icons.meeting_room_outlined)),
          items: [
            for (final room in store.rooms) DropdownMenuItem(value: room.id, child: Text('${room.number} · ${room.type.label}')),
          ],
          onChanged: (value) => setState(() => _roomId = value ?? _roomId),
        ),
        const SizedBox(height: 12),
        TextField(controller: _title, decoration: const InputDecoration(labelText: '¿Qué ocurre?', hintText: 'Ej. Ducha sin agua caliente')),
        const SizedBox(height: 12),
        TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Detalle (opcional)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [for (final c in HotelStore.incidentCategories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
        const SizedBox(height: 16),
        const Text('Urgencia', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final p in Priority.values)
              ChoiceChip(
                label: Text(p.label),
                selected: _urgency == p,
                selectedColor: p.color.withAlpha(50),
                onSelected: (_) => setState(() => _urgency = p),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bloquear la habitación'),
          subtitle: const Text('No se podrá asignar a huéspedes hasta resolverla.'),
          value: _blocksRoom,
          onChanged: (value) => setState(() => _blocksRoom = value),
        ),
        const SizedBox(height: 8),
        AppButton(text: 'Registrar incidencia', icon: Icons.send, dark: true, onPressed: _submit),
      ],
    );
    if (!widget.standalone) return form;
    return Scaffold(appBar: AppBar(title: const Text('Reportar incidencia', style: TextStyle(fontWeight: FontWeight.w900))), body: form);
  }
}
