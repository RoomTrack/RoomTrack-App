import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import 'chat_view.dart';

/// Area channels, task conversations and guest chats in one place (US-12, US-20).
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final user = store.currentUser!;
      final myArea = user.role.area;
      final areas = myArea == null || user.role == UserRole.reception ? Area.values : [myArea];
      final taskChannels = store.messages
          .where((m) => m.channel.startsWith('task:'))
          .map((m) => m.channel)
          .toSet()
          .where((channel) {
        final task = store.taskById(int.parse(channel.split(':')[1]));
        return user.role == UserRole.admin ||
            user.role == UserRole.reception ||
            task.assigneeId == user.id ||
            store.messagesIn(channel).any((m) => m.authorId == user.id);
      }).toList();
      final guestChannels = user.role == UserRole.admin || user.role == UserRole.reception
          ? store.messages.where((m) => m.channel.startsWith('guest:')).map((m) => m.channel).toSet().toList()
          : <String>[];

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader(title: 'Canales de área', subtitle: 'Todos los miembros del área reciben el mensaje.'),
          for (final area in areas)
            _ChannelTile(
              icon: area.icon,
              title: 'Canal ${area.label}',
              channel: HotelStore.areaChannel(area),
              store: store,
            ),
          if (guestChannels.isNotEmpty) ...[
            const SectionHeader(title: 'Huéspedes'),
            for (final channel in guestChannels)
              _ChannelTile(
                icon: Icons.person_outline,
                title: store.stayById(int.parse(channel.split(':')[1])).guestName,
                channel: channel,
                store: store,
              ),
          ],
          const SectionHeader(title: 'Conversaciones por tarea'),
          if (taskChannels.isEmpty) const EmptyState(message: 'Comenta una tarea desde su detalle para coordinar.'),
          for (final channel in taskChannels)
            _ChannelTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Limpieza hab. ${store.roomById(store.taskById(int.parse(channel.split(':')[1])).roomId).number}',
              channel: channel,
              store: store,
            ),
        ],
      );
    });
  }
}

class _ChannelTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String channel;
  final HotelStore store;

  const _ChannelTile({required this.icon, required this.title, required this.channel, required this.store});

  @override
  Widget build(BuildContext context) {
    final last = store.messagesIn(channel).lastOrNull;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
            body: ChatView(channel: channel),
          ),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(backgroundColor: kSoftGreen, child: Icon(icon, color: kPrimaryDark)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(last == null ? 'Sin mensajes' : '${last.authorName.split(' ').first}: ${last.text}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: last == null ? null : Text(timeAgo(last.createdAt, store.now), style: const TextStyle(color: kMuted, fontSize: 12)),
      ),
    );
  }
}
