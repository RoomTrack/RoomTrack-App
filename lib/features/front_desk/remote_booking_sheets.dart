import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/backend/api_client.dart';
import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Assisted check-in at the desk (US-27): the guest's document and its photo, as in the digital check-in. When the
/// booked room is not ready yet, the backend proposes rooms ready now; moving the booking there completes it.
Future<void> showAssistedCheckInSheet(BuildContext context, Stay stay) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssistedCheckIn(stay: stay),
    );

class _AssistedCheckIn extends StatefulWidget {
  final Stay stay;

  const _AssistedCheckIn({required this.stay});

  @override
  State<_AssistedCheckIn> createState() => _AssistedCheckInState();
}

class _AssistedCheckInState extends State<_AssistedCheckIn> {
  final _remote = HotelStore.instance.remote!;
  final _number = TextEditingController();
  final _nationality = TextEditingController(text: 'PE');
  String _documentType = 'DNI';
  XFile? _photo;
  bool _sending = false;
  List<AvailableRoom>? _alternatives;
  AvailableRoom? _chosen;
  String? _warning;

  @override
  void dispose() {
    _number.dispose();
    _nationality.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 80);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _send() async {
    final photo = _photo;
    if (photo == null) {
      showAppSnack(context, 'Agrega una foto del documento del huésped.', error: true);
      return;
    }
    setState(() {
      _sending = true;
      _warning = null;
    });
    final bytes = await photo.readAsBytes();
    try {
      // The booking moves to the room the front desk picked among the alternatives.
      if (_chosen case final room?) await _remote.rescheduleBooking(widget.stay.id, roomId: room.id);
      final code = await _remote.completeCheckIn(widget.stay.id,
          documentType: _documentType, documentNumber: _number.text, nationality: _nationality.text, document: bytes, fileName: photo.name);
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnack(context, 'Check-in completado${code == null ? '' : ' · código de acceso $code'}.');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'room.not_ready' || e.code == 'room.occupied') {
        final alternatives = await _remote.checkInAlternatives(widget.stay.id).catchError((_) => <AvailableRoom>[]);
        if (!mounted) return;
        setState(() {
          _alternatives = alternatives;
          _chosen = alternatives.firstOrNull;
          _warning = alternatives.isEmpty
              ? '${e.message} No hay otra habitación lista ahora.'
              : '${e.message} Elige una habitación lista y vuelve a confirmar.';
        });
      } else {
        setState(() => _warning = e.message);
      }
    } on DomainException catch (e) {
      if (mounted) setState(() => _warning = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final alternatives = _alternatives;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Check-in de ${stay.guestName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text('${stay.nights} noches · sale ${fmtDate(stay.checkOut)}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final type in const [('DNI', 'DNI'), ('PASSPORT', 'Pasaporte'), ('CE', 'Carné de extranjería')])
                  ChoiceChip(label: Text(type.$2), selected: _documentType == type.$1, onSelected: (_) => setState(() => _documentType = type.$1)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(controller: _number, decoration: const InputDecoration(labelText: 'Número de documento')),
            const SizedBox(height: 8),
            TextField(
              controller: _nationality,
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Nacionalidad (código de 2 letras)', counterText: ''),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Tomar foto')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Galería')),
                ),
              ],
            ),
            if (_photo != null) InfoRow(Icons.check_circle_outline, 'Documento: ${_photo!.name}', color: kSuccess),
            if (alternatives != null && alternatives.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Habitaciones listas ahora', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final room in alternatives)
                    ChoiceChip(
                      label: Text('${room.number} · ${room.typeName} · ${money(room.total)}'),
                      selected: _chosen?.id == room.id,
                      onSelected: (_) => setState(() => _chosen = room),
                    ),
                ],
              ),
            ],
            if (_warning != null) ...[
              const SizedBox(height: 10),
              Text(_warning!, style: const TextStyle(color: kError, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            AppButton(
              text: _chosen == null ? 'Confirmar check-in' : 'Mover a la ${_chosen!.number} y confirmar',
              icon: Icons.key_outlined,
              dark: true,
              loading: _sending,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// New dates and/or room of a Pending or Confirmed booking; a paid one keeps its total (the backend checks it).
Future<void> showRescheduleSheet(BuildContext context, Stay stay) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Reschedule(stay: stay),
    );

class _Reschedule extends StatefulWidget {
  final Stay stay;

  const _Reschedule({required this.stay});

  @override
  State<_Reschedule> createState() => _RescheduleState();
}

class _RescheduleState extends State<_Reschedule> {
  final _remote = HotelStore.instance.remote!;
  late DateTime _from = DateUtils.dateOnly(widget.stay.checkIn);
  late DateTime _to = DateUtils.dateOnly(widget.stay.checkOut);
  late int? _roomId = widget.stay.roomId;
  late Future<List<AvailableRoom>> _rooms = _remote.availableRooms(_from, _to);
  bool _saving = false;

  Future<void> _pickDates() async {
    final today = DateUtils.dateOnly(HotelStore.instance.now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from.isBefore(today) ? today : _from, end: _to.isAfter(today) ? _to : today.add(const Duration(days: 1))),
      helpText: 'Nuevas fechas',
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.start;
      _to = range.end.isAfter(range.start) ? range.end : range.start.add(const Duration(days: 1));
      _rooms = _remote.availableRooms(_from, _to);
    });
  }

  Future<void> _save() async {
    final stay = widget.stay;
    final datesChanged = _from != DateUtils.dateOnly(stay.checkIn) || _to != DateUtils.dateOnly(stay.checkOut);
    final roomChanged = _roomId != stay.roomId;
    if (!datesChanged && !roomChanged) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final ok = await runAsync(
      context,
      () => _remote.rescheduleBooking(stay.id,
          checkIn: datesChanged ? _from : null, checkOut: datesChanged ? _to : null, roomId: roomChanged ? _roomId : null),
      success: 'Reserva actualizada. Avisamos a ${stay.guestEmail} por correo.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = HotelStore.instance;
    final current = widget.stay.roomId == null ? null : store.rooms.where((r) => r.id == widget.stay.roomId).firstOrNull;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Cambiar reserva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (!widget.stay.awaitingPayment)
            const InfoRow(Icons.info_outline, 'Está pagada: el cambio debe mantener el mismo total.', color: kWarning),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDates,
            icon: const Icon(Icons.date_range),
            label: Text('${fmtDate(_from)} → ${fmtDate(_to)} · ${_to.difference(_from).inDays} noches'),
          ),
          const SizedBox(height: 12),
          const Text('Habitación', style: TextStyle(fontWeight: FontWeight.w800)),
          FutureBuilder(
            future: _rooms,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
              final rooms = snapshot.data;
              if (rooms == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (current != null && !rooms.any((r) => r.id == current.id))
                    ChoiceChip(
                      label: Text('${current.number} · actual'),
                      selected: _roomId == current.id,
                      onSelected: (_) => setState(() => _roomId = current.id),
                    ),
                  for (final room in rooms)
                    ChoiceChip(
                      label: Text('${room.number} · ${room.typeName} · ${money(room.total)}'),
                      selected: _roomId == room.id,
                      onSelected: (_) => setState(() => _roomId = room.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          AppButton(text: 'Guardar cambios', icon: Icons.save, loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
