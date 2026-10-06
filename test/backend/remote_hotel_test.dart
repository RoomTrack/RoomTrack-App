import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roomtrack/core/backend/api_client.dart';
import 'package:roomtrack/core/backend/remote_hotel.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/domain/models.dart';

/// A fake gateway answering the routes the app uses, with the shapes of the real backend.
RemoteHotel fakeBackend({required Map<String, Object?> me, Map<String, Object?> signIn = const {}}) {
  final routes = <String, Object?>{
    'POST /authentication/sign-in': signIn,
    'GET /users/me': me,
    'GET /users': [
      {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'status': 'Active', 'hotelId': 1},
      {'id': 3, 'email': 'limpieza@roomtrack.pe', 'firstName': 'María', 'lastName': 'Quispe', 'role': 'housekeeping', 'status': 'Inactive', 'hotelId': 1},
    ],
    'GET /rooms': [
      {'id': 10, 'hotelId': 1, 'roomTypeId': 1, 'roomTypeName': 'Suite', 'price': 205, 'status': 'Occupied', 'number': '304'},
      {'id': 11, 'hotelId': 1, 'roomTypeId': 2, 'roomTypeName': 'Doble', 'price': 140, 'status': 'Cleaning', 'number': '201'},
      {'id': 12, 'hotelId': 2, 'roomTypeId': 2, 'roomTypeName': 'Doble', 'price': 140, 'status': 'Available', 'number': '101'},
    ],
    'GET /bookings': [
      {
        'id': 7, 'code': 'SS-AAAA1111', 'hotelId': 1, 'roomId': 10, 'roomNumber': '304', 'guestName': 'Sofía Herrera',
        'guestEmail': 'huesped@roomtrack.pe', 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-08T00:00:00',
        'nights': 3, 'pricePerNight': 205, 'totalPrice': 615, 'status': 'CheckedIn', 'createdAt': '2026-10-01T10:00:00Z',
        'checkedInAt': '2026-10-05T15:10:00Z', 'userId': 6,
      },
      {
        'id': 8, 'code': 'SS-BBBB2222', 'hotelId': 1, 'roomId': 11, 'roomNumber': '201', 'guestName': 'Andrés Molina',
        'guestEmail': 'huesped2@roomtrack.pe', 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-06T00:00:00',
        'nights': 1, 'pricePerNight': 140, 'totalPrice': 140, 'status': 'Pending', 'createdAt': '2026-10-02T10:00:00Z',
        'paymentDueAt': '2026-10-06T10:00:00Z', 'userId': 8,
      },
      {'id': 9, 'status': 'Cancelled', 'roomId': 11, 'checkInDate': '2026-10-05T00:00:00', 'checkOutDate': '2026-10-06T00:00:00', 'totalPrice': 1},
    ],
    'GET /payments/booking/7': {
      'id': 70, 'bookingId': 7, 'transactionId': 'YAPE-1', 'amount': 615, 'status': 'Completed', 'method': 'Yape',
      'paymentDate': '2026-10-01 10:05:00',
    },
    'GET /bookings/7/check-in': {'accessCode': '304911'},
  };
  final client = MockClient((request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^.*?(?=/[a-z])'), '');
    final key = '${request.method} $path';
    if (!routes.containsKey(key)) return http.Response(jsonEncode({'title': 'Not found', 'status': 404}), 404);
    return http.Response(jsonEncode(routes[key]), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final store = HotelStore(seed: false);
  final remote = RemoteHotel(store, ApiClient(client: client));
  store.remote = remote;
  return remote;
}

void main() {
  test('el personal con autenticador pide el código de 6 dígitos', () async {
    final remote = fakeBackend(
      me: const {},
      signIn: {'id': 1, 'email': 'admin@roomtrack.pe', 'token': null, 'mfaRequired': true, 'mfaToken': 'mfa-token'},
    );
    final outcome = await remote.signIn('admin@roomtrack.pe', 'x');
    expect(outcome, isA<MfaCodeNeeded>().having((o) => o.mfaToken, 'mfaToken', 'mfa-token'));
  });

  test('el administrador sincroniza su hotel: habitaciones, personal, reservas y pagos', () async {
    final remote = fakeBackend(
      me: {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': 'admin', 'hotelId': 1},
      signIn: {'id': 1, 'token': 'access', 'refreshToken': 'refresh'},
    );
    final outcome = await remote.signIn('admin@roomtrack.pe', 'x');
    final store = remote.store;

    expect(outcome, isA<SignedIn>());
    expect(store.currentUser!.name, 'Ana Torres');
    // Only the rooms of the admin's hotel; Cleaning is shown as pending cleaning.
    expect(store.rooms.map((r) => r.number), ['201', '304']);
    expect(store.rooms.firstWhere((r) => r.number == '201').status, RoomStatus.dirty);
    expect(store.rooms.firstWhere((r) => r.number == '304').type, RoomType.suite);
    expect(store.users.firstWhere((u) => u.id == 3).active, isFalse);

    // Cancelled bookings disappear; Pending ones wait for the front desk to register the payment.
    expect(store.stays.map((s) => s.id), [7, 8]);
    final sofia = store.stayById(7);
    expect(sofia.status, StayStatus.checkedIn);
    expect(sofia.code, 'SS-AAAA1111');
    expect(store.totalCharges(sofia), 615);
    expect(store.balanceOf(sofia), 0);
    expect(store.stayById(8).awaitingPayment, isTrue);
    expect(store.payments.single.method, 'Yape');
  });

  test('el huésped recibe su código de acceso', () async {
    final remote = fakeBackend(
      me: {'id': 6, 'email': 'huesped@roomtrack.pe', 'firstName': 'Sofía', 'lastName': 'Herrera', 'role': 'guest', 'hotelId': null},
      signIn: {'id': 6, 'token': 'access'},
    );
    await remote.signIn('huesped@roomtrack.pe', 'x');
    final stay = remote.store.activeStayOf(6)!;
    expect(stay.accessCode, '304911');
  });

  test('los errores del backend llegan en español', () {
    final error = ApiClient.problem(401, jsonEncode({'title': 'Invalid credentials', 'code': 'mfa.code_already_used'}));
    expect(error.message, 'Ese código ya se usó. Espera el siguiente de tu app autenticadora.');
    final validation = ApiClient.problem(400, jsonEncode({'errors': {'email': ['El correo no es válido.']}}));
    expect(validation.message, 'El correo no es válido.');
  });
}
