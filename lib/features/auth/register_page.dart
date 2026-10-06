import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/ui.dart';

/// Guests create their own account; staff accounts are created by the admin (US-03).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _link = TextEditingController();
  bool _loading = false;

  /// With the backend the account exists only after the e-mail link is opened.
  bool _awaitingVerification = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    final store = HotelStore.instance;
    final remote = store.remote;
    if (remote == null) {
      final ok = runAction(
        context,
        () => store.registerGuest(name: _name.text, email: _email.text, password: _password.text),
        success: 'Cuenta creada. Si tienes una reserva con este correo, ya aparece en tu estancia.',
      );
      if (ok) Navigator.pop(context, _email.text.trim());
      return;
    }
    setState(() => _loading = true);
    final ok = await runAsync(
      context,
      () => remote.signUpGuest(name: _name.text, email: _email.text, password: _password.text),
      success: 'Te enviamos un enlace a tu correo para verificar la cuenta.',
    );
    if (mounted) {
      setState(() {
        _loading = false;
        _awaitingVerification = ok;
      });
    }
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final ok = await runAsync(context, () => HotelStore.instance.remote!.verifyEmail(_link.text),
        success: 'Correo verificado. Ya puedes iniciar sesión.');
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) Navigator.pop(context, _email.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final remote = HotelStore.instance.isRemote;
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta de huésped')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Usa el mismo correo de tu reserva para vincularla.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !_awaitingVerification,
            decoration: const InputDecoration(labelText: 'Nombre y apellido', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            enabled: !_awaitingVerification,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_awaitingVerification,
            obscureText: true,
            decoration: InputDecoration(
              labelText: remote ? 'Contraseña (mín. 15 caracteres)' : 'Contraseña (mín. 6 caracteres)',
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 18),
          if (!_awaitingVerification)
            AppButton(text: 'Crear cuenta', icon: Icons.person_add_alt, dark: true, loading: _loading, onPressed: _register)
          else ...[
            AppCard(
              color: kSoftGreen,
              child: const Text('Abre el enlace que te enviamos por correo. Si lo abriste en otro dispositivo, pégalo aquí.'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _link, decoration: const InputDecoration(labelText: 'Enlace o código de verificación')),
            const SizedBox(height: 12),
            AppButton(text: 'Verificar correo', icon: Icons.mark_email_read_outlined, dark: true, loading: _loading, onPressed: _verify),
            TextButton(
              onPressed: () => runAsync(context, () => HotelStore.instance.remote!.resendVerification(_email.text),
                  success: 'Te enviamos un nuevo enlace.'),
              child: const Text('Reenviar enlace'),
            ),
          ],
        ],
      ),
    );
  }
}
