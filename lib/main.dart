import 'package:flutter/material.dart';

import 'core/hotel_store.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/shell/role_shell.dart';
import 'shared/ui.dart';

void main() {
  runApp(const RoomTrackApp());
}

class RoomTrackApp extends StatelessWidget {
  const RoomTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoomTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light),
        useMaterial3: true,
        scaffoldBackgroundColor: kSurface,
        textTheme: ThemeData.light().textTheme.apply(bodyColor: kSecondary, displayColor: kSecondary),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kSecondary,
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: kSurface,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kCardSurface,
          surfaceTintColor: kCardSurface,
          indicatorColor: kSoftGreen,
          height: 68,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(color: states.contains(WidgetState.selected) ? kSecondary : kMuted),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              color: states.contains(WidgetState.selected) ? kSecondary : kMuted,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        chipTheme: const ChipThemeData(backgroundColor: kCardSurface, selectedColor: kSoftGreen, side: BorderSide(color: kLine)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kPrimary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: kPrimary)),
      ),
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _restored;

  @override
  void initState() {
    super.initState();
    HotelStore.instance.startTicker();
    _restored = SessionStore.restore(HotelStore.instance).then((user) => user != null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _restored,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView(message: 'Preparando la operación del día...'));
        }
        return snapshot.data == true ? const RoleShell() : const LoginPage();
      },
    );
  }
}
