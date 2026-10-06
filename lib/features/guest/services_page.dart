import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Service catalog laid out as the "Servicios" mockup (US-19, US-33).
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final query = _search.text.trim().toLowerCase();
      final services = store.services
          .where((s) => query.isEmpty || s.name.toLowerCase().contains(query) || s.description.toLowerCase().contains(query))
          .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Buscar servicios',
              prefixIcon: Icon(Icons.search, color: kMuted),
              fillColor: kCardSurface,
            ),
          ),
          const SizedBox(height: 16),
          if (services.isEmpty) const EmptyState(icon: Icons.search_off, message: 'No encontramos ese servicio.'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.75,
            children: [
              for (final service in services) _ServiceTile(service: service, onTap: () => _openService(context, store, service)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kSoftGreen, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Expanded(child: Text('¿Necesitas algo ahora?', style: TextStyle(fontFamily: kSerif, fontSize: 20, color: kSecondary))),
                    Icon(Icons.notifications_active_outlined, color: kGold),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => showCreateRequestSheet(context, store),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Crear solicitud', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// Detail with description, price and availability before ordering (US-33).
  Future<void> _openService(BuildContext context, HotelStore store, ServiceItem service) async {
    final stay = store.activeStayOf(store.currentUser!.id);
    final canOrder = service.available && stay != null && stay.status == StayStatus.checkedIn;
    final order = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: kCardSurface,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(service.icon, color: kGold, size: 28),
                const SizedBox(width: 12),
                Expanded(child: Text(service.name, style: const TextStyle(fontFamily: kSerif, fontSize: 24))),
              ],
            ),
            const SizedBox(height: 10),
            Text(service.description, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Pill(text: service.price == 0 ? 'Sin costo' : '${money(service.price)} a tu cuenta', color: kPrimary),
                Pill(text: service.available ? 'Disponible' : 'No disponible', color: service.available ? kSuccess : kMuted),
                Pill(text: 'Atiende ${service.area.label} · ~${service.area.etaMinutes} min', color: kGold),
              ],
            ),
            if (!canOrder && service.available) ...[
              const SizedBox(height: 12),
              const Text('Podrás pedir servicios cuando completes tu check-in.', style: TextStyle(color: kWarning)),
            ],
            const SizedBox(height: 20),
            AppButton(
              text: 'Solicitar',
              icon: Icons.check,
              onPressed: canOrder ? () => Navigator.pop(sheetContext, true) : null,
            ),
          ],
        ),
      ),
    );
    if (order != true || !context.mounted || stay == null) return;
    runAction(
      context,
      () => store.requestService(stay.id, service.id),
      success: 'Solicitud enviada a ${service.area.label}. Tiempo estimado: ${service.area.etaMinutes} min.',
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final ServiceItem service;
  final VoidCallback onTap;

  const _ServiceTile({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kLine)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(service.icon, color: service.available ? kSecondary : kMuted, size: 24),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: kGold, size: 20),
                ],
              ),
              const Spacer(),
              Text(
                service.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: service.available ? kSecondary : kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Free-text request that reaches reception first (US-19).
Future<void> showCreateRequestSheet(BuildContext context, HotelStore store) async {
  final user = store.currentUser!;
  final stay = store.activeStayOf(user.id);
  if (stay == null || stay.status != StayStatus.checkedIn) {
    showAppSnack(context, 'Podrás enviar solicitudes durante tu estancia.', error: true);
    return;
  }
  final text = TextEditingController();
  final send = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCardSurface,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('¿Qué necesitas?', style: TextStyle(fontFamily: kSerif, fontSize: 24)),
          const SizedBox(height: 4),
          const Text('Recepción la recibe al instante y la deriva al área indicada.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 14),
          TextField(controller: text, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Ej. Una almohada extra')),
          const SizedBox(height: 14),
          AppButton(text: 'Enviar solicitud', icon: Icons.send, onPressed: () => Navigator.pop(sheetContext, true)),
        ],
      ),
    ),
  );
  if (send != true || !context.mounted) return;
  runAction(
    context,
    () => store.createRequest(roomId: stay.roomId!, stayId: stay.id, description: text.text, area: Area.reception, createdById: user.id),
    success: 'Recibimos tu solicitud. Tiempo estimado de atención: ${Area.reception.etaMinutes} min.',
  );
}
