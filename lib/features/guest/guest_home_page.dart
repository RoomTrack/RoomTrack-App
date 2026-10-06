import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../requests/requests_page.dart';
import 'services_page.dart';

/// Guest landing tab: where the stay stands and how the requests are going (US-19).
class GuestHomePage extends StatelessWidget {
  const GuestHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final stay = store.activeStayOf(store.currentUser!.id);
      final requests = stay == null ? const <GuestRequest>[] : store.requestsForStay(stay.id);
      final room = stay?.roomId == null ? null : store.roomById(stay!.roomId!);
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (stay != null)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  const Icon(Icons.key_outlined, color: kGold, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room == null ? '${stay.roomType.label} · ${stay.status.label}' : '${stay.roomType.label} ${room.number}',
                          style: const TextStyle(fontFamily: kSerif, color: Colors.white, fontSize: 20),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stay.status == StayStatus.checkedIn
                              ? 'Check-out ${relativeDay(stay.checkOut, store.now)} · ${fmtHour12(stay.checkOut)}'
                              : '${fmtDayMonth(stay.checkIn)} – ${fmtDayMonth(stay.checkOut)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('Tus solicitudes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: () => showCreateRequestSheet(context, store),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
              ),
            ],
          ),
          if (requests.isEmpty)
            const EmptyState(icon: Icons.room_service_outlined, message: 'Cuando pidas algo, verás aquí si está pendiente, en proceso o resuelto.'),
          for (final request in requests) RequestCard(request: request, store: store, readOnly: true),
        ],
      );
    });
  }
}
