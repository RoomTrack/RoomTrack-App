import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

typedef PaymentParts = List<({double amount, CardInfo? card})>;

/// Card form with the simulated gateway; supports splitting between two methods (US-15, US-16).
///
/// Returns true once [onPay] succeeds. A declined card keeps the sheet open so
/// the guest can try another method.
Future<bool> showPaymentSheet(
  BuildContext context, {
  required String title,
  required double amount,
  required void Function(PaymentParts parts) onPay,
  bool allowSplit = false,
  bool allowCash = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentForm(title: title, amount: amount, onPay: onPay, allowSplit: allowSplit, allowCash: allowCash),
  );
  return result ?? false;
}

class _PartControllers {
  final TextEditingController amount = TextEditingController();
  final TextEditingController number = TextEditingController();
  final TextEditingController holder = TextEditingController();
  final TextEditingController expiry = TextEditingController();
  final TextEditingController cvv = TextEditingController();
  bool cash = false;

  CardInfo get card => CardInfo(number: number.text, holder: holder.text, expiry: expiry.text, cvv: cvv.text);

  void dispose() {
    for (final c in [amount, number, holder, expiry, cvv]) {
      c.dispose();
    }
  }
}

class _PaymentForm extends StatefulWidget {
  final String title;
  final double amount;
  final void Function(PaymentParts parts) onPay;
  final bool allowSplit;
  final bool allowCash;

  const _PaymentForm({required this.title, required this.amount, required this.onPay, required this.allowSplit, required this.allowCash});

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final List<_PartControllers> _parts = [_PartControllers()];
  String? _error;

  @override
  void initState() {
    super.initState();
    _parts.first.amount.text = widget.amount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final part in _parts) {
      part.dispose();
    }
    super.dispose();
  }

  void _toggleSplit(bool split) {
    setState(() {
      if (split) {
        final half = (widget.amount / 2).toStringAsFixed(2);
        _parts.first.amount.text = half;
        _parts.add(_PartControllers()..amount.text = (widget.amount - double.parse(half)).toStringAsFixed(2));
      } else {
        _parts.removeLast().dispose();
        _parts.first.amount.text = widget.amount.toStringAsFixed(2);
      }
    });
  }

  void _submit() {
    final parts = <({double amount, CardInfo? card})>[
      for (final part in _parts)
        (amount: double.tryParse(part.amount.text.replaceAll(',', '.')) ?? 0, card: part.cash ? null : part.card),
    ];
    try {
      widget.onPay(parts);
      Navigator.pop(context, true);
    } on DomainException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = _parts.length > 1;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text('Total ${money(widget.amount)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kPrimaryDark)),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: kMuted),
                SizedBox(width: 4),
                Expanded(child: Text('Pago seguro (demo). Prueba 4242 4242 4242 4242 · rechazo: 4000 0000 0000 0002', style: TextStyle(color: kMuted, fontSize: 12))),
              ],
            ),
            if (widget.allowSplit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dividir entre dos métodos'),
                value: split,
                onChanged: _toggleSplit,
              ),
            for (var i = 0; i < _parts.length; i++) ...[
              if (split) Text('Método ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (split) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _parts[i].amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
                ),
              ],
              if (widget.allowCash)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Efectivo en recepción'),
                  value: _parts[i].cash,
                  onChanged: (v) => setState(() => _parts[i].cash = v ?? false),
                ),
              if (!_parts[i].cash) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _parts[i].number,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Número de tarjeta', prefixIcon: Icon(Icons.credit_card)),
                ),
                const SizedBox(height: 8),
                TextField(controller: _parts[i].holder, decoration: const InputDecoration(labelText: 'Titular')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _parts[i].expiry, decoration: const InputDecoration(labelText: 'MM/AA'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _parts[i].cvv,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'CVV'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: kError.withAlpha(20), borderRadius: BorderRadius.circular(14)),
                child: Text(_error!, style: const TextStyle(color: kError, fontWeight: FontWeight.w700)),
              ),
            AppButton(text: 'Pagar', icon: Icons.lock, dark: true, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
