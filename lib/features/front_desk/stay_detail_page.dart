import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../payments/folio_card.dart';
import '../payments/payment_sheet.dart';
import 'check_in_sheet.dart';
import 'register_payment_sheet.dart';

/// Reception's view of a stay: folio, collection and assisted check-out (US-16, US-17, US-27).
class StayDetailPage extends StatelessWidget {
  final int stayId;

  const StayDetailPage({super.key, required this.stayId});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final stay = store.stayById(stayId);
      final room = stay.roomId == null ? null : store.roomById(stay.roomId!);
      final balance = store.balanceOf(stay);
      final receipts = store.receipts.where((r) => r.stayId == stay.id).toList();
      final remote = store.isRemote;
      return Scaffold(
        appBar: AppBar(title: Text(stay.guestName, style: const TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(text: stay.status.label, color: kPrimary),
                      if (stay.code != null) Pill(text: stay.code!, color: kGold),
                      if (stay.awaitingPayment) const Pill(text: 'Pago pendiente', color: kWarning),
                    ],
                  ),
                  if (stay.paymentDueAt != null && stay.awaitingPayment)
                    InfoRow(Icons.timer_outlined, 'Debe pagarse antes del ${fmtDateTime(stay.paymentDueAt!)}', color: kWarning),
                  InfoRow(Icons.mail_outline, stay.guestEmail),
                  InfoRow(Icons.meeting_room_outlined, room == null ? 'Sin habitación (${stay.roomType.label})' : 'Habitación ${room.number}'),
                  InfoRow(Icons.date_range, '${fmtDate(stay.checkIn)} → ${fmtDate(stay.checkOut)} · ${stay.nights} noches'),
                  if (stay.accessCode != null && stay.isActive) InfoRow(Icons.key_outlined, 'Código de acceso ${stay.accessCode}'),
                  if (stay.fiscalData != null) InfoRow(Icons.business_outlined, 'Factura a ${stay.fiscalData!.businessName} (${stay.fiscalData!.ruc})'),
                ],
              ),
            ),
            FolioCard(stay: stay, store: store),
            const SizedBox(height: 8),
            if (remote) ..._remoteActions(context, stay)
            else ...[
            if (stay.status == StayStatus.reserved || stay.status == StayStatus.checkInInProgress)
              AppButton(text: 'Hacer check-in', icon: Icons.key_outlined, dark: true, onPressed: () => showCheckInSheet(context, stay)),
            if (stay.isActive && balance > 0) ...[
              const SizedBox(height: 10),
              AppButton(
                text: 'Cobrar saldo ${money(balance)}',
                icon: Icons.point_of_sale,
                onPressed: () async {
                  final paid = await showPaymentSheet(
                    context,
                    title: 'Cobro en recepción',
                    amount: balance,
                    allowSplit: true,
                    allowCash: true,
                    onPay: (parts) => store.payBalance(stay.id, parts),
                  );
                  if (paid && context.mounted) showAppSnack(context, 'Pago registrado. Folio saldado.');
                },
              ),
            ],
            if (stay.status == StayStatus.checkedIn) ...[
              const SizedBox(height: 10),
              AppButton(
                text: 'Registrar check-out',
                icon: Icons.logout,
                dark: true,
                onPressed: () async {
                  final ok = await confirm(context, 'Check-out', 'La habitación pasará a pendiente de limpieza y se devolverá el depósito.');
                  if (!ok || !context.mounted) return;
                  runAction(context, () => store.checkOut(stay.id, receptionistId: store.currentUser!.id),
                      success: 'Check-out registrado. Comprobante enviado a ${stay.guestEmail}.');
                },
              ),
            ],
            if (stay.isActive) ...[
              const SizedBox(height: 10),
              AppButton(text: 'Datos para factura', icon: Icons.business_outlined, outlined: true, onPressed: () => editFiscalData(context, store, stay)),
            ],
            ],
            if (receipts.isNotEmpty) ...[
              const SectionHeader(title: 'Comprobantes'),
              for (final receipt in receipts)
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${receipt.type} ${receipt.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${money(receipt.amount)} · enviado ${receipt.sentCount} ${receipt.sentCount == 1 ? 'vez' : 'veces'}',
                                style: const TextStyle(color: kMuted)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          store.resendReceipt(receipt.id);
                          showAppSnack(context, 'Comprobante reenviado a ${receipt.email}.');
                        },
                        child: const Text('Reenviar'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
    });
  }

  /// What the backend lets the front desk do with a booking today.
  List<Widget> _remoteActions(BuildContext context, Stay stay) => [
        if (stay.awaitingPayment)
          AppButton(text: 'Registrar pago', icon: Icons.point_of_sale, dark: true, onPressed: () => showRegisterPaymentSheet(context, stay)),
        if (stay.status == StayStatus.reserved && !stay.awaitingPayment)
          const InfoRow(Icons.phone_iphone, 'Reserva pagada: el huésped completa su check-in digital desde la app.', color: kSuccess),
        if (stay.status == StayStatus.checkedIn)
          const InfoRow(Icons.info_outline, 'El check-out y los cargos adicionales llegan con la siguiente fase del backend.'),
      ];
}
