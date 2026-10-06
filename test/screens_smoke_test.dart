import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/core/seed.dart';
import 'package:roomtrack/domain/models.dart';
import 'package:roomtrack/features/front_desk/stay_detail_page.dart';
import 'package:roomtrack/features/guest/my_stay_page.dart';
import 'package:roomtrack/features/guest/services_page.dart';
import 'package:roomtrack/features/housekeeping/task_detail_page.dart';
import 'package:roomtrack/features/incidents/incident_detail_page.dart';
import 'package:roomtrack/features/rooms/room_detail_page.dart';
import 'package:roomtrack/features/shell/feature_registry.dart';
import 'package:roomtrack/features/shell/role_shell.dart';

/// Opens every tab and every "Más" entry of every role, failing on any layout or build error.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final account in kDemoAccounts) {
    testWidgets('todas las pantallas de ${account.label} se construyen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = HotelStore.instance;
      store.signIn(account.email, kDemoPassword);

      await tester.pumpWidget(const MaterialApp(home: RoleShell()));
      await tester.pump();

      final tabs = roleTabs[account.role]!;
      for (final feature in tabs) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(featureInfo[feature]!.title)));
        await tester.pump(const Duration(milliseconds: 300));
        _expectNoError(tester, 'pestaña ${feature.name}');
      }

      for (final feature in moreFeatures(account.role)) {
        final context = tester.element(find.byType(RoleShell));
        openFeature(context, feature);
        await tester.pump(const Duration(milliseconds: 400));
        _expectNoError(tester, 'pantalla ${feature.name}');
        Navigator.of(context).pop();
        await tester.pump(const Duration(milliseconds: 400));
      }

      store.signOut();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('las pantallas de detalle se construyen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = HotelStore.instance;
    store.signIn('admin@roomtrack.com', kDemoPassword);
    final pages = <Widget>[
      const RoomDetailPage(roomId: 202),
      TaskDetailPage(taskId: store.openTasks.first.id),
      IncidentDetailPage(incidentId: store.openIncidents.first.id),
      StayDetailPage(stayId: store.inHouse.first.id),
    ];
    for (final page in pages) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump(const Duration(milliseconds: 300));
      _expectNoError(tester, page.runtimeType.toString());
    }
    store.signOut();
  });

  testWidgets('mi estadía coincide con el mockup y cambia tras el check-out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = HotelStore.instance;
    final guest = store.signIn('huesped@roomtrack.com', kDemoPassword);
    final stay = store.activeStayOf(guest.id)!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MyStayPage())));
    await tester.pump();
    // Mockup "Mi estadía": hotel, Suite 304, 2 guests, account summary and the two actions.
    expect(find.text(kHotelName), findsOneWidget);
    expect(find.text('Suite 304'), findsOneWidget);
    expect(find.text('2 huéspedes'), findsOneWidget);
    expect(find.text('Hospedada'), findsOneWidget);
    expect(find.text('Resumen de cuenta'), findsOneWidget);
    expect(find.text(r'$724.00'), findsOneWidget);
    expect(find.text('Extender estadía'), findsOneWidget);
    expect(find.text('Llave digital'), findsOneWidget);

    store.payBalance(stay.id, [(amount: store.balanceOf(stay), card: null)]);
    store.checkOut(stay.id);
    await tester.pump();
    expect(find.text('¿Cómo fue tu estancia?'), findsOneWidget);
    expect(stay.status, StayStatus.checkedOut);
    store.signOut();
  });

  testWidgets('servicios muestra las categorías del mockup y filtra', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    HotelStore.instance.signIn('huesped@roomtrack.com', kDemoPassword);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ServicesPage())));
    for (final name in ['Limpieza', 'Toallas extra', 'Amenidades', 'Lavandería', 'Comida y bebida', 'Reportar un problema', 'Salida tardía', 'Conserjería']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('¿Necesitas algo ahora?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'lava');
    await tester.pump();
    expect(find.text('Lavandería'), findsOneWidget);
    expect(find.text('Conserjería'), findsNothing);
    HotelStore.instance.signOut();
  });
}

/// Fails with the full Flutter diagnostics (which widget overflowed and where).
void _expectNoError(WidgetTester tester, String screen) {
  final error = tester.takeException();
  final details = error is FlutterError ? error.toStringDeep() : '$error';
  expect(error, isNull, reason: '$screen: $details');
}
