import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Methods a guest pays with from the app; the front desk also takes cash and cards.
const Set<String> _guestMethods = {'Yape', 'Plin', 'BankTransfer'};

class _Part {
  final TextEditingController amount = TextEditingController();
  final TextEditingController operation = TextEditingController();
  String method;

  _Part(this.method);

  void dispose() {
    amount.dispose();
    operation.dispose();
  }
}

/// Pays the balance of the backend's folio, split in up to 4 methods (US-16). Returns true once it is paid.
Future<bool> showFolioPaymentSheet(BuildContext context, Stay stay, {required double balance, String title = 'Pagar saldo'}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCardSurface,
    builder: (_) => _FolioPaymentForm(stay: stay, balance: balance, title: title),
  );
  return paid ?? false;
}

class _FolioPaymentForm extends StatefulWidget {
  final Stay stay;
  final double balance;
  final String title;

  const _FolioPaymentForm({required this.stay, required this.balance, required this.title});

  @override
  State<_FolioPaymentForm> createState() => _FolioPaymentFormState();
}

class _FolioPaymentFormState extends State<_FolioPaymentForm> {
  late final bool _guest = HotelStore.instance.currentUser?.role == UserRole.guest;
  late final List<({String value, String label})> _methods =
      kPaymentMethods.where((m) => !_guest || _guestMethods.contains(m.value)).toList();
  late final List<_Part> _parts = [_Part(_methods.first.value)..amount.text = widget.balance.toStringAsFixed(2)];
  bool _busy = false;

  @override
  void dispose() {
    for (final part in _parts) {
      part.dispose();
    }
    super.dispose();
  }

  void _addPart() {
    setState(() => _parts.add(_Part(_methods.first.value)));
  }

  Future<void> _pay() async {
    final parts = <({double amount, String method, String operationNumber})>[];
    for (final part in _parts) {
      final amount = double.tryParse(part.amount.text.replaceAll(',', '.').trim()) ?? 0;
      if (amount <= 0) {
        showAppSnack(context, 'Ingresa el monto de cada parte.', error: true);
        return;
      }
      parts.add((amount: amount, method: part.method, operationNumber: part.operation.text));
    }
    final total = parts.fold(0.0, (sum, p) => sum + p.amount);
    if (total > widget.balance + 0.005) {
      showAppSnack(context, 'Las partes suman ${money(total)} y el saldo es ${money(widget.balance)}.', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runAsync(context, () => HotelStore.instance.remote!.payFolio(widget.stay.id, parts),
        success: 'Pago registrado. Enviamos el comprobante a ${widget.stay.guestEmail}.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontFamily: kSerif, fontSize: 22)),
            Text('Saldo pendiente ${money(widget.balance)}', style: const TextStyle(color: kMuted)),
            for (var i = 0; i < _parts.length; i++) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(_parts.length == 1 ? 'Medio de pago' : 'Parte ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (_parts.length > 1)
                    IconButton(
                      tooltip: 'Quitar',
                      onPressed: () => setState(() => _parts.removeAt(i).dispose()),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in _methods)
                    ChoiceChip(label: Text(m.label), selected: _parts[i].method == m.value, onSelected: (_) => setState(() => _parts[i].method = m.value)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _parts[i].amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              if (_parts[i].method != 'Cash') ...[
                const SizedBox(height: 8),
                TextField(controller: _parts[i].operation, decoration: const InputDecoration(labelText: 'Número de operación o voucher')),
              ],
            ],
            if (_parts.length < 4)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _addPart, icon: const Icon(Icons.call_split), label: const Text('Dividir con otro medio')),
              ),
            const SizedBox(height: 12),
            AppButton(text: _busy ? 'Registrando…' : 'Pagar', icon: Icons.point_of_sale, dark: true, onPressed: _busy ? null : _pay),
          ],
        ),
      ),
    );
  }
}

/// The front desk posts an additional charge to the folio (minibar, laundry, damage...).
Future<void> showFolioChargeSheet(BuildContext context, Stay stay) async {
  final description = TextEditingController();
  final amount = TextEditingController();
  var category = 'Minibar';
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCardSurface,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cargo a ${stay.guestName}', style: const TextStyle(fontFamily: kSerif, fontSize: 22)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in RemoteHotel.chargeCategories.entries)
                  ChoiceChip(label: Text(entry.value), selected: category == entry.key, onSelected: (_) => setLocal(() => category = entry.key)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Descripción', hintText: 'Ej. 2 aguas del minibar')),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            const SizedBox(height: 16),
            AppButton(text: 'Agregar cargo', icon: Icons.add_card, dark: true, onPressed: () => Navigator.pop(sheetContext, true)),
          ],
        ),
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  await runAsync(
    context,
    () => HotelStore.instance.remote!.postCharge(stay.id,
        description: description.text, amount: double.tryParse(amount.text.replaceAll(',', '.').trim()) ?? 0, category: category),
    success: 'Cargo agregado al folio.',
  );
}

/// US-15: the refundable guarantee deposit, released at check-out.
Future<void> showDepositSheet(BuildContext context, Stay stay) async {
  final amount = TextEditingController(text: '150.00');
  final operation = TextEditingController();
  var method = kPaymentMethods.first.value;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCardSurface,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Depósito de garantía', style: TextStyle(fontFamily: kSerif, fontSize: 22)),
            const Text('Se devuelve automáticamente al hacer el check-out.', style: TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in kPaymentMethods)
                  ChoiceChip(label: Text(m.label), selected: method == m.value, onSelected: (_) => setLocal(() => method = m.value)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto'),
            ),
            if (method != 'Cash') ...[
              const SizedBox(height: 8),
              TextField(controller: operation, decoration: const InputDecoration(labelText: 'Número de operación o voucher')),
            ],
            const SizedBox(height: 16),
            AppButton(text: 'Registrar garantía', icon: Icons.shield_outlined, dark: true, onPressed: () => Navigator.pop(sheetContext, true)),
          ],
        ),
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  await runAsync(
    context,
    () => HotelStore.instance.remote!.holdDeposit(stay.id,
        amount: double.tryParse(amount.text.replaceAll(',', '.').trim()) ?? 0, method: method, operationNumber: operation.text),
    success: 'Garantía registrada.',
  );
}
