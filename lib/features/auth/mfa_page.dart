import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../shared/ui.dart';
import '../shell/role_shell.dart';

/// Second factor of the staff accounts (US-01): enroll an authenticator app or type one of its codes.
class MfaPage extends StatefulWidget {
  final SignInOutcome outcome;

  const MfaPage({super.key, required this.outcome});

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final RemoteHotel _remote = HotelStore.instance.remote!;
  final TextEditingController _code = TextEditingController();
  MfaEnrollment? _enrollment;
  bool _useRecoveryCode = false;
  bool _loading = false;
  String? _error;

  bool get _enrolling => widget.outcome is MfaEnrollmentNeeded;

  String get _mfaToken => switch (widget.outcome) {
        MfaEnrollmentNeeded(:final mfaToken) || MfaCodeNeeded(:final mfaToken) => mfaToken,
        _ => '',
      };

  String get _email => switch (widget.outcome) {
        MfaEnrollmentNeeded(:final email) || MfaCodeNeeded(:final email) => email,
        _ => '',
      };

  @override
  void initState() {
    super.initState();
    if (_enrolling) _startEnrollment();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() => _loading = true);
    try {
      final enrollment = await _remote.startMfaEnrollment(_mfaToken);
      if (mounted) setState(() => _enrollment = enrollment);
    } on DomainException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_enrolling) {
        final recoveryCodes = await _remote.confirmMfaEnrollment(_mfaToken, _code.text);
        if (mounted && recoveryCodes.isNotEmpty) await _showRecoveryCodes(recoveryCodes);
      } else {
        await _remote.verifyMfa(
          _mfaToken,
          code: _useRecoveryCode ? null : _code.text,
          recoveryCode: _useRecoveryCode ? _code.text : null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RoleShell()), (_) => false);
    } on DomainException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryCodes(List<String> codes) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guarda tus códigos de recuperación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Úsalos si pierdes tu celular. Cada uno sirve una sola vez y no volveremos a mostrarlos.'),
            const SizedBox(height: 12),
            SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: codes.join('\n'))),
            child: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Ya los guardé')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enrollment = _enrollment;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            _enrolling ? 'Protege tu cuenta' : 'Ingresa tu código',
            style: const TextStyle(fontFamily: kSerif, fontSize: 28),
          ),
          const SizedBox(height: 6),
          Text(
            _enrolling
                ? 'Las cuentas del personal usan una app autenticadora (Google Authenticator, Microsoft Authenticator...). '
                    'Escanea el código QR con ella y escribe el código de 6 dígitos que te muestra.'
                : 'Abre tu app autenticadora y escribe el código de 6 dígitos de RoomTrack para $_email.',
            style: const TextStyle(color: kMuted),
          ),
          const SizedBox(height: 20),
          if (_enrolling && enrollment != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
                child: QrImageView(data: enrollment.otpAuthUri, size: 200, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            const Text('¿No puedes escanear? Escribe esta clave en tu app:', style: TextStyle(color: kMuted)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    enrollment.secret.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim(),
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar clave',
                  onPressed: () => Clipboard.setData(ClipboardData(text: enrollment.secret)),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_enrolling && enrollment == null && _loading) const LoadingView(message: 'Preparando tu clave...'),
          TextField(
            controller: _code,
            autofocus: !_enrolling,
            keyboardType: _useRecoveryCode ? TextInputType.text : TextInputType.number,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: _useRecoveryCode ? 'Código de recuperación (XXXXX-XXXXX)' : 'Código de 6 dígitos',
              prefixIcon: const Icon(Icons.password),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: kError, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          AppButton(
            text: _enrolling ? 'Activar y entrar' : 'Verificar',
            icon: Icons.verified_user_outlined,
            dark: true,
            loading: _loading,
            onPressed: _enrolling && enrollment == null ? null : _submit,
          ),
          if (!_enrolling)
            TextButton(
              onPressed: () => setState(() {
                _useRecoveryCode = !_useRecoveryCode;
                _code.clear();
              }),
              child: Text(_useRecoveryCode ? 'Usar el código de mi app' : 'No tengo mi celular: usar un código de recuperación'),
            ),
        ],
      ),
    );
  }
}
