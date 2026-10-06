import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Conversation of one channel: a task, an area or a guest's stay.
class ChatView extends StatefulWidget {
  final String channel;
  final String emptyMessage;

  const ChatView({super.key, required this.channel, this.emptyMessage = 'Aún no hay mensajes.'});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final me = store.currentUser!;
      final messages = store.messagesIn(widget.channel).reversed.toList();
      return Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? EmptyState(icon: Icons.chat_bubble_outline, message: widget.emptyMessage)
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = message.authorId == me.id;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine ? kPrimary : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: mine ? null : Border.all(color: kLine),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Text(message.authorName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: kPrimaryDark)),
                              Text(message.text, style: TextStyle(color: mine ? Colors.white : kSecondary)),
                              const SizedBox(height: 2),
                              Text(
                                timeAgo(message.createdAt, store.now),
                                style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : kMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Escribe un mensaje...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  void _send() {
    final store = HotelStore.instance;
    store.sendMessage(widget.channel, store.currentUser!, _text.text);
    _text.clear();
  }
}
