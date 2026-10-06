import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Guest folio: charges, payments, deposit and balance (US-15, US-16).
class FolioCard extends StatelessWidget {
  final Stay stay;
  final HotelStore store;

  const FolioCard({super.key, required this.stay, required this.store});

  @override
  Widget build(BuildContext context) {
    final balance = store.balanceOf(stay);
    final payments = store.paymentsOf(stay.id);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Folio', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              Pill(
                text: balance > 0 ? 'Saldo ${money(balance)}' : 'Saldado',
                color: balance > 0 ? kWarning : kSuccess,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final charge in stay.charges) _Line(charge.description, money(charge.amount)),
          const Divider(),
          _Line('Total cargos', money(store.totalCharges(stay)), bold: true),
          _Line('Pagado', '- ${money(store.paidFor(stay))}'),
          _Line('Saldo pendiente', money(balance), bold: true),
          const SizedBox(height: 8),
          _Line(
            'Depósito de garantía',
            stay.depositRefunded
                ? '${money(stay.depositHeld)} devuelto'
                : stay.depositHeld > 0
                    ? '${money(stay.depositHeld)} retenido'
                    : '${money(stay.depositRequired)} pendiente',
          ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Movimientos', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final p in payments)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      p.status == PaymentStatus.rejected ? Icons.cancel_outlined : Icons.check_circle_outline,
                      size: 16,
                      color: p.status == PaymentStatus.rejected ? kError : kSuccess,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${p.kind.label} · ${p.method}${p.reason.isEmpty ? '' : ' (${p.reason})'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _Line(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Fiscal data so the receipt is issued as an invoice (US-17).
Future<void> editFiscalData(BuildContext context, HotelStore store, Stay stay) async {
  final ruc = TextEditingController(text: stay.fiscalData?.ruc ?? '');
  final name = TextEditingController(text: stay.fiscalData?.businessName ?? '');
  final address = TextEditingController(text: stay.fiscalData?.address ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Datos para factura'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: ruc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'RUC (11 dígitos)')),
          const SizedBox(height: 8),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Razón social')),
          const SizedBox(height: 8),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección fiscal')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  runAction(
    context,
    () => store.setFiscalData(stay.id, FiscalData(ruc: ruc.text.trim(), businessName: name.text.trim(), address: address.text.trim())),
    success: 'Los próximos comprobantes se emitirán como factura.',
  );
}
