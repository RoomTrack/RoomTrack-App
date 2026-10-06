import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/features/auth/login_page.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('el administrador inicia sesión y ve su panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.tap(find.text('Administrador'));
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(HotelStore.instance.currentUser?.email, 'admin@roomtrack.com');
    expect(find.text('Operación de hoy'), findsOneWidget);
    expect(find.text('Analítica'), findsOneWidget);
  });

  testWidgets('credenciales inválidas muestran un error genérico', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.enterText(find.byKey(const Key('login-email')), 'admin@roomtrack.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'incorrecta');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });
}
