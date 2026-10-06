import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Assisted check-in: pick a free room and confirm (US-27, US-28).
Future<void> showCheckInSheet(BuildContext context, Stay stay, {Room? preselectedRoom}) async {
  final store = HotelStore.instance;
  final document = TextEditingController(text: stay.documentId);
  // A room reserved in advance is proposed first, even if it is not ready yet (US-27, escenario 3).
  Room? selected = preselectedRoom ??
      (stay.roomId != null ? store.roomById(stay.roomId!) : store.assignableRooms(type: stay.roomType).firstOrNull);
  List<Room> alternatives = const [];
  String? warning;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setLocal) {
        final options = {
          ...store.assignableRooms(type: stay.roomType),
          ...alternatives,
          ?selected,
        }.toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Check-in de ${stay.guestName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('Reservó ${stay.roomType.label} · ${stay.nights} noches', style: const TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              TextField(controller: document, decoration: const InputDecoration(labelText: 'Documento de identidad')),
              const SizedBox(height: 12),
              const Text('Habitación', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (options.isEmpty)
                Text('No hay habitaciones listas. Estimado: ${store.estimateReadyMinutes(stay.roomType)} min.',
                    style: const TextStyle(color: kWarning)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final room in options)
                    ChoiceChip(
                      label: Text('${room.number} · ${room.type.label}'),
                      selected: selected?.id == room.id,
                      onSelected: (_) => setLocal(() => selected = room),
                    ),
                ],
              ),
              if (warning != null) ...[
                const SizedBox(height: 10),
                Text(warning!, style: const TextStyle(color: kError, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 16),
              AppButton(
                text: 'Confirmar check-in',
                icon: Icons.key_outlined,
                dark: true,
                onPressed: selected == null
                    ? null
                    : () {
                        try {
                          final done = store.assistedCheckIn(stay.id, selected!.id,
                              receptionistId: store.currentUser!.id, documentId: document.text);
                          Navigator.pop(sheetContext);
                          showAppSnack(context, 'Habitación ${selected!.number} ocupada · código ${done.accessCode}');
                        } on RoomNotReadyException catch (e) {
                          setLocal(() {
                            warning = '${e.message} Te sugerimos una alternativa disponible.';
                            alternatives = e.alternatives;
                            selected = e.alternatives.firstOrNull;
                          });
                        } on DomainException catch (e) {
                          setLocal(() => warning = e.message);
                        }
                      },
              ),
            ],
          ),
        );
      },
    ),
  );
}
