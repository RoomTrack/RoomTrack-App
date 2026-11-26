import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../payments/payment_settings_page.dart';
import 'checklists_page.dart';

/// The hotel record, its room types and rooms, and the cleaning protocols (administrators, backend only).
class HotelSetupPage extends StatefulWidget {
  const HotelSetupPage({super.key});

  @override
  State<HotelSetupPage> createState() => _HotelSetupPageState();
}

class _HotelSetupPageState extends State<HotelSetupPage> {
  final _remote = HotelStore.instance.remote!;
  late Future<HotelInfo> _hotel = _remote.hotel();
  late Future<List<RoomTypeInfo>> _types = _remote.roomTypes();

  void _reloadTypes() => setState(() => _types = _remote.roomTypes());

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final rooms = [...store.rooms]..sort((a, b) => a.number.compareTo(b.number));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FutureBuilder(
            future: _hotel,
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorCard('${snapshot.error}', onRetry: () => setState(() => _hotel = _remote.hotel()));
              final hotel = snapshot.data;
              if (hotel == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
              return _HotelCard(hotel: hotel, onEdit: () => _editHotel(hotel));
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            text: 'Protocolos de limpieza',
            icon: Icons.checklist_rtl,
            outlined: true,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChecklistsPage())),
          ),
          const SizedBox(height: 10),
          AppButton(
            text: 'Medios de pago del hotel',
            icon: Icons.account_balance_wallet_outlined,
            outlined: true,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentSettingsPage())),
          ),
          SectionHeader(
            title: 'Tipos de habitación',
            subtitle: 'Compartidos por los hoteles de la cadena.',
            trailing: TextButton.icon(onPressed: _newType, icon: const Icon(Icons.add), label: const Text('Nuevo')),
          ),
          FutureBuilder(
            future: _types,
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorCard('${snapshot.error}', onRetry: _reloadTypes);
              final types = snapshot.data;
              if (types == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in types)
                    Tooltip(message: type.description, child: Chip(avatar: const Icon(Icons.bed_outlined, size: 18), label: Text(type.name))),
                ],
              );
            },
          ),
          SectionHeader(
            title: 'Habitaciones',
            subtitle: '${rooms.length} en el hotel',
            trailing: TextButton.icon(onPressed: () => _editRoom(null), icon: const Icon(Icons.add), label: const Text('Agregar')),
          ),
          for (final room in rooms)
            AppCard(
              onTap: () => _editRoom(room),
              child: Row(
                children: [
                  Text(room.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${room.typeLabel}${room.price == null ? '' : ' · ${money(room.price!)} / noche'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (room.description.isNotEmpty)
                          Text(room.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted)),
                        const SizedBox(height: 4),
                        Pill(text: room.status.label, color: room.status.color),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: kMuted),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _newType() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo tipo de habitación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre (p. ej. Suite junior)')),
            TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAsync(context, () => _remote.createRoomType(name.text, description.text), success: 'Tipo de habitación creado.');
    if (done) _reloadTypes();
  }

  Future<void> _editHotel(HotelInfo hotel) async {
    final saved = await showModalBottomSheet<HotelInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HotelForm(hotel: hotel),
    );
    if (saved != null && mounted) setState(() => _hotel = Future.value(saved));
  }

  Future<void> _editRoom(Room? room) async {
    final types = await _types.catchError((_) => <RoomTypeInfo>[]);
    if (!mounted) return;
    if (types.isEmpty) {
      showAppSnack(context, 'Primero crea un tipo de habitación.', error: true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RoomForm(room: room, types: types),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard(this.message, {required this.onRetry});

  @override
  Widget build(BuildContext context) => AppCard(
        borderColor: kError,
        child: Row(
          children: [
            Expanded(child: Text(message, style: const TextStyle(color: kError))),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      );
}

class _HotelCard extends StatelessWidget {
  final HotelInfo hotel;
  final VoidCallback onEdit;

  const _HotelCard({required this.hotel, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hotel.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: Image.network(hotel.imageUrl, height: 150, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(hotel.name, style: const TextStyle(fontFamily: kSerif, fontSize: 22))),
                    IconButton(tooltip: 'Editar datos del hotel', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                  ],
                ),
                InfoRow(Icons.place_outlined, hotel.location),
                if (hotel.type.isNotEmpty) InfoRow(Icons.category_outlined, hotel.type),
                if (hotel.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(hotel.description, style: const TextStyle(color: kMuted)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(
                      text: hotel.acceptsBookings ? 'Acepta reservas' : 'Sin medios de pago: no acepta reservas',
                      color: hotel.acceptsBookings ? kSuccess : kWarning,
                    ),
                    for (final amenity in hotel.amenities) Pill(text: amenity, color: kPrimary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HotelForm extends StatefulWidget {
  final HotelInfo hotel;

  const _HotelForm({required this.hotel});

  @override
  State<_HotelForm> createState() => _HotelFormState();
}

class _HotelFormState extends State<_HotelForm> {
  final _remote = HotelStore.instance.remote!;
  late final _name = TextEditingController(text: widget.hotel.name);
  late final _address = TextEditingController(text: widget.hotel.address);
  late final _city = TextEditingController(text: widget.hotel.city);
  late final _country = TextEditingController(text: widget.hotel.country);
  late final _image = TextEditingController(text: widget.hotel.imageUrl);
  late final _description = TextEditingController(text: widget.hotel.description);
  late String _type = widget.hotel.type;
  late final Set<String> _amenities = {...widget.hotel.amenities};
  late final Future<(List<String>, List<String>)> _options =
      Future.wait([_remote.hotelCategories(), _remote.amenityOptions()]).then((r) => (r[0], r[1]));
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _country, _image, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _uploadPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() => _uploading = true);
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    await runAsync(context, () async => _image.text = await _remote.uploadHotelImage(bytes, photo.name),
        success: 'Foto subida. Guarda para aplicarla.');
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HotelInfo? saved;
    final ok = await runAsync(context, () async {
      saved = await _remote.updateHotel(HotelInfo(
        id: widget.hotel.id,
        name: _name.text,
        address: _address.text,
        city: _city.text,
        country: _country.text,
        imageUrl: _image.text,
        description: _description.text,
        type: _type,
        amenities: _amenities.toList(),
      ));
    }, success: 'Datos del hotel actualizados.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Datos del hotel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'Ciudad'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _country, decoration: const InputDecoration(labelText: 'País'))),
              ],
            ),
            const SizedBox(height: 8),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL de la foto'))),
                const SizedBox(width: 8),
                _uploading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(tooltip: 'Subir foto', onPressed: _uploadPhoto, icon: const Icon(Icons.upload_outlined)),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _options,
              builder: (context, snapshot) {
                final options = snapshot.data;
                if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
                if (options == null) return const LinearProgressIndicator();
                final (categories, amenities) = options;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categoría', style: TextStyle(fontWeight: FontWeight.w800)),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final c in {...categories, if (_type.isNotEmpty) _type})
                          ChoiceChip(label: Text(c), selected: _type == c, onSelected: (_) => setState(() => _type = c)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Servicios del hotel', style: TextStyle(fontWeight: FontWeight.w800)),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final a in {...amenities, ..._amenities})
                          FilterChip(
                            label: Text(a),
                            selected: _amenities.contains(a),
                            onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            AppButton(text: 'Guardar', icon: Icons.save, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _RoomForm extends StatefulWidget {
  final Room? room;
  final List<RoomTypeInfo> types;

  const _RoomForm({required this.room, required this.types});

  @override
  State<_RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends State<_RoomForm> {
  final _remote = HotelStore.instance.remote!;
  late final _number = TextEditingController(text: widget.room?.number ?? '');
  late final _price = TextEditingController(text: widget.room?.price?.toStringAsFixed(2) ?? '');
  late final _description = TextEditingController(text: widget.room?.description ?? '');
  late int _typeId = widget.types.any((t) => t.id == widget.room?.roomTypeId) ? widget.room!.roomTypeId! : widget.types.first.id;
  late final Set<String> _amenities = {...?widget.room?.amenities};
  late final Future<List<String>> _options = _remote.amenityOptions();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_number, _price, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (price == null || price <= 0) {
      showAppSnack(context, 'Ingresa el precio por noche.', error: true);
      return;
    }
    setState(() => _saving = true);
    final room = widget.room;
    final ok = await runAsync(
      context,
      () => room == null
          ? _remote.createRoom(number: _number.text, roomTypeId: _typeId, price: price, description: _description.text, amenities: _amenities.toList())
          : _remote.updateRoom(room,
              number: _number.text, roomTypeId: _typeId, price: price, description: _description.text, amenities: _amenities.toList()),
      success: room == null ? 'Habitación ${_number.text.trim()} creada.' : 'Habitación actualizada.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _delete(Room room) async {
    final ok = await confirm(context, 'Eliminar habitación ${room.number}',
        'Se quitará del hotel. No se puede si tiene reservas activas.', action: 'Eliminar');
    if (!ok || !mounted) return;
    if (await runAsync(context, () => _remote.deleteRoom(room), success: 'Habitación ${room.number} eliminada.') && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(room == null ? 'Nueva habitación' : 'Habitación ${room.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _number, maxLength: 10, decoration: const InputDecoration(labelText: 'Número', counterText: ''))),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio por noche', prefixText: '\$ '),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _typeId,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final t in widget.types) DropdownMenuItem(value: t.id, child: Text(t.name))],
              onChanged: (v) => setState(() => _typeId = v ?? _typeId),
            ),
            const SizedBox(height: 8),
            TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
            const SizedBox(height: 10),
            const Text('Comodidades', style: TextStyle(fontWeight: FontWeight.w800)),
            FutureBuilder(
              future: _options,
              builder: (context, snapshot) {
                final options = snapshot.data ?? const <String>[];
                return Wrap(
                  spacing: 8,
                  children: [
                    for (final a in {...options, ..._amenities})
                      FilterChip(
                        label: Text(a),
                        selected: _amenities.contains(a),
                        onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            AppButton(text: 'Guardar', icon: Icons.save, loading: _saving, onPressed: _save),
            if (room != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kError),
                onPressed: () => _delete(room),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar habitación'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
