import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Notification center; urgent ones stand out (US-22).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  /// Unread when the page opened: they stay highlighted while it is visible.
  late final Set<int> _unread;

  @override
  void initState() {
    super.initState();
    final store = HotelStore.instance;
    _unread = store.notifications.where((n) => n.userId == store.currentUser?.id && !n.read).map((n) => n.id).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = store.currentUser;
      if (mounted && user != null) store.markNotificationsRead(user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final list = store.notificationsFor(store.currentUser!.id);
      if (list.isEmpty) return const EmptyState(icon: Icons.notifications_none, message: 'No tienes notificaciones.');
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Configura qué recibir desde tu perfil.', style: TextStyle(color: kMuted)),
          for (final n in list) _tile(n, store, unread: _unread.contains(n.id) || !n.read),
        ],
      );
    });
  }

  Widget _tile(AppNotification n, HotelStore store, {required bool unread}) {
    final highlight = n.urgent && unread;
    return AppCard(
      color: highlight ? kError.withAlpha(16) : null,
      borderColor: highlight ? kError : (unread ? kPrimary : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(n.urgent ? Icons.priority_high : Icons.notifications_outlined, color: n.urgent ? kError : kPrimaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title, style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w600)),
                Text(n.body),
                Text(timeAgo(n.createdAt, store.now), style: const TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
