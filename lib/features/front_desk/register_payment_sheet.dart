import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// The front desk registers the payment of a pending booking; the backend confirms it (US-15, US-17).
Future<void> showRegisterPaymentSheet(BuildContext context, Stay stay) async {
  final store = HotelStore.instance;
  var method = kPaymentMethods.first.value;
  final operation = TextEditingController();
  final note = TextEditingController();
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
            Text('Registrar pago · ${stay.code ?? stay.guestName}', style: const TextStyle(fontFamily: kSerif, fontSize: 22)),
            Text('Total de la reserva ${money(store.totalCharges(stay))}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in kPaymentMethods)
                  ChoiceChip(label: Text(m.label), selected: method == m.value, onSelected: (_) => setLocal(() => method = m.value)),
              ],
            ),
            const SizedBox(height: 12),
            if (method != 'Cash')
              TextField(controller: operation, decoration: const InputDecoration(labelText: 'Número de operación o voucher')),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 16),
            AppButton(text: 'Registrar pago', icon: Icons.point_of_sale, dark: true, onPressed: () => Navigator.pop(sheetContext, true)),
          ],
        ),
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  await runAsync(
    context,
    () => store.remote!.registerPayment(stay.id, method: method, operationNumber: operation.text, note: note.text),
    success: 'Pago registrado: la reserva quedó confirmada y el huésped ya puede hacer su check-in.',
  );
}
