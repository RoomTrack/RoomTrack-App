import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/api_client.dart';
import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../core/seed.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import '../shell/role_shell.dart';
import 'mfa_page.dart';
import 'password_reset_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      showAppSnack(context, 'Ingresa tu correo y contraseña.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final remote = HotelStore.instance.remote;
      if (remote != null) {
        SessionStore.watch(remote.api);
        final outcome = await remote.signIn(_email.text, _password.text);
        if (!mounted) return;
        if (outcome is SignedIn) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleShell()));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => MfaPage(outcome: outcome)));
        }
        return;
      }
      final user = HotelStore.instance.signIn(_email.text, _password.text);
      await SessionStore.save(user);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'auth.email_not_verified') {
        _offerResend();
      } else {
        showAppSnack(context, e.message, error: true);
      }
    } on DomainException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _offerResend() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text('Primero verifica tu correo con el enlace que te enviamos.'),
      action: SnackBarAction(
        label: 'Reenviar',
        onPressed: () => runAsync(context, () => HotelStore.instance.remote!.resendVerification(_email.text),
            success: 'Te enviamos un nuevo enlace de verificación.'),
      ),
    ));
  }

  void _fillDemo(String email, String password) {
    _email.text = email;
    _password.text = password;
  }

  Future<void> _openRegister() async {
    final email = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
    if (email != null && mounted) _email.text = email;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kSoftGreen, kSurface, kSurface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(32)),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RoomTrackLogo(size: 48, inverted: true),
                          SizedBox(height: 14),
                          Text('RoomTrack', style: TextStyle(fontFamily: kSerif, color: Colors.white, fontSize: 30)),
                          SizedBox(height: 4),
                          Text('Toda la operación del hotel, en tiempo real.', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 24, offset: const Offset(0, 12))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Iniciar sesión', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          const Text('Verás solo las funciones de tu puesto.', style: TextStyle(color: kMuted)),
                          const SizedBox(height: 20),
                          TextField(
                            key: const Key('login-email'),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('login-password'),
                            controller: _password,
                            obscureText: _obscure,
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => PasswordResetPage(initialEmail: _email.text)),
                              ),
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          AppButton(text: 'Ingresar', icon: Icons.login, loading: _loading, dark: true, onPressed: _login),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: _openRegister,
                              child: const Text('Soy huésped y quiero crear mi cuenta'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The local seed accounts are only for development: never in a release build.
                    if (!backendEnabled || kDebugMode) ...[
                      const SizedBox(height: 18),
                      Text(
                        backendEnabled ? 'Cuentas del backend local (tool/seed_backend.py)' : 'Cuentas de demostración (contraseña $kDemoPassword)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final account in backendEnabled
                              ? [for (final a in kRemoteDemoAccounts) (email: a.email, label: a.label, password: a.password)]
                              : [for (final a in kDemoAccounts) (email: a.email, label: a.label, password: kDemoPassword)])
                            ActionChip(
                              avatar: const Icon(Icons.person_outline, size: 18),
                              label: Text(account.label),
                              onPressed: () => _fillDemo(account.email, account.password),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
