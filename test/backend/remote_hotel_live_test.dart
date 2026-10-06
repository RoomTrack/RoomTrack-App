// End-to-end check of the app against a local backend seeded by tool/seed_backend.py:
//
//   flutter test test/backend/remote_hotel_live_test.dart --dart-define=API_BASE_URL=http://localhost:8080/api/v1
//
// Without API_BASE_URL every test is skipped.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/backend/api_client.dart';
import 'package:roomtrack/core/backend/remote_hotel.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/domain/models.dart';

/// RFC 6238 code of a Base32 secret, as an authenticator app shows it.
String totp(String secret, {DateTime? at}) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bits = secret.toUpperCase().replaceAll('=', '').split('').map((c) => alphabet.indexOf(c).toRadixString(2).padLeft(5, '0')).join();
  final key = Uint8List.fromList([for (var i = 0; i + 8 <= bits.length; i += 8) int.parse(bits.substring(i, i + 8), radix: 2)]);
  final counter = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final message = ByteData(8)..setInt64(0, counter);
  final digest = Hmac(sha1, key).convert(message.buffer.asUint8List()).bytes;
  final offset = digest.last & 0x0f;
  final value = ((digest[offset] & 0x7f) << 24) | (digest[offset + 1] << 16) | (digest[offset + 2] << 8) | digest[offset + 3];
  return (value % 1000000).toString().padLeft(6, '0');
}

/// A 1×1 PNG: enough for the backend's document upload.
final Uint8List tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Future<RemoteHotel> signedIn(String email, String password) async {
  final store = HotelStore(seed: false);
  final remote = RemoteHotel(store, ApiClient());
  store.remote = remote;
  var outcome = await remote.signIn(email, password);
  if (outcome is MfaCodeNeeded) {
    final accounts = jsonDecode(File('tool/demo_accounts.local.json').readAsStringSync())['accounts'] as Map<String, dynamic>;
    final secret = (accounts[email] as Map<String, dynamic>)['mfaSecret'] as String;
    try {
      await remote.verifyMfa(outcome.mfaToken, code: totp(secret));
    } on ApiException catch (e) {
      if (e.code != 'mfa.code_already_used') rethrow;
      // A code works once: wait for the next window.
      await Future<void>.delayed(Duration(seconds: 31 - DateTime.now().second % 30));
      outcome = await remote.signIn(email, password);
      await remote.verifyMfa((outcome as MfaCodeNeeded).mfaToken, code: totp(secret));
    }
  }
  return remote;
}

void main() {
  final skip = backendEnabled ? false : 'Sin --dart-define=API_BASE_URL';

  test('credenciales inválidas llegan en español', () async {
    final remote = RemoteHotel(HotelStore(seed: false), ApiClient());
    await expectLater(
      remote.signIn('admin@roomtrack.pe', 'incorrecta-123456'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Correo o contraseña incorrectos.')),
    );
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('el personal sin autenticador debe activarlo (MFA)', () async {
    final remote = RemoteHotel(HotelStore(seed: false), ApiClient());
    final outcome = await remote.signIn('limpieza@roomtrack.pe', kRemoteStaffPassword);
    expect(outcome, isA<MfaEnrollmentNeeded>());
    final enrollment = await remote.startMfaEnrollment((outcome as MfaEnrollmentNeeded).mfaToken);
    expect(enrollment.otpAuthUri, startsWith('otpauth://totp/'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('el administrador ve habitaciones, personal y cambia estados', () async {
    final remote = await signedIn('admin@roomtrack.pe', kRemoteStaffPassword);
    final store = remote.store;
    expect(store.currentUser!.role, UserRole.admin);
    expect(store.rooms, hasLength(12));
    expect(store.users.map((u) => u.email), containsAll(['recepcion@roomtrack.pe', 'limpieza@roomtrack.pe']));

    final room = store.rooms.firstWhere((r) => r.number == '102');
    await remote.changeRoomStatus(room, RoomStatus.maintenance);
    expect(store.rooms.firstWhere((r) => r.number == '102').status, RoomStatus.maintenance);
    final history = await remote.roomStatusHistory(room.id);
    expect(history.first.to, RoomStatus.maintenance.label);
    await remote.changeRoomStatus(store.rooms.firstWhere((r) => r.number == '102'), RoomStatus.available);

    final metrics = await remote.monthlyMetrics();
    expect(metrics.bookings, greaterThanOrEqualTo(1));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('recepción confirma el pago y el huésped hace su check-in digital', () async {
    final admin = await signedIn('admin@roomtrack.pe', kRemoteStaffPassword);
    final pending = admin.store.stays.where((s) => s.guestEmail == 'huesped2@roomtrack.pe').single;
    if (pending.awaitingPayment) {
      await admin.registerPayment(pending.id, method: 'Cash');
    }
    expect(admin.store.stayById(pending.id).awaitingPayment, isFalse);

    final guest = await signedIn('huesped@roomtrack.pe', kRemoteGuestPassword);
    final stay = guest.store.activeStayOf(guest.store.currentUser!.id)!;
    expect(guest.store.roomById(stay.roomId!).number, '304');
    if (stay.status == StayStatus.reserved) {
      final code = await guest.completeCheckIn(stay.id,
          documentType: 'DNI', documentNumber: '70123456', nationality: 'PE', document: tinyPng, fileName: 'dni.png');
      expect(code, hasLength(6));
    }
    expect(guest.store.stayById(stay.id).status, StayStatus.checkedIn);
    expect(guest.store.roomById(stay.roomId!).status, RoomStatus.occupied);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
