import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../front_desk/stay_detail_page.dart';

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
      );
    });
  }
}
