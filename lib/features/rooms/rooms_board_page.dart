import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/ui.dart';
import 'room_detail_page.dart';

/// Every room grouped by status, filterable by floor (US-04).
class RoomsBoardPage extends StatefulWidget {
  const RoomsBoardPage({super.key});

  @override
  State<RoomsBoardPage> createState() => _RoomsBoardPageState();
}

class _RoomsBoardPageState extends State<RoomsBoardPage> {
  int? _floor;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final rooms = store.rooms.where((r) => _floor == null || r.floor == _floor).toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Todos los pisos'), selected: _floor == null, onSelected: (_) => setState(() => _floor = null)),
              for (final floor in store.floors)
                ChoiceChip(label: Text('Piso $floor'), selected: _floor == floor, onSelected: (_) => setState(() => _floor = floor)),
            ],
          ),
          for (final status in RoomStatus.values) ...[
            if (rooms.any((r) => r.status == status)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Row(
                  children: [
                    Icon(status.icon, color: status.color, size: 20),
                    const SizedBox(width: 8),
                    Flexible(child: Text(status.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    const SizedBox(width: 8),
                    Pill(text: '${rooms.where((r) => r.status == status).length}', color: status.color),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final room in rooms.where((r) => r.status == status))
                    RoomTile(
                      room: room,
                      warning: store.hasBlockingIncident(room.id),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoomDetailPage(roomId: room.id))),
                    ),
                ],
              ),
            ],
          ],
        ],
      );
    });
  }
}

class RoomTile extends StatelessWidget {
  final Room room;
  final bool warning;
  final VoidCallback onTap;

  const RoomTile({super.key, required this.room, required this.onTap, this.warning = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: room.status.color.withAlpha(22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: room.status.color.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(room.number, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                if (warning) const Icon(Icons.build_circle, size: 16, color: kError),
              ],
            ),
            Text(room.type.label, style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
