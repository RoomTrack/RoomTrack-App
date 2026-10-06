import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../hotel_store.dart';

/// Production gateway of RoomTrack (Render).
const String kProductionBaseUrl = 'https://roomtrack-api.onrender.com/api/v1';

/// Base URL of the RoomTrack gateway, e.g. `http://10.0.2.2:8080/api/v1` from the Android emulator.
/// Release builds use [kProductionBaseUrl] by default; debug builds without it run on the in-memory demo data.
/// `--dart-define=API_BASE_URL=` (empty) forces the demo in any build.
const String _rawBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: bool.fromEnvironment('dart.vm.product') ? kProductionBaseUrl : '');

bool get backendEnabled => _rawBaseUrl.trim().isNotEmpty;

/// Error returned by the RoomTrack API, reduced to a Spanish message the UI can show.
class ApiException extends DomainException {
  final int statusCode;

  /// Stable code of the backend ProblemDetails, e.g. `auth.email_not_verified`.
  final String code;

  const ApiException(this.statusCode, super.message, {this.code = ''});
}

/// Access and refresh tokens of the signed-in user.
class ApiSession {
  final String accessToken;
  final String? refreshToken;

  const ApiSession(this.accessToken, this.refreshToken);
}

/// HTTP access to the gateway. Keeps the session and renews it once with the refresh token on a 401.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  ApiSession? session;

  /// Called whenever the session changes (sign-in, refresh, revocation) so it can be persisted.
  void Function(ApiSession? session)? onSessionChanged;

  static String get baseUrl {
    final trimmed = _rawBaseUrl.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool json = true, String? bearer}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if ((bearer ?? session?.accessToken) case final token?) 'Authorization': 'Bearer $token',
      };

  void setSession(ApiSession? value) {
    session = value;
    onSessionChanged?.call(value);
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, [Object? body, String? bearer]) => _send('POST', path, body: body, bearer: bearer);

  Future<dynamic> put(String path, Object? body) => _send('PUT', path, body: body);

  Future<dynamic> patch(String path, Object? body) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Multipart request (the digital check-in uploads the identity document).
  Future<dynamic> postMultipart(String path, Map<String, String> fields, {required String fileField, required Uint8List bytes, required String fileName}) async {
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers(json: false))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(fileField, bytes, filename: fileName));
      return http.Response.fromStream(await _client.send(request));
    }

    var response = await _guard(send);
    if (response.statusCode == 401 && await _tryRefresh()) response = await _guard(send);
    return _decode(response);
  }

  Future<dynamic> _send(String method, String path, {Object? body, String? bearer}) async {
    Future<http.Response> send() {
      final request = http.Request(method, _uri(path))..headers.addAll(_headers(bearer: bearer));
      if (body != null) request.body = jsonEncode(body);
      return _client.send(request).then(http.Response.fromStream);
    }

    var response = await _guard(send);
    if (response.statusCode == 401 && bearer == null && !path.startsWith('/authentication') && await _tryRefresh()) {
      response = await _guard(send);
    }
    return _decode(response);
  }

  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(const Duration(seconds: 70));
    } catch (_) {
      throw const ApiException(0, 'No hay conexión con el servidor de RoomTrack. Revisa que el backend esté encendido.');
    }
  }

  Future<bool> _tryRefresh() async {
    final refresh = session?.refreshToken;
    if (refresh == null) return false;
    try {
      final response = await _client.post(_uri('/authentication/refresh'),
          headers: _headers(bearer: ''), body: jsonEncode({'refreshToken': refresh}));
      if (response.statusCode != 200) {
        setSession(null);
        return false;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setSession(ApiSession(data['token'] as String, data['refreshToken'] as String?));
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    final body = response.body.trim();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body.isEmpty ? null : jsonDecode(body);
    }
    throw problem(response.statusCode, body);
  }

  /// Reads an RFC 7807 ProblemDetails: `code` selects a Spanish message, `errors` lists the invalid fields.
  static ApiException problem(int statusCode, String body) {
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } catch (_) {}
    final code = parsed?['code']?.toString() ?? '';
    final known = _spanish[code];
    if (known != null) return ApiException(statusCode, known, code: code);

    final errors = parsed?['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final messages = errors.values
          .expand((value) => value is List ? value : [value])
          .map((value) => value is Map ? (value['message'] ?? value['detail'] ?? value).toString() : value.toString())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (messages.isNotEmpty) return ApiException(statusCode, messages.join('\n'), code: code);
    }
    final message = parsed?['detail']?.toString() ?? parsed?['title']?.toString();
    if (message != null && message.isNotEmpty) return ApiException(statusCode, message, code: code);
    return ApiException(statusCode, switch (statusCode) {
      401 => 'Tu sesión terminó. Vuelve a iniciar sesión.',
      403 => 'Tu rol no tiene permiso para esta acción.',
      404 => 'No encontramos lo que buscabas.',
      429 => 'Demasiados intentos. Espera un momento.',
      _ => 'Error del servidor ($statusCode).',
    }, code: code);
  }

  static const Map<String, String> _spanish = {
    'auth.invalid_credentials': 'Correo o contraseña incorrectos.',
    'auth.account_deactivated': 'Tu cuenta está desactivada. Contacta al administrador.',
    'auth.account_locked': 'Tu cuenta se bloqueó por varios intentos fallidos. Inténtalo en unos minutos.',
    'auth.email_not_verified': 'Primero verifica tu correo con el enlace que te enviamos.',
    'auth.session_revoked': 'Tu sesión fue cerrada. Vuelve a iniciar sesión.',
    'auth.token_expired': 'Tu sesión expiró. Vuelve a iniciar sesión.',
    'auth.refresh_token_invalid': 'Tu sesión expiró. Vuelve a iniciar sesión.',
    'mfa.invalid_code': 'El código no es correcto. Revisa tu app autenticadora.',
    'mfa.code_already_used': 'Ese código ya se usó. Espera el siguiente de tu app autenticadora.',
    'mfa.recovery_code_invalid': 'El código de recuperación no es válido.',
    'mfa.recovery_code_format': 'Un código de recuperación tiene el formato XXXXX-XXXXX.',
    'email_verification.link_expired': 'El enlace de verificación expiró. Pide uno nuevo.',
    'email_verification.link_invalid': 'El enlace de verificación no es válido.',
    'password_reset.link_expired': 'El enlace para restablecer la contraseña expiró. Pide uno nuevo.',
    'password_reset.link_invalid': 'El enlace para restablecer la contraseña no es válido.',
    'password.too_short': 'La contraseña es muy corta: mínimo 15 caracteres para huéspedes y 8 para el personal.',
    'password.too_common': 'Esa contraseña es muy común. Elige otra.',
    'password.breached': 'Esa contraseña apareció en filtraciones de datos. Elige otra.',
    'password.contains_email': 'La contraseña no puede contener tu correo.',
    'password.repetitive': 'La contraseña es demasiado repetitiva.',
    'user.email_already_registered': 'Ya existe una cuenta con ese correo.',
    'user.last_chain_admin': 'No puedes desactivar al último administrador de cadena.',
    'user.outside_hierarchy': 'No puedes modificar a un usuario de tu mismo nivel o superior.',
    'user.role_not_assignable': 'No puedes asignar ese rol.',
    'room.invalid_status_transition': 'Ese cambio de estado no está permitido para la habitación.',
    'room.not_ready': 'La habitación aún no está lista.',
    'booking.room_unavailable': 'La habitación no está libre en esas fechas.',
    'booking.room_under_maintenance': 'La habitación está en mantenimiento.',
    'booking.check_in_in_past': 'La fecha de llegada no puede ser pasada.',
    'booking.check_out_not_after_check_in': 'La salida debe ser al menos un día después de la llegada.',
    'booking.hotel_payment_settings_missing': 'El hotel aún no configuró sus medios de pago.',
    'payment.booking_already_paid': 'Esta reserva ya está pagada.',
    'payment.booking_not_pending': 'Solo se registran pagos de reservas pendientes.',
    'payment.operation_number_required': 'Ingresa el número de operación.',
    'check_in.booking_not_confirmed': 'Tu reserva debe estar pagada para hacer el check-in.',
    'check_in.not_open_yet': 'El check-in digital aún no está abierto para tu reserva.',
    'check_in.already_completed': 'Ya completaste el check-in.',
    'check_in.stay_ended': 'Tu estancia ya terminó.',
    'check_in.dni_invalid': 'El DNI debe tener 8 dígitos.',
    'check_in.dni_only_for_nationals': 'El DNI solo aplica a nacionalidad peruana (PE).',
    'check_in.passport_invalid': 'El pasaporte debe tener de 6 a 12 letras o dígitos.',
    'check_in.foreigner_card_invalid': 'El carné de extranjería debe tener de 8 a 12 letras o dígitos.',
    'check_in.foreigner_card_only_for_foreigners': 'El carné de extranjería no aplica a nacionalidad peruana.',
    'check_in.document_required': 'Sube una foto de tu documento de identidad.',
    'check_in.document_file_type': 'El documento debe ser JPG, PNG o PDF.',
    'check_in.document_too_large': 'El archivo del documento supera los 5 MB.',
    'check_in.nationality_invalid': 'La nacionalidad debe ser un código de 2 letras (PE, AR, US...).',
    'rate_limit.exceeded': 'Demasiados intentos. Espera un momento y vuelve a intentarlo.',
    'service.unavailable': 'Un servicio del backend no responde. Inténtalo en un momento.',
  };
}
