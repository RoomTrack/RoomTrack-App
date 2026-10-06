import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/api_client.dart';
import '../../core/hotel_store.dart';
import '../../core/permissions.dart';
import '../../core/seed.dart';
import '../../core/session.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';
import '../auth/login_page.dart';
import 'feature_registry.dart';

/// Home of the signed-in user: tabs and permissions follow the current role (US-01, US-03).
class RoleShell extends StatefulWidget {
  const RoleShell({super.key});

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  final HotelStore _store = HotelStore.instance;
  int _index = 0;
  int _lastNotificationId = 0;
  UserRole? _role;
  bool _leaving = false;
  Timer? _sync;

  @override
  void initState() {
    super.initState();
    final user = _store.currentUser;
    if (user != null) {
      _role = user.role;
      final mine = _store.notificationsFor(user.id);
      _lastNotificationId = mine.isEmpty ? 0 : mine.map((n) => n.id).reduce((a, b) => a > b ? a : b);
    }
    _store.addListener(_onStoreChanged);
    // With the backend, other devices change rooms and bookings: pull them regularly.
    if (_store.isRemote) _sync = Timer.periodic(const Duration(seconds: 20), (_) => _pull());
  }

  @override
  void dispose() {
    _sync?.cancel();
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> _pull() async {
    try {
      await _store.remote!.sync();
    } on ApiException catch (e) {
      // A revoked session (deactivated account, role change) or an expired one ends here.
      if (e.statusCode == 401 && mounted) {
        showAppSnack(context, e.message, error: true);
        await _store.remote!.signOut();
      }
    }
  }

  void _onStoreChanged() {
    final user = _store.currentUser;
    if (user == null || !user.active) {
      if (user != null) showAppSnack(context, 'Tu cuenta fue desactivada.', error: true);
      _signOut();
      return;
    }
    if (user.role != _role) {
      // A role change adjusts the permissions on the spot.
      setState(() {
        _role = user.role;
        _index = 0;
      });
    }
    // In-app banner standing in for a push notification (US-22).
    final fresh = _store.notifications.where((n) => n.userId == user.id && n.id > _lastNotificationId).toList();
    if (fresh.isNotEmpty) {
      _lastNotificationId = fresh.map((n) => n.id).reduce((a, b) => a > b ? a : b);
      final latest = fresh.last;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: latest.urgent ? kError : kSecondary,
          content: Text('${latest.title}\n${latest.body}'),
          action: SnackBarAction(label: 'Ver', textColor: Colors.white, onPressed: _openNotifications),
        ));
      }
    }
  }

  Future<void> _signOut() async {
    if (_leaving) return;
    _leaving = true;
    _store.signOut();
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  void _openNotifications() {
    final info = featureInfo[Feature.notifications]!;
    openPage(context, Feature.notifications, FeaturePage(feature: Feature.notifications, child: info.builder()));
  }

  @override
  Widget build(BuildContext context) {
    final user = _store.currentUser;
    if (user == null) return const Scaffold(body: LoadingView());
    final tabs = roleTabs[user.role]!;
    final hasMore = user.role != UserRole.guest;
    final pageCount = tabs.length + (hasMore ? 1 : 0);
    final index = _index.clamp(0, pageCount - 1);
    final isMore = hasMore && index == tabs.length;
    final feature = isMore ? null : tabs[index];
    final info = feature == null ? null : featureInfo[feature]!;
    final (title, subtitle) = switch (feature) {
      null => ('Más', 'Todo lo demás que puedes hacer.'),
      Feature.guestHome => ('Hola, ${user.firstName}', 'Te damos la bienvenida a $kHotelName.'),
      _ => (info!.title, info.subtitle),
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const RoomTrackLogo(size: 34, withName: true),
        actions: [
          NotificationBell(onTap: _openNotifications),
          const SizedBox(width: 16),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: kLine)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          PageHeader(title: title, subtitle: subtitle),
          Expanded(
            child: isMore ? MorePage(role: user.role) : KeyedSubtree(key: ValueKey(feature), child: info!.builder()),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => _index = value),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final f in tabs) NavigationDestination(icon: Icon(featureInfo[f]!.icon), label: featureInfo[f]!.title),
            if (hasMore) const NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
          ],
        ),
      ),
    );
  }
}

class NotificationBell extends StatelessWidget {
  final VoidCallback onTap;

  const NotificationBell({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final count = store.currentUser == null ? 0 : store.unreadCount(store.currentUser!.id);
      return CircleIconButton(
        tooltip: 'Notificaciones',
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.notifications_none, color: kSecondary),
        ),
      );
    });
  }
}

/// A feature opened on its own route, with the same app bar as the tabs.
class FeaturePage extends StatelessWidget {
  final Feature feature;
  final Widget child;

  const FeaturePage({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(featureInfo[feature]!.title, style: const TextStyle(fontFamily: kSerif, fontSize: 24))),
      body: child,
    );
  }
}

/// Opens any feature, enforcing the role permissions.
Future<void> openFeature(BuildContext context, Feature feature) {
  return openPage(context, feature, FeaturePage(feature: feature, child: featureInfo[feature]!.builder()));
}

class MorePage extends StatelessWidget {
  final UserRole role;

  const MorePage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final features = moreFeatures(role);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final feature in features)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => openFeature(context, feature),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(featureInfo[feature]!.icon, color: kPrimaryDark),
              title: Text(featureInfo[feature]!.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        if (!canAccess(role, Feature.staffAdmin)) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            // Lets the role restriction be checked in a demo (US-01, escenario 3).
            onPressed: () => openFeature(context, Feature.staffAdmin),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Intentar abrir administración de personal'),
          ),
        ],
      ],
    );
  }
}
