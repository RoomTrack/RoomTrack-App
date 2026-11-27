import 'package:flutter/material.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../shared/ui.dart';
import 'hotel_setup_page.dart';

/// What an administrator without a hotel sees: a hotel admin registers theirs, a chain administrator picks one of
/// the chain or registers a new one.
class HotelGatePage extends StatefulWidget {
  const HotelGatePage({super.key});

  @override
  State<HotelGatePage> createState() => _HotelGatePageState();
}

class _HotelGatePageState extends State<HotelGatePage> {
  final RemoteHotel _remote = HotelStore.instance.remote!;
  late Future<List<ChainHotel>> _hotels = _load();
  bool _signingOut = false;

  Future<List<ChainHotel>> _load() => _remote.isChainAdmin ? _remote.chainHotels() : Future.value(const []);

  Future<void> _reload() async {
    final next = _load();
    setState(() => _hotels = next);
    await next.catchError((_) => const <ChainHotel>[]);
  }

  Future<void> _register() async {
    final created = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const HotelForm(),
    );
    // A chain administrator starts working on the new hotel; a hotel admin's session now carries it.
    if (created == true && mounted) await _reload();
  }

  Future<void> _choose(ChainHotel hotel) async {
    await runAsync(context, () => _remote.chooseHotel(hotel));
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await _remote.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final chain = _remote.isChainAdmin;
    final name = HotelStore.instance.currentUser?.firstName ?? '';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const RoomTrackLogo(size: 34, withName: true),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signingOut ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: kLine)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          children: [
            PageHeader(
              title: chain ? 'Hoteles de la cadena' : 'Registra tu hotel',
              subtitle: chain
                  ? 'Elige el hotel en el que vas a trabajar, o registra uno nuevo.'
                  : 'Hola${name.isEmpty ? '' : ', $name'}. Tu cuenta aún no tiene un hotel: registra el que vas a administrar.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!chain) ...[
                    const AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InfoRow(Icons.apartment_outlined, 'Cada cuenta de administrador administra un solo hotel.'),
                          InfoRow(Icons.badge_outlined, 'Luego agregas sus habitaciones, su personal y sus medios de pago.'),
                          InfoRow(Icons.lock_outline, 'Al registrarlo, tu sesión se renueva para incluir el hotel.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppButton(
                    text: chain ? 'Registrar un hotel' : 'Registrar mi hotel',
                    icon: Icons.add_business_outlined,
                    outlined: chain,
                    onPressed: _register,
                  ),
                  if (chain) ...[
                    const SizedBox(height: 8),
                    FutureBuilder(
                      future: _hotels,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return AppCard(
                            borderColor: kError,
                            child: Row(
                              children: [
                                Expanded(child: Text('${snapshot.error}', style: const TextStyle(color: kError))),
                                TextButton(onPressed: _reload, child: const Text('Reintentar')),
                              ],
                            ),
                          );
                        }
                        final hotels = snapshot.data;
                        if (hotels == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                        if (hotels.isEmpty) {
                          return const EmptyState(message: 'La cadena aún no tiene hoteles.', icon: Icons.apartment_outlined);
                        }
                        return Column(children: [for (final hotel in hotels) _HotelTile(hotel: hotel, onTap: () => _choose(hotel))]);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotelTile extends StatelessWidget {
  final ChainHotel hotel;
  final VoidCallback onTap;

  const _HotelTile({required this.hotel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 64,
                height: 64,
                child: hotel.imageUrl.isEmpty
                    ? const ColoredBox(color: kLine, child: Icon(Icons.apartment_outlined, color: kMuted))
                    : Image.network(hotel.imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(color: kLine, child: Icon(Icons.apartment_outlined, color: kMuted))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hotel.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (hotel.location.isNotEmpty)
                    Text(hotel.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted)),
                  const SizedBox(height: 4),
                  Pill(
                    text: hotel.acceptsBookings ? 'Acepta reservas' : 'Sin medios de pago',
                    color: hotel.acceptsBookings ? kSuccess : kWarning,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kMuted),
          ],
        ),
      ),
    );
  }
}
