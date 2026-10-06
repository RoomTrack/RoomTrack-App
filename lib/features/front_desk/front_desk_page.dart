import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import 'check_in_sheet.dart';
import 'register_payment_sheet.dart';
import 'stay_detail_page.dart';

/// Arrivals, guests in house and departures handled at the desk (US-27).
class FrontDeskPage extends StatelessWidget {
  const FrontDeskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final arrivals = store.arrivalsToday;
      final inHouse = store.inHouse..sort((a, b) => a.checkOut.compareTo(b.checkOut));
      final upcoming = store.upcoming;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(text: 'Nueva reserva / huésped sin reserva', icon: Icons.person_add_alt, onPressed: () => _newReservation(context, store)),
          SectionHeader(title: 'Llegadas de hoy', subtitle: '${arrivals.length} pendientes de check-in'),
          if (arrivals.isEmpty) const EmptyState(message: 'No hay llegadas pendientes.'),
          for (final stay in arrivals)
            _StayCard(
              stay: stay,
              store: store,
              action: _arrivalAction(context, store, stay),
            ),
          SectionHeader(title: 'Hospedados', subtitle: '${inHouse.length} habitaciones ocupadas'),
          for (final stay in inHouse)
            _StayCard(
              stay: stay,
              store: store,
              // The backend has no check-out yet: the stay detail explains it.
              action: OutlinedButton.icon(
                icon: Icon(store.isRemote ? Icons.receipt_long_outlined : Icons.logout, size: 18),
                label: Text(store.isRemote ? 'Detalle' : 'Check-out'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StayDetailPage(stayId: stay.id))),
              ),
            ),
          if (upcoming.isNotEmpty) ...[
            const SectionHeader(title: 'Próximas reservas'),
            for (final stay in upcoming) _StayCard(stay: stay, store: store),
          ],
        ],
      );
    });
  }

  Widget? _arrivalAction(BuildContext context, HotelStore store, Stay stay) {
    if (!store.isRemote) {
      return FilledButton.icon(
        icon: const Icon(Icons.key_outlined, size: 18),
        label: const Text('Check-in'),
        onPressed: () => showCheckInSheet(context, stay),
      );
    }
    // With the backend the guest checks in from their app once the booking is paid.
    if (!stay.awaitingPayment) return null;
    return FilledButton.icon(
      icon: const Icon(Icons.point_of_sale, size: 18),
      label: const Text('Pago'),
      onPressed: () => showRegisterPaymentSheet(context, stay),
    );
  }

  Future<void> _newReservation(BuildContext context, HotelStore store) async {
    final name = TextEditingController();
    final email = TextEditingController();
    var type = RoomType.standard;
    var nights = 1;
    Room? room;
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
              const Text('Nueva reserva para hoy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del huésped')),
              const SizedBox(height: 8),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in RoomType.values)
                    ChoiceChip(
                      label: Text('${t.label} · ${money(t.nightlyRate)}'),
                      selected: type == t,
                      onSelected: (_) => setLocal(() {
                        type = t;
                        room = null;
                      }),
                    ),
                ],
              ),
              // The backend books a concrete room; it checks that it is free for the dates.
              if (store.isRemote) ...[
                const SizedBox(height: 8),
                const Text('Habitación', style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in store.rooms.where((r) => r.type == type && r.status != RoomStatus.maintenance))
                      ChoiceChip(label: Text(r.number), selected: room?.id == r.id, onSelected: (_) => setLocal(() => room = r)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Noches', style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(onPressed: nights > 1 ? () => setLocal(() => nights--) : null, icon: const Icon(Icons.remove)),
                  Text('$nights', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  IconButton(onPressed: () => setLocal(() => nights++), icon: const Icon(Icons.add)),
                ],
              ),
              const SizedBox(height: 12),
              AppButton(text: 'Crear reserva', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final remote = store.remote;
    if (remote != null) {
      final chosen = room;
      if (chosen == null) {
        showAppSnack(context, 'Elige la habitación.', error: true);
        return;
      }
      await runAsync(
        context,
        () => remote.createBooking(roomId: chosen.id, checkIn: store.now, nights: nights, guestName: name.text, guestEmail: email.text),
        success: 'Reserva creada con pago pendiente. Registra el pago para confirmarla.',
      );
      return;
    }
    runAction(
      context,
      () => store.createReservation(guestName: name.text, guestEmail: email.text, type: type, nights: nights),
      success: 'Reserva creada. Ya aparece en llegadas de hoy.',
    );
  }
}

class _StayCard extends StatelessWidget {
  final Stay stay;
  final HotelStore store;
  final Widget? action;

  const _StayCard({required this.stay, required this.store, this.action});

  @override
  Widget build(BuildContext context) {
    final room = stay.roomId == null ? null : store.roomById(stay.roomId!);
    final balance = store.balanceOf(stay);
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StayDetailPage(stayId: stay.id))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stay.guestName, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(
                  '${room == null ? stay.roomType.label : 'Hab. ${room.number}'} · ${fmtDate(stay.checkIn)} → ${fmtDate(stay.checkOut)}',
                  style: const TextStyle(color: kMuted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(text: stay.status.label, color: kPrimary),
                    if (stay.digital) const Pill(text: 'Check-in digital', color: kSuccess, icon: Icons.phone_iphone),
                    if (stay.awaitingPayment) const Pill(text: 'Pago pendiente', color: kWarning, icon: Icons.hourglass_bottom),
                    if (store.isRemote && !stay.awaitingPayment && stay.status == StayStatus.reserved)
                      const Pill(text: 'Pagada · check-in en su app', color: kSuccess),
                    if (balance > 0) Pill(text: 'Saldo ${money(balance)}', color: kWarning),
                  ],
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
