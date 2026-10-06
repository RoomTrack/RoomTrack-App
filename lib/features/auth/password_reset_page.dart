import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/ui.dart';

/// Recovery by e-mail link (US-01, escenario 4).
class PasswordResetPage extends StatefulWidget {
  final String initialEmail;

  const PasswordResetPage({super.key, this.initialEmail = ''});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  final TextEditingController _token = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  static const _sentMessage = 'Si el correo está registrado, te enviamos un enlace seguro para restablecer tu contraseña.';

  Future<void> _send() async {
    final remote = HotelStore.instance.remote;
    if (remote == null) {
      showAppSnack(context, HotelStore.instance.requestPasswordReset(_email.text));
      setState(() => _sent = true);
      return;
    }
    final ok = await runAsync(context, () => remote.requestPasswordReset(_email.text), success: _sentMessage);
    if (ok && mounted) setState(() => _sent = true);
  }

  /// In the demo the link is read from the local outbox.
  void _openDemoLink() {
    final token = HotelStore.instance.lastResetToken(_email.text);
    if (token == null) {
      showAppSnack(context, 'No hay un enlace para ese correo.', error: true);
      return;
    }
    setState(() => _token.text = token);
  }

  Future<void> _reset() async {
    final store = HotelStore.instance;
    final remote = store.remote;
    final bool ok;
    if (remote == null) {
      ok = runAction(context, () => store.resetPassword(_token.text, _password.text),
          success: 'Contraseña actualizada. Ya puedes iniciar sesión.');
    } else {
      ok = await runAsync(context, () => remote.resetPassword(_token.text, _password.text),
          success: 'Contraseña actualizada. Ya puedes iniciar sesión.');
    }
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final remote = HotelStore.instance.isRemote;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Te enviaremos un enlace seguro a tu correo para crear una nueva contraseña.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 14),
          AppButton(text: 'Enviar enlace', icon: Icons.send, onPressed: _send),
          if (_sent) ...[
            const SizedBox(height: 28),
            const Text('Restablecer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Abre el enlace del correo o pégalo aquí.', style: TextStyle(color: kMuted)),
            if (!remote)
              TextButton.icon(onPressed: _openDemoLink, icon: const Icon(Icons.mark_email_read_outlined), label: const Text('Abrir el enlace (demo)')),
            const SizedBox(height: 8),
            TextField(controller: _token, decoration: const InputDecoration(labelText: 'Enlace o código')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: remote ? 'Nueva contraseña (15+ huésped, 8+ personal)' : 'Nueva contraseña'),
            ),
            const SizedBox(height: 14),
            AppButton(text: 'Guardar contraseña', icon: Icons.lock_reset, dark: true, onPressed: _reset),
          ],
        ],
      ),
    );
  }
}
