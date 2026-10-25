import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../shared/ui.dart';

/// How the guests pay their bookings: Yape, Plin or a bank account. Until it is set the hotel takes no bookings.
class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage> {
  final RemoteHotel _remote = HotelStore.instance.remote!;
  final TextEditingController _holder = TextEditingController();
  final TextEditingController _yape = TextEditingController();
  final TextEditingController _plin = TextEditingController();
  final TextEditingController _bank = TextEditingController();
  final TextEditingController _account = TextEditingController();
  final TextEditingController _cci = TextEditingController();
  late Future<void> _loading = _load();
  bool _acceptsBookings = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_holder, _yape, _plin, _bank, _account, _cci]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async => _show(await _remote.paymentSettings());

  void _show(HotelPaymentSettings settings) {
    _acceptsBookings = settings.acceptsBookings;
    _holder.text = settings.accountHolder ?? '';
    _yape.text = settings.yapeNumber ?? '';
    _plin.text = settings.plinNumber ?? '';
    _bank.text = settings.bankName ?? '';
    _account.text = settings.bankAccountNumber ?? '';
    _cci.text = settings.bankAccountCci ?? '';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await runAsync(context, () async {
      final saved = await _remote.updatePaymentSettings(HotelPaymentSettings(
        accountHolder: _holder.text,
        yapeNumber: _yape.text,
        plinNumber: _plin.text,
        bankName: _bank.text,
        bankAccountNumber: _account.text,
        bankAccountCci: _cci.text,
      ));
      _show(saved);
    }, success: 'Medios de pago guardados. Los huéspedes los verán al reservar.');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medios de pago', style: TextStyle(fontWeight: FontWeight.w900))),
      body: FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) {
            final error = snapshot.error;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                EmptyState(
                  icon: Icons.cloud_off_outlined,
                  message: error is DomainException ? error.message : 'No pudimos cargar los medios de pago.',
                ),
                AppButton(text: 'Reintentar', icon: Icons.refresh, outlined: true, onPressed: () => setState(() => _loading = _load())),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _acceptsBookings
                  ? const InfoRow(Icons.check_circle_outline, 'El hotel acepta reservas con estos medios de pago.', color: kSuccess)
                  : const InfoRow(Icons.warning_amber_outlined, 'Configura al menos un medio de pago: sin él el hotel no recibe reservas.',
                      color: kWarning),
              const SectionHeader(title: 'Titular', subtitle: 'A nombre de quién pagan los huéspedes.'),
              TextField(controller: _holder, decoration: const InputDecoration(labelText: 'Titular de la cuenta', prefixIcon: Icon(Icons.person_outline))),
              const SectionHeader(title: 'Billeteras', subtitle: 'Celular de 9 dígitos que empieza con 9.'),
              TextField(
                controller: _yape,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Número de Yape', prefixIcon: Icon(Icons.phone_iphone)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _plin,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Número de Plin', prefixIcon: Icon(Icons.phone_iphone)),
              ),
              const SectionHeader(title: 'Transferencia bancaria', subtitle: 'Déjala en blanco si no la ofreces.'),
              TextField(controller: _bank, decoration: const InputDecoration(labelText: 'Banco', prefixIcon: Icon(Icons.account_balance_outlined))),
              const SizedBox(height: 10),
              TextField(
                controller: _account,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Número de cuenta', prefixIcon: Icon(Icons.numbers)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cci,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CCI (20 dígitos, opcional)', prefixIcon: Icon(Icons.numbers)),
              ),
              const SizedBox(height: 16),
              AppButton(text: 'Guardar medios de pago', icon: Icons.save, dark: true, loading: _saving, onPressed: _save),
            ],
          );
        },
      ),
    );
  }
}
