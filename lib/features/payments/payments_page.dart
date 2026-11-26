import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../front_desk/stay_detail_page.dart';
import 'payment_settings_page.dart';

/// Charges, refunds and receipts by date, with resend (US-17).
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  PaymentKind? _kind;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final list = store.payments.where((p) => _kind == null || p.kind == _kind).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final income = list
          .where((p) => p.status == PaymentStatus.approved && p.kind != PaymentKind.deposit)
          .fold(0.0, (sum, p) => sum + p.amount);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (store.currentUser?.role == UserRole.admin && store.remote?.hotelId != null) ...[
            AppButton(
              text: 'Medios de pago del hotel',
              icon: Icons.account_balance_wallet_outlined,
              outlined: true,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentSettingsPage())),
            ),
            const SizedBox(height: 10),
          ],
          if (store.isRemote) const _HotelHistory() else ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(label: const Text('Todos'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
              for (final kind in PaymentKind.values)
                ChoiceChip(label: Text(kind.label), selected: _kind == kind, onSelected: (_) => setState(() => _kind = kind)),
            ],
          ),
          SectionHeader(title: '${list.length} movimientos', subtitle: 'Cobrado: ${money(income)}'),
          for (final payment in list.take(80))
            Builder(builder: (context) {
              final stay = store.stayById(payment.stayId);
              final receipt = payment.receiptId == null ? null : store.receipts.where((r) => r.id == payment.receiptId).firstOrNull;
              final color = switch (payment.status) {
                PaymentStatus.approved => kSuccess,
                PaymentStatus.rejected => kError,
                PaymentStatus.refunded => kPrimary,
              };
              return AppCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StayDetailPage(stayId: stay.id))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(stay.guestName, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(money(payment.amount), style: TextStyle(fontWeight: FontWeight.w900, color: color)),
                      ],
                    ),
                    Text('${payment.kind.label} · ${payment.method}', style: const TextStyle(color: kMuted)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Pill(text: payment.status.label, color: color),
                        const SizedBox(width: 8),
                        Text(fmtDateTime(payment.createdAt), style: const TextStyle(color: kMuted, fontSize: 12)),
                        const Spacer(),
                        if (receipt != null)
                          TextButton.icon(
                            icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                            label: Text(receipt.number),
                            onPressed: () {
                              store.resendReceipt(receipt.id);
                              showAppSnack(context, '${receipt.type} reenviada a ${receipt.email}.');
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      );
    });
  }
}

/// The hotel's money movements as the backend records them (US-17): booking and folio payments, refunds, deposits
/// and receipts, for the chosen period.
class _HotelHistory extends StatefulWidget {
  const _HotelHistory();

  @override
  State<_HotelHistory> createState() => _HotelHistoryState();
}

class _HotelHistoryState extends State<_HotelHistory> {
  final _remote = HotelStore.instance.remote!;
  int _days = 30;
  late Future<List<PaymentHistoryEntry>> _entries = _load();

  Future<List<PaymentHistoryEntry>> _load() {
    final now = HotelStore.instance.now;
    return _remote.paymentHistory(from: now.subtract(Duration(days: _days)), to: now);
  }

  @override
  Widget build(BuildContext context) {
    final store = HotelStore.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final days in const [7, 30, 90])
              ChoiceChip(
                label: Text('$days días'),
                selected: _days == days,
                onSelected: (_) => setState(() {
                  _days = days;
                  _entries = _load();
                }),
              ),
          ],
        ),
        FutureBuilder(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
            final entries = snapshot.data;
            if (entries == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            final income = entries.where((e) => e.type == 'BookingPayment' || e.type == 'FolioPayment').fold(0.0, (sum, e) => sum + e.amount);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: '${entries.length} movimientos', subtitle: 'Cobrado: ${money(income)}'),
                if (entries.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, message: 'Sin movimientos en el periodo.'),
                for (final entry in entries.take(150))
                  Builder(builder: (context) {
                    final stay = store.stays.where((s) => s.id == entry.bookingId).firstOrNull;
                    final color = entry.amount < 0 ? kPrimary : (entry.type == 'Receipt' ? kMuted : kSuccess);
                    return AppCard(
                      onTap: stay == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => StayDetailPage(stayId: stay.id))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(stay?.guestName ?? 'Reserva ${entry.bookingId}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              Text(money(entry.amount), style: TextStyle(fontWeight: FontWeight.w900, color: color)),
                            ],
                          ),
                          Text([entry.typeLabel, ?entry.method, ?entry.reference].join(' · '), style: const TextStyle(color: kMuted)),
                          Row(
                            children: [
                              Expanded(child: Text(fmtDateTime(entry.at), style: const TextStyle(color: kMuted, fontSize: 12))),
                              if (entry.receiptId != null)
                                TextButton.icon(
                                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                                  label: const Text('Reenviar'),
                                  onPressed: () => runAsync(context, () => _remote.resendReceipt(entry.receiptId!),
                                      success: 'Comprobante reenviado al huésped.'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}
