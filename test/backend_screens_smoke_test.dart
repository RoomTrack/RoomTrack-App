import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roomtrack/core/backend/api_client.dart';
import 'package:roomtrack/core/backend/remote_hotel.dart';
import 'package:roomtrack/core/hotel_store.dart';
import 'package:roomtrack/core/seed.dart';
import 'package:roomtrack/domain/models.dart';
import 'package:roomtrack/features/admin/audit_log_page.dart';
import 'package:roomtrack/features/admin/checklists_page.dart';
import 'package:roomtrack/features/admin/hotel_setup_page.dart';
import 'package:roomtrack/features/front_desk/remote_booking_sheets.dart';
import 'package:roomtrack/features/front_desk/stay_detail_page.dart';
import 'package:roomtrack/features/payments/payments_page.dart';
import 'package:roomtrack/features/profiles/guest_profile_sheet.dart';
import 'package:roomtrack/features/profiles/staff_profile_page.dart';
import 'package:roomtrack/features/rooms/availability_page.dart';
import 'package:roomtrack/features/rooms/room_detail_page.dart';

/// Answers of a fake gateway for the screens that read the backend when they open.
final List<(RegExp, Object?)> _routes = [
  (RegExp(r'^GET /hotels/1$'), {
    'id': 1, 'hostId': 1, 'name': 'Casa Andina', 'location': 'Av. El Sol 954, Cusco, Perú', 'imageUrl': '', 'description': 'Boutique',
    'basePrice': 120, 'type': 'Boutique', 'amenities': ['Wifi'], 'acceptsBookings': true,
  }),
  (RegExp(r'^GET /room-types$'), [{'id': 1, 'name': 'Suite', 'description': 'Amplia'}, {'id': 2, 'name': 'Doble', 'description': ''}]),
  (RegExp(r'^GET /accommodations/options/\w+$'), ['Wifi', 'Boutique']),
  (RegExp(r'^GET /cleaning-tasks/checklists$'), [
    {'hotelId': 1, 'roomTypeId': null, 'isStandard': true, 'items': [{'position': 1, 'label': 'Cambiar sábanas', 'isRequired': true}]},
  ]),
  (RegExp(r'^GET /audit-logs$'), {
    'items': [
      {'id': 1, 'occurredAt': '2026-11-25T08:00:00Z', 'action': 'RoleChanged', 'outcome': 'Success', 'actorEmail': 'admin@roomtrack.pe',
        'targetEmail': 'limpieza@roomtrack.pe', 'ipAddress': '10.0.0.1'},
    ],
    'page': 1, 'pageSize': 30, 'totalCount': 1, 'totalPages': 1,
  }),
  (RegExp(r'^GET /staff/user/\d+$'), {
    'id': 'a1', 'userId': 3, 'code': 'EMP-0003', 'firstName': 'María', 'lastName': 'Quispe', 'email': 'm@roomtrack.pe', 'phone': '987654321',
    'position': 'Camarera', 'shift': 'Morning', 'documentType': 0, 'documentNumber': '45678912', 'status': 'Active',
    'assignments': [{'id': 'b1', 'scope': 'Hotel', 'targetId': 1, 'role': 'Housekeeping', 'startDate': '2026-11-01', 'endDate': null, 'status': 'Active'}],
  }),
  (RegExp(r'^GET /rooms/\d+/status-history$'), const []),
  (RegExp(r'^GET /rooms/\d+/maintenance-history$'), {
    'roomId': 202, 'correctiveCount': 2, 'preventiveCount': 1, 'recurringCount': 0, 'incidents': const [],
    'preventivePlans': [{'title': 'Revisar aire', 'frequencyDays': 30, 'nextDueOn': '2026-12-10', 'isActive': true}],
  }),
  (RegExp(r'^GET /io-t-emulator/rooms/\d+/actuators-state$'), {
    'roomId': 202, 'currentTemperature': 22.0, 'motionDetected': true, 'lastCommandReceived': 'INITIALIZE_SYSTEM',
    'hardwareStatus': 'OPERATIONAL_EMULATED', 'timestamp': '2026-11-25T10:00:00Z',
  }),
  (RegExp(r'^GET /bookings/room/\d+$'), [
    {'id': 90, 'code': 'RT-1', 'guestName': 'Sofía Herrera', 'checkInDate': '2030-01-01T00:00:00', 'checkOutDate': '2030-01-03T00:00:00', 'status': 'Confirmed'},
  ]),
  (RegExp(r'^GET /rooms/available$'), [
    {'id': 202, 'roomTypeName': 'Suite', 'pricePerNight': 205, 'nights': 1, 'totalPrice': 205, 'status': 'Available', 'number': '202'},
  ]),
  (RegExp(r'^GET /payments/history$'), [
    {'occurredAt': '2026-11-26T15:00:00Z', 'type': 'FolioPayment', 'bookingId': 1, 'amount': 30.0, 'method': 'Yape', 'reference': 'OP-1', 'receiptId': 5},
  ]),
];

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('las pantallas que leen el backend se construyen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = HotelStore.instance;
    store.signIn('admin@roomtrack.com', kDemoPassword);
    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst(RegExp(r'^.*?(?=/[a-z])'), '');
      for (final (pattern, body) in _routes) {
        if (pattern.hasMatch('${request.method} $path')) {
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }
      }
      return http.Response(jsonEncode({'status': 404}), 404);
    });
    store.remote = RemoteHotel(store, ApiClient(client: client))..me = {'id': store.currentUser!.id, 'hotelId': 1, 'role': 'admin'};
    addTearDown(() => store.remote = null);

    final housekeeper = store.users.firstWhere((u) => u.role == UserRole.housekeeping);
    final stay = store.stays.firstWhere((s) => s.status == StayStatus.reserved);
    final pages = <String, Widget>{
      'hotel': const Scaffold(body: HotelSetupPage()),
      'protocolos': const ChecklistsPage(),
      'auditoría': const Scaffold(body: AuditLogPage()),
      'ficha de personal': StaffProfilePage(user: housekeeper),
      'habitación': const RoomDetailPage(roomId: 202),
      'disponibilidad': const Scaffold(body: AvailabilityPage()),
      'pagos': const Scaffold(body: PaymentsPage()),
      'reserva': StayDetailPage(stayId: stay.id),
      'ficha del huésped': Scaffold(
        body: GuestProfileEditor(name: stay.guestName, email: stay.guestEmail, load: () async => null),
      ),
    };
    for (final entry in pages.entries) {
      await tester.pumpWidget(MaterialApp(home: entry.value));
      await tester.pumpAndSettle();
      // An overflowing row names the widget that created it.
      final overflowing = tester.allRenderObjects
          .whereType<RenderFlex>()
          .where((r) => r.toStringShort().contains('OVERFLOWING'))
          .map((r) => (r.debugCreator! as DebugCreator).element.debugGetCreatorChain(12));
      expect(tester.takeException(), isNull, reason: '${entry.key}: ${overflowing.join('\n')}');
    }

    // The front desk sheets of a booking.
    for (final open in [showAssistedCheckInSheet, showRescheduleSheet]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => open(context, stay), child: const Text('abrir')))),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // The room's bookings and the maintenance summary came from the backend.
    await tester.pumpWidget(const MaterialApp(home: RoomDetailPage(roomId: 202)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Revisar aire · cada 30 días · próximo 10/12/2026'), 300);
    expect(find.text('Sofía Herrera'), findsOneWidget);
    expect(find.text('22.0 °C'), findsOneWidget);
  });
}
