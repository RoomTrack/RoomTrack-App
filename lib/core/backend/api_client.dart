import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../hotel_store.dart';

/// Production gateway of RoomTrack (Azure Container Apps, Chile Central).
const String kProductionBaseUrl = 'https://gateway.bravepond-f06cc29c.chilecentral.azurecontainerapps.io/api/v1';

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

  /// `params` of the ProblemDetails (e.g. the estimated wait of `check_in.room_not_ready`).
  final Map<String, dynamic> params;

  const ApiException(this.statusCode, super.message, {this.code = '', this.params = const {}});
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

  /// The hotel a chain administrator is working on: every read without its own `hotelId` is scoped to it, since
  /// the backend answers a chain administrator with the whole chain otherwise. Null for everybody else.
  int? scopeHotelId;

  static String get baseUrl {
    final trimmed = _rawBaseUrl.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// [path] with the chain administrator's hotel, unless it already names one.
  String _scoped(String path) {
    final hotel = scopeHotelId;
    if (hotel == null || path.contains('hotelId=') || path.startsWith('/authentication') || path.startsWith('/hotels')) {
      return path;
    }
    return '$path${path.contains('?') ? '&' : '?'}hotelId=$hotel';
  }

  Map<String, String> _headers({bool json = true, String? bearer}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if ((bearer ?? session?.accessToken) case final token?) 'Authorization': 'Bearer $token',
      };

  void setSession(ApiSession? value) {
    session = value;
    onSessionChanged?.call(value);
  }

  Future<dynamic> get(String path) => _send('GET', _scoped(path));

  /// A text download (a CSV report): the body as it comes, or the backend's problem as an [ApiException].
  Future<String> getText(String path) async {
    Future<http.Response> send() => _client
        .send(http.Request('GET', _uri(_scoped(path)))..headers.addAll({..._headers(json: false), 'Accept': 'text/csv, */*'}))
        .then(http.Response.fromStream);

    var response = await _guard(send);
    if (response.statusCode == 401 && await _tryRefresh()) response = await _guard(send);
    if (response.statusCode >= 200 && response.statusCode < 300) return utf8.decode(response.bodyBytes);
    throw problem(response.statusCode, response.body);
  }

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

  /// Multipart upload to a URL outside the gateway, without the session (a signed Cloudinary upload).
  Future<Map<String, dynamic>> uploadTo(String url, Map<String, String> fields,
      {required String fileField, required Uint8List bytes, required String fileName}) async {
    final response = await _guard(() async {
      final request = http.MultipartRequest('POST', Uri.parse(url))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(fileField, bytes, filename: fileName));
      return http.Response.fromStream(await _client.send(request));
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'No se pudo subir la imagen (${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
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
      // The gateway and some services scale to zero, and the gateway waits up to 90 s for a sleeping service to boot
      // before forwarding to it: the first requests after a while take from ~20 s to over a minute.
      return await send().timeout(const Duration(seconds: 100));
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
    final params = (parsed?['params'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final known = _withParams(code, params) ?? _spanish[code];
    if (known != null) return ApiException(statusCode, known, code: code, params: params);

    // Each broken rule carries its own code (e.g. `payment_settings.cci_invalid`).
    final violations = parsed?['violations'];
    if (violations is List) {
      final messages = violations
          .map((v) => v is Map ? _spanish[v['code']?.toString()] : null)
          .whereType<String>()
          .toSet();
      if (messages.isNotEmpty) return ApiException(statusCode, messages.join('\n'), code: code);
    }

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
      502 || 503 || 504 => 'El servidor está arrancando. Inténtalo de nuevo en un momento.',
      _ => 'Error del servidor ($statusCode).',
    }, code: code);
  }

  /// Messages that carry the `params` of the error.
  static String? _withParams(String code, Map<String, dynamic> params) {
    switch (code) {
      case 'check_in.room_not_ready':
        final minutes = (params['estimatedWaitMinutes'] as num?)?.toInt();
        return minutes == null
            ? 'Tu habitación aún no está lista. Pide ayuda a recepción.'
            : 'Tu habitación aún no está lista: estará en unos $minutes ${minutes == 1 ? 'minuto' : 'minutos'}.';
      case 'payment.card_declined':
        final reason = params['reason']?.toString().trim() ?? '';
        return 'La tarjeta fue rechazada${reason.isEmpty ? '.' : ': $reason'} Prueba con otra tarjeta o paga en el hotel.';
    }
    return null;
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
    'incident.already_resolved': 'Esta incidencia ya está resuelta.',
    'incident.assign_not_allowed': 'Solo el administrador puede asignarla a otra persona o quitársela a su responsable.',
    'incident.assignee_not_maintenance': 'Solo se asigna a personal de mantenimiento del hotel.',
    'incident.invalid_status_transition': 'La incidencia cambió de estado. Actualiza la pantalla.',
    'incident.not_assigned': 'Primero asigna la incidencia a un técnico.',
    'incident.not_assignee': 'Solo su responsable o un administrador puede hacerlo.',
    'incident.title_length': 'El título debe tener de 3 a 120 caracteres.',
    'incident.description_length': 'El detalle no puede pasar de 1000 caracteres.',
    'incident.resolution_notes_required': 'Agrega observaciones sobre la solución.',
    'incident.resolution_notes_length': 'Las observaciones no pueden pasar de 1000 caracteres.',
    'cleaning_task.assign_not_allowed': 'Solo recepción o un administrador puede asignarla a otra persona.',
    'cleaning_task.assignee_not_housekeeping': 'Solo se asigna a personal de limpieza del hotel.',
    'cleaning_task.cancellation_reason_length': 'El motivo no puede pasar de 500 caracteres.',
    'cleaning_task.closed': 'Esta tarea ya está cerrada.',
    'cleaning_task.invalid_status_transition': 'La tarea cambió de estado. Actualiza la pantalla.',
    'cleaning_task.manage_not_allowed': 'Solo recepción o un administrador puede hacerlo.',
    'cleaning_task.no_housekeeper_available': 'No hay personal de limpieza activo para asignarla.',
    'cleaning_task.not_assigned': 'Primero asigna la tarea a alguien de limpieza.',
    'cleaning_task.not_assignee': 'Solo la persona responsable puede actualizar esta tarea.',
    'cleaning_task.notes_length': 'Las indicaciones no pueden pasar de 500 caracteres.',
    'cleaning_task.room_already_has_open_task': 'Esa habitación ya tiene una tarea de limpieza abierta.',
    'cleaning_task.checklist_incomplete': 'Completa los ítems obligatorios del checklist antes de marcarla como limpia.',
    'cleaning_task.checklist_item_not_found': 'Ese ítem ya no está en el checklist. Actualiza la pantalla.',
    'cleaning_checklist.item_duplicated': 'Hay un ítem repetido en el checklist.',
    'cleaning_checklist.item_label': 'Cada ítem del checklist necesita un texto de hasta 150 caracteres.',
    'cleaning_checklist.items_count': 'El checklist debe tener de 1 a 30 ítems.',
    'preventive_maintenance.description_length': 'El detalle no puede pasar de 1000 caracteres.',
    'preventive_maintenance.first_due_in_past': 'La primera fecha no puede ser pasada.',
    'preventive_maintenance.frequency_range': 'La frecuencia debe ser de 1 a 365 días.',
    'preventive_maintenance.inactive': 'Este mantenimiento preventivo ya está desactivado.',
    'preventive_maintenance.not_due': 'Este mantenimiento aún no vence.',
    'preventive_maintenance.reminder_range': 'El recordatorio debe ser de 0 a 30 días antes.',
    'preventive_maintenance.title_length': 'El título debe tener de 3 a 120 caracteres.',
    'guest_request.area_required': 'Indica el área que atiende la solicitud.',
    'guest_request.assignee_not_of_area': 'Solo se asigna a alguien del área de la solicitud.',
    'guest_request.closed': 'Esta solicitud ya está cerrada.',
    'guest_request.description_length': 'El detalle no puede pasar de 1000 caracteres.',
    'guest_request.no_current_stay': 'Necesitas una estadía en curso para enviar solicitudes.',
    'guest_request.not_allowed': 'Tu rol no puede hacer esto con la solicitud.',
    'guest_request.note_length': 'La nota no puede pasar de 500 caracteres.',
    'guest_request.room_required': 'Indica la habitación de la solicitud.',
    'guest_request.title_length': 'Describe la solicitud en 3 a 120 caracteres.',
    'service_catalog.not_available': 'Este servicio no está disponible por ahora.',
    'service_catalog.other_hotel': 'Ese servicio no es del catálogo de tu hotel.',
    'service_catalog.hotel_required': 'Necesitas una estadía en curso para ver los servicios del hotel.',
    'service_catalog.name_length': 'El nombre del servicio debe tener de 3 a 80 caracteres.',
    'service_catalog.description_length': 'La descripción no puede pasar de 500 caracteres.',
    'service_catalog.price_invalid': 'El precio va de 0 (incluido) a 99 999.99, con hasta 2 decimales.',
    'service_catalog.estimated_minutes_invalid': 'El tiempo estimado va de 1 a 1440 minutos.',
    'stay_review.stay_not_finished': 'Podrás evaluar tu estancia después del check-out.',
    'stay_review.window_closed': 'El plazo para evaluar esta estancia (30 días) ya terminó.',
    'stay_review.already_submitted': 'Ya evaluaste esta estancia. ¡Gracias!',
    'stay_review.rating_out_of_range': 'Cada calificación va de 1 a 5 estrellas.',
    'stay_review.comment_too_long': 'El comentario no puede pasar de 1000 caracteres.',
    'stay_review.period_invalid': 'Revisa el rango de fechas (máximo 366 días).',
    'staff_performance.invalid_period': 'Revisa el rango de fechas (máximo 366 días).',
    'report_schedule.recipients_required': 'Agrega al menos un destinatario.',
    'report_schedule.too_many_recipients': 'Un envío programado tiene como máximo 10 destinatarios.',
    'report_schedule.recipient_invalid': 'Hay un correo de destinatario que no es válido.',
    'report_schedule.no_report_selected': 'Elige al menos un reporte para enviar.',
    'conversation.access_denied': 'No participas en esta conversación.',
    'conversation.no_current_stay': 'Necesitas una estadía en curso para escribir a recepción.',
    'conversation.not_an_area': 'Esa área no tiene canal de mensajes.',
    'message.body_length': 'El mensaje debe tener de 1 a 2000 caracteres.',
    'check_out.already_completed': 'El check-out ya se hizo.',
    'check_out.not_checked_in': 'Solo se hace el check-out de una estadía con check-in.',
    'folio.amount_range': 'El monto debe ser mayor que 0 y de hasta S/ 100 000.',
    'folio.balance_pending': 'La cuenta tiene saldo pendiente: primero hay que pagarlo.',
    'folio.booking_not_staying': 'La reserva no está hospedada en el hotel.',
    'folio.charge_description_length': 'Describe el cargo en hasta 150 caracteres.',
    'folio.closed': 'La cuenta de esta estadía ya está cerrada.',
    'folio.deposit_already_held': 'La garantía ya fue registrada.',
    'folio.nothing_to_pay': 'No hay saldo pendiente.',
    'folio.overpayment': 'El pago supera el saldo pendiente.',
    'folio.payment_parts_count': 'Un pago se divide en hasta 4 partes.',
    'invoice.address_length': 'La dirección no puede pasar de 200 caracteres.',
    'invoice.business_name_length': 'Indica la razón social (hasta 150 caracteres).',
    'invoice.invalid_ruc': 'El RUC no es válido: son 11 dígitos.',
    'shift.already_assigned': 'Esa persona ya está en el turno.',
    'shift.already_exists': 'Ya hay un turno de esa área en ese horario.',
    'shift.date_in_past': 'No se programan turnos en fechas pasadas.',
    'shift.double_booked': 'Esa persona ya tiene otro turno a esa hora.',
    'shift.minimum_staff_range': 'El mínimo de personal debe ser de 1 a 50.',
    'shift.not_assigned': 'Esa persona no está en el turno.',
    'shift.not_staff_of_hotel': 'Solo se asigna personal del hotel.',
    'shift_handover.area_required': 'Indica el área de la entrega de turno.',
    'shift_handover.empty': 'Escribe una nota o deja pendientes para el siguiente turno.',
    'shift_handover.notes_length': 'Las notas no pueden pasar de 2000 caracteres.',
    'shift_handover.own_handover': 'No confirmas la lectura de tu propia entrega.',
    'shift_swap.not_pending': 'Ese cambio de turno ya fue decidido.',
    'shift_swap.other_hotel': 'El cambio de turno debe ser con alguien de tu hotel.',
    'shift_swap.reason_length': 'El motivo no puede pasar de 300 caracteres.',
    'shift_swap.same_shift': 'Elige turnos distintos para el cambio.',
    'push.category_unknown': 'Ese tipo de notificación no existe.',
    'request.conflict': 'Otra persona cambió esto al mismo tiempo. Actualiza e inténtalo de nuevo.',
    'resource.not_found': 'No encontramos lo que buscabas.',
    'auth.forbidden': 'Tu rol no tiene permiso para esta acción.',
    'room.occupied':'La habitación está ocupada: se limpia cuando el huésped haga el check-out.',
    'room.blocked_by_incident': 'Una incidencia abierta bloquea la habitación: primero hay que resolverla.',
    'room.invalid_status_transition': 'Ese cambio de estado no está permitido para la habitación.',
    'room.not_ready': 'La habitación aún no está lista.',
    'booking.room_unavailable': 'La habitación no está libre en esas fechas.',
    'booking.room_under_maintenance': 'La habitación está en mantenimiento.',
    'booking.check_in_in_past': 'La fecha de llegada no puede ser pasada.',
    'booking.check_out_not_after_check_in': 'La salida debe ser al menos un día después de la llegada.',
    'booking.hotel_payment_settings_missing': 'El hotel aún no configuró sus medios de pago.',
    'booking.cancellation_not_allowed': 'Solo se cancelan reservas pendientes o confirmadas.',
    'booking.cancellation_too_late': 'Ya no se puede cancelar: el check-in es hoy o ya pasó.',
    'payment_settings.account_holder_required': 'Indica a nombre de quién se paga.',
    'payment_settings.account_holder_length': 'El titular debe tener de 2 a 100 caracteres.',
    'payment_settings.method_required': 'Configura al menos un medio de pago: Yape, Plin o una cuenta bancaria.',
    'payment_settings.yape_number_invalid': 'El número de Yape debe ser un celular de 9 dígitos que empiece con 9.',
    'payment_settings.plin_number_invalid': 'El número de Plin debe ser un celular de 9 dígitos que empiece con 9.',
    'payment_settings.bank_name_required': 'Indica el banco de la cuenta.',
    'payment_settings.bank_name_length': 'El nombre del banco debe tener de 2 a 60 caracteres.',
    'payment_settings.bank_account_number_required': 'Indica el número de cuenta del banco.',
    'payment_settings.bank_account_number_invalid': 'El número de cuenta debe tener de 8 a 20 dígitos.',
    'payment_settings.cci_invalid': 'El CCI debe tener 20 dígitos.',
    'payment.booking_already_paid': 'Esta reserva ya está pagada.',
    'payment.booking_not_pending': 'Solo se registran pagos de reservas pendientes.',
    'payment.operation_number_required': 'Ingresa el número de operación.',
    'payment.online_card_not_registrable': 'El pago con tarjeta en línea lo hace el huésped desde su app.',
    'payment.card_declined': 'La tarjeta fue rechazada. Prueba con otra tarjeta o paga en el hotel.',
    'payment.card_token_invalid': 'No pudimos leer la tarjeta. Vuelve a ingresarla.',
    'check_in.booking_not_confirmed': 'Tu reserva debe estar pagada para hacer el check-in.',
    'check_in.not_open_yet': 'El check-in digital aún no está abierto para tu reserva.',
    'check_in.already_completed': 'Ya completaste el check-in.',
    'check_in.awaiting_arrival': 'Ya hiciste tu check-in digital: al llegar al hotel confirma tu identidad para recibir tu código.',
    'check_in.not_awaiting_arrival': 'Esta reserva no tiene un check-in esperando la llegada: completa el check-in digital.',
    'check_in.identity_mismatch': 'El número no coincide con el del documento que enviaste en el check-in.',
    'check_in.room_not_ready': 'Tu habitación aún no está lista. Pide ayuda a recepción.',
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
    'booking.change_not_allowed': 'Solo se cambian reservas pendientes o confirmadas.',
    'booking.change_requires_field': 'Indica la nueva fecha o la nueva habitación.',
    'booking.paid_total_mismatch': 'La reserva ya está pagada: el cambio debe mantener el mismo total.',
    'room.has_active_bookings': 'La habitación tiene reservas activas: no se puede eliminar.',
    'room.not_found': 'Esa habitación ya no existe.',
    'room.number_invalid': 'El número de habitación debe tener hasta 10 caracteres.',
    'room.number_taken': 'Ya existe una habitación con ese número en el hotel.',
    'room.price_out_of_range': 'El precio por noche debe estar entre 0.01 y 100000.',
    'room_type.not_found': 'Ese tipo de habitación ya no existe.',
    'hotel.image_url_not_allowed': 'La imagen debe ser una URL https válida.',
    'hotel.not_found': 'No encontramos el hotel.',
    'media.uploads_not_configured': 'Este servidor no tiene configurada la subida de imágenes.',
    'guest_profile.already_linked': 'Esta ficha ya está vinculada a otra cuenta.',
    'guest_profile.correction_reason_required': 'Indica el motivo de la corrección.',
    'guest_profile.identification_already_set': 'La ficha ya tiene documento: un administrador puede corregirlo.',
    'guest_profile.inactive': 'La ficha del huésped está desactivada.',
    'guest_profile.no_document_to_correct': 'La ficha aún no tiene documento que corregir.',
    'profile.dni_invalid': 'El DNI debe tener 8 dígitos.',
    'profile.passport_invalid': 'El pasaporte debe tener de 6 a 12 letras o dígitos.',
    'profile.foreigner_id_invalid': 'El carné de extranjería debe tener de 8 a 12 letras o dígitos.',
    'profile.document_number_required': 'Ingresa el número de documento.',
    'profile.email_invalid': 'El correo no es válido.',
    'profile.email_required': 'Ingresa el correo.',
    'profile.first_name_required': 'Ingresa el nombre.',
    'profile.last_name_required': 'Ingresa el apellido.',
    'profile.phone_invalid': 'El teléfono no es válido.',
    'profile.phone_required': 'Ingresa el teléfono.',
    'profile.date_range_invalid': 'La fecha de fin debe ser posterior a la de inicio.',
    'staff.inactive': 'La ficha del colaborador está desactivada.',
    'staff.job_position_required': 'Indica el puesto.',
    'staff.job_position_length': 'El puesto es demasiado largo.',
    'staff.shift_invalid': 'Elige un turno habitual válido.',
    'staff.assignment_duplicated': 'Ya tiene esa asignación.',
    'staff.assignment_terminated': 'Esa asignación ya terminó.',
    'staff.assignment_already_terminated': 'Esa asignación ya terminó.',
    'staff.assignment_not_suspended': 'Solo se reactiva una asignación suspendida.',
    'staff.assignment_period_expired': 'El periodo de esa asignación ya venció.',
    'staff.termination_before_start': 'La fecha de término no puede ser anterior al inicio.',
    'staff.admin_conflicts_with_reception': 'No puede ser administrador y recepción en el mismo hotel.',
    'staff.reception_conflicts_with_admin': 'No puede ser recepción y administrador en el mismo hotel.',
    'staff.hotel_not_found': 'No encontramos el hotel de la asignación.',
    'iot.thermostat_invalid': 'Indica la temperatura y la velocidad del ventilador.',
    'rate_limit.exceeded': 'Demasiados intentos. Espera un momento y vuelve a intentarlo.',
    'service.unavailable': 'Un servicio del backend no responde. Inténtalo en un momento.',
  };
}
