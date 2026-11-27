import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roomtrack/core/backend/api_client.dart';
import 'package:roomtrack/core/backend/remote_hotel.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/features/admin/hotel_setup_page.dart';
import 'package:roomtrack/features/shell/role_shell.dart';

/// Signs in an administrator without a hotel ([role] `admin` or `chain_admin`) against a fake gateway.
Future<RemoteHotel> _adminWithoutHotel(String role) async {
  final routes = <String, Object?>{
    'POST /authentication/sign-in': {'id': 1, 'token': 'access', 'refreshToken': 'refresh'},
    'GET /users/me': {'id': 1, 'email': 'admin@roomtrack.pe', 'firstName': 'Ana', 'lastName': 'Torres', 'role': role, 'hotelId': null},
    'GET /hotels': [
      {'id': 1, 'name': 'Casa Aurora', 'location': 'Av. Larco 1150, Lima, Perú', 'imageUrl': '', 'acceptsBookings': true},
      {'id': 2, 'name': 'Wasi Cusco', 'location': 'Calle Plateros 3, Cusco, Perú', 'imageUrl': '', 'acceptsBookings': false},
    ],
    'GET /rooms': const [],
    'GET /bookings': const [],
    'GET /users': const [],
    'GET /accommodations/options/categories': ['Hotel', 'Boutique'],
    'GET /accommodations/options/amenities': ['Wifi'],
  };
  final client = MockClient((request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^.*?(?=/[a-z])'), '');
    final body = routes['${request.method} $path'];
    if (body == null) return http.Response(jsonEncode({'title': 'Not found', 'status': 404}), 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final store = HotelStore.instance;
  final remote = RemoteHotel(store, ApiClient(client: client));
  store.remote = remote;
  await remote.signIn('admin@roomtrack.pe', 'x');
  return remote;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    HotelStore.instance.remote = null;
    HotelStore.instance.signOut();
  });

  testWidgets('un administrador sin hotel ve cómo registrar el suyo', (tester) async {
    await tester.runAsync(() => _adminWithoutHotel('admin'));
    await tester.pumpWidget(const MaterialApp(home: RoleShell()));
    await tester.pump();

    expect(find.text('Registra tu hotel'), findsOneWidget);
    expect(find.text('Registrar mi hotel'), findsOneWidget);

    await tester.tap(find.text('Registrar mi hotel'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(HotelForm), findsOneWidget);
    expect(find.text('Registrar hotel'), findsOneWidget);
  });

  testWidgets('el administrador de cadena elige un hotel y puede volver a la lista', (tester) async {
    final remote = await tester.runAsync(() => _adminWithoutHotel('chain_admin'));
    await tester.pumpWidget(const MaterialApp(home: RoleShell()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Hoteles de la cadena'), findsOneWidget);
    expect(find.text('Casa Aurora'), findsOneWidget);
    expect(find.text('Wasi Cusco'), findsOneWidget);

    await tester.runAsync(() => remote!.chooseHotel(const ChainHotel(2, 'Wasi Cusco')));
    await tester.pump();
    expect(find.text('Hoteles de la cadena'), findsNothing);
    expect(find.text('Cambiar de hotel'), findsOneWidget);
    expect(find.text('Wasi Cusco'), findsOneWidget);

    await tester.tap(find.text('Cambiar de hotel'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Hoteles de la cadena'), findsOneWidget);
  });
}
