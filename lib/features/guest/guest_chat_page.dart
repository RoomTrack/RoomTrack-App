import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../shared/ui.dart';
import '../messages/chat_view.dart';

/// Direct chat with reception during the stay (US-20).
class GuestChatPage extends StatelessWidget {
  const GuestChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HotelStore.instance;
    final stay = store.activeStayOf(store.currentUser!.id);
    if (stay == null) return const EmptyState(icon: Icons.chat_bubble_outline, message: 'El chat se habilita cuando tienes una reserva.');
    return ChatView(
      channel: HotelStore.guestChannel(stay.id),
      emptyMessage: 'Escríbenos, recepción te responderá aquí mismo.',
    );
  }
}
