import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/hotel_store.dart';
import '../../core/seed.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import '../payments/folio_card.dart';
import '../payments/payment_sheet.dart';
import 'guest_chat_page.dart';
import 'rating_card.dart';

/// The guest's stay from reservation to check-out, laid out as the "Mi estadía" mockup
/// (US-13, US-14, US-15, US-16, US-21).
class MyStayPage extends StatelessWidget {
  const MyStayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final stay = store.activeStayOf(store.currentUser!.id);
      if (stay == null) {
        return const EmptyState(
          icon: Icons.hotel_outlined,
          message: 'No encontramos reservas con tu correo.\nSi reservaste con otro correo, pide ayuda a recepción.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          StayHeroCard(stay: stay, store: store),
          const SizedBox(height: 20),
          ...switch (stay.status) {
            StayStatus.reserved || StayStatus.checkInInProgress =>
              store.isRemote ? [_RemoteCheckIn(stay: stay, store: store)] : [_CheckInSteps(stay: stay, store: store)],
            StayStatus.checkedIn => _inHouse(context, store, stay),
            StayStatus.checkedOut => [
                if (!stay.rated) RatingCard(stay: stay),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('¡Gracias por tu visita!', style: TextStyle(fontFamily: kSerif, fontSize: 20)),
                      InfoRow(Icons.mail_outline, 'Enviamos el comprobante de tu estancia a ${stay.guestEmail}.'),
                      if (stay.depositRefunded) InfoRow(Icons.undo, 'Devolución del depósito de ${money(stay.depositHeld)} en proceso.'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AccountSummary(stay: stay, store: store),
              ],
          },
        ],
      );
    });
  }

  List<Widget> _inHouse(BuildContext context, HotelStore store, Stay stay) {
    final balance = store.balanceOf(stay);
    if (store.isRemote) {
      return [
        AccountSummary(stay: stay, store: store),
        const SizedBox(height: 20),
        _MockupButton(text: 'Llave digital', icon: Icons.key_outlined, filled: true, onPressed: () => _showKey(context, store, stay)),
        const SizedBox(height: 12),
        const InfoRow(Icons.info_outline, 'Para extender tu estadía o hacer el check-out, escribe a recepción desde Mensajes.'),
      ];
    }
    return [
      AccountSummary(stay: stay, store: store),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: _MockupButton(
              text: 'Extender estadía',
              icon: Icons.edit_calendar_outlined,
              filled: true,
              onPressed: () => _extend(context, store, stay),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MockupButton(
              text: 'Llave digital',
              icon: Icons.key_outlined,
              onPressed: () => _showKey(context, store, stay),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _MockupButton(
        text: balance > 0 ? 'Pagar ${money(balance)} y hacer check-out' : 'Hacer check-out',
        icon: Icons.logout,
        onPressed: () => _checkOut(context, store, stay),
      ),
      Center(
        child: TextButton.icon(
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(stay.fiscalData == null ? 'Necesito factura' : 'Factura a ${stay.fiscalData!.businessName}'),
          onPressed: () => editFiscalData(context, store, stay),
        ),
      ),
    ];
  }

  void _showKey(BuildContext context, HotelStore store, Stay stay) {
    final room = store.roomById(stay.roomId!);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCardSurface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_outlined, color: kGold, size: 36),
            const SizedBox(height: 8),
            Text('${stay.roomType.label} ${room.number}', style: const TextStyle(fontFamily: kSerif, fontSize: 24)),
            const SizedBox(height: 16),
            Text(
              stay.accessCode ?? '------',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 8, color: kPrimary),
            ),
            const SizedBox(height: 12),
            const Text('Ingresa este código en la cerradura de tu habitación.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ],
        ),
      ),
    );
  }

  Future<void> _checkOut(BuildContext context, HotelStore store, Stay stay) async {
    final balance = store.balanceOf(stay);
    if (balance > 0) {
      // Pending charges are shown and paid before the check-out can finish (US-14, US-16).
      final paid = await showPaymentSheet(
        context,
        title: 'Saldo de tu cuenta',
        amount: balance,
        allowSplit: true,
        onPay: (parts) => store.payBalance(stay.id, parts),
      );
      if (!paid || !context.mounted) return;
    } else {
      final ok = await confirm(context, 'Check-out', '¿Confirmas que finalizas tu estancia?');
      if (!ok || !context.mounted) return;
    }
    runAction(context, () => store.checkOut(stay.id), success: 'Check-out completado. Te enviamos el comprobante por correo.');
  }

  Future<void> _extend(BuildContext context, HotelStore store, Stay stay) async {
    var nights = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Extender estadía'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(onPressed: nights > 1 ? () => setLocal(() => nights--) : null, icon: const Icon(Icons.remove)),
                  Text('$nights ${nights == 1 ? 'noche' : 'noches'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => setLocal(() => nights++), icon: const Icon(Icons.add)),
                ],
              ),
              Text('Costo adicional ${money(stay.roomType.nightlyRate * nights)}', style: const TextStyle(color: kMuted)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Verificar y extender')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    runAction(context, () => store.extendStay(stay.id, nights), success: 'Estancia extendida. Se agregó el cargo a tu cuenta.');
  }
}

/// Hotel photo, status, room, dates, guests and check-out time.
class StayHeroCard extends StatelessWidget {
  final Stay stay;
  final HotelStore store;

  const StayHeroCard({super.key, required this.stay, required this.store});

  @override
  Widget build(BuildContext context) {
    final room = stay.roomId == null ? null : store.roomById(stay.roomId!);
    final (status, dot) = switch (stay.status) {
      StayStatus.reserved => ('Confirmada', kGold),
      StayStatus.checkInInProgress => ('Check-in en proceso', kWarning),
      StayStatus.checkedIn => ('Hospedada', kSuccess),
      StayStatus.checkedOut => ('Finalizada', kMuted),
    };
    final timeline = switch (stay.status) {
      StayStatus.checkedIn || StayStatus.checkedOut => 'Check-out ${relativeDay(stay.checkOut, store.now)} · ${fmtHour12(stay.checkOut)}',
      _ => 'Check-in ${relativeDay(stay.checkIn, store.now)} · desde las ${fmtHour12(stay.checkIn)}',
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kCardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              // The gradient shows while the photo loads or when there is no connection.
              Container(
                height: 92,
                width: double.infinity,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [kSoftGreen, Color(0xFFD9CBB0)])),
                child: Image.network(kHotelImage, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(kHotelName, style: TextStyle(fontFamily: kSerif, fontSize: 21, color: kSecondary)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.key_outlined, size: 18, color: kGold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        room == null ? '${stay.roomType.label} (por asignar)' : '${stay.roomType.label} ${room.number}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: kMuted),
                    const SizedBox(width: 6),
                    Text('${fmtDayMonth(stay.checkIn)} – ${fmtDayMonth(stay.checkOut)}', style: const TextStyle(color: kMuted)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 18, color: kMuted),
                    const SizedBox(width: 6),
                    Text('${stay.guests} ${stay.guests == 1 ? 'huésped' : 'huéspedes'}', style: const TextStyle(color: kMuted)),
                  ],
                ),
                const Divider(height: 24, color: kLine),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: kGold),
                    const SizedBox(width: 6),
                    Expanded(child: Text(timeline, style: const TextStyle(color: kMuted))),
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

/// "Resumen de cuenta" of the mockup: charges and total, plus what was already paid.
class AccountSummary extends StatelessWidget {
  final Stay stay;
  final HotelStore store;

  const AccountSummary({super.key, required this.stay, required this.store});

  @override
  Widget build(BuildContext context) {
    final paid = store.paidFor(stay);
    final balance = store.balanceOf(stay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(child: Text('Resumen de cuenta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            Text('USD', style: TextStyle(color: kMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          decoration: BoxDecoration(color: kCardSurface, borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
          child: Column(
            children: [
              for (final charge in stay.charges)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(charge.description.split(' · ').first, style: const TextStyle(color: kMuted))),
                      Text(money(charge.amount)),
                    ],
                  ),
                ),
              const Divider(height: 20, color: kLine),
              Row(
                children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(money(store.totalCharges(stay)), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kSecondary)),
                ],
              ),
              if (paid > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('Pagado', style: TextStyle(color: kMuted))),
                    Text('- ${money(paid)}', style: const TextStyle(color: kMuted)),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Saldo pendiente', style: TextStyle(color: kMuted))),
                    Text(money(balance), style: TextStyle(color: balance > 0 ? kWarning : kSuccess, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
              if (stay.depositHeld > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Depósito de garantía', style: TextStyle(color: kMuted, fontSize: 13))),
                      Text(
                        '${money(stay.depositHeld)} ${stay.depositRefunded ? 'devuelto' : 'retenido'}',
                        style: const TextStyle(color: kMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Large rounded buttons of the mockup: dark green filled or white outlined.
class _MockupButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;

  const _MockupButton({required this.text, required this.icon, required this.onPressed, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    const padding = EdgeInsets.symmetric(vertical: 18, horizontal: 12);
    final label = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700));
    return filled
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.white, shape: shape, padding: padding),
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: label,
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: kCardSurface,
              foregroundColor: kSecondary,
              side: const BorderSide(color: kLine),
              shape: shape,
              padding: padding,
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: label,
          );
  }
}

/// Digital check-in: identity, deposit and arrival confirmation (US-13, US-15).
class _CheckInSteps extends StatefulWidget {
  final Stay stay;
  final HotelStore store;

  const _CheckInSteps({required this.stay, required this.store});

  @override
  State<_CheckInSteps> createState() => _CheckInStepsState();
}

class _CheckInStepsState extends State<_CheckInSteps> {
  late final TextEditingController _document = TextEditingController(text: widget.stay.documentId);
  String? _waitMessage;

  @override
  void dispose() {
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final store = widget.store;
    final started = stay.status == StayStatus.checkInInProgress;
    final depositPaid = stay.depositHeld >= stay.depositRequired;
    final balance = store.balanceOf(stay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Check-in digital', style: TextStyle(fontFamily: kSerif, fontSize: 22)),
        const Text('Regístrate antes de llegar y evita la fila.', style: TextStyle(color: kMuted)),
        const SizedBox(height: 8),
        _Step(
          number: 1,
          title: 'Tus datos',
          done: started,
          child: started
              ? InfoRow(Icons.badge_outlined, 'Documento ${stay.documentId}')
              : Column(
                  children: [
                    TextField(controller: _document, decoration: const InputDecoration(labelText: 'Documento de identidad')),
                    const SizedBox(height: 10),
                    AppButton(
                      text: 'Iniciar check-in',
                      icon: Icons.arrow_forward,
                      onPressed: () => runAction(context, () => store.startDigitalCheckIn(stay.id, _document.text),
                          success: 'Tu reserva quedó en "check-in en proceso".'),
                    ),
                  ],
                ),
        ),
        _Step(
          number: 2,
          title: 'Pago',
          done: depositPaid,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountSummary(stay: stay, store: store),
              const SizedBox(height: 12),
              if (!depositPaid)
                AppButton(
                  text: 'Pagar depósito de garantía ${money(stay.depositRequired)}',
                  icon: Icons.credit_card,
                  onPressed: !started
                      ? null
                      : () async {
                          final paid = await showPaymentSheet(
                            context,
                            title: 'Depósito reembolsable',
                            amount: stay.depositRequired,
                            onPay: (parts) => store.payDeposit(stay.id, parts.first.card!),
                          );
                          if (paid && context.mounted) showAppSnack(context, 'Depósito retenido. Tu check-in está habilitado.');
                        },
                ),
              if (balance > 0) ...[
                const SizedBox(height: 8),
                AppButton(
                  text: 'Pagar mi reserva ${money(balance)} (opcional)',
                  icon: Icons.payments_outlined,
                  outlined: true,
                  onPressed: !started
                      ? null
                      : () => showPaymentSheet(
                            context,
                            title: 'Pago de reserva',
                            amount: balance,
                            onPay: (parts) => store.payReservation(stay.id, parts.first.card!),
                          ),
                ),
              ],
            ],
          ),
        ),
        _Step(
          number: 3,
          title: 'Al llegar al hotel',
          done: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Confirma tu identidad para recibir tu habitación y código de acceso.', style: TextStyle(color: kMuted)),
              if (_waitMessage != null) ...[
                const SizedBox(height: 8),
                InfoRow(Icons.hourglass_bottom, _waitMessage!, color: kWarning),
              ],
              const SizedBox(height: 10),
              AppButton(
                text: 'Ya llegué',
                icon: Icons.key_outlined,
                dark: true,
                onPressed: !started || !depositPaid ? null : _arrive,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.support_agent),
          label: const Text('¿Problemas? Escribir a recepción'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Recepción')),
                body: const GuestChatPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _arrive() async {
    final document = await askText(context, title: 'Confirma tu identidad', label: 'Documento de identidad');
    if (document == null || !mounted) return;
    try {
      final stay = widget.store.confirmArrival(widget.stay.id, document);
      setState(() => _waitMessage = null);
      if (mounted) showAppSnack(context, '¡Te damos la bienvenida! Habitación ${widget.store.roomById(stay.roomId!).number}.');
    } on RoomNotReadyException catch (e) {
      setState(() => _waitMessage = e.message);
    } on DomainException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final bool done;
  final Widget child;

  const _Step({required this.number, required this.title, required this.done, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: done ? kSuccess : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done ? kSuccess : kSoftGreen,
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text('$number', style: const TextStyle(fontWeight: FontWeight.w900, color: kPrimaryDark)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Digital check-in against the backend (US-13): pay first, then identity document and its photo.
class _RemoteCheckIn extends StatefulWidget {
  final Stay stay;
  final HotelStore store;

  const _RemoteCheckIn({required this.stay, required this.store});

  @override
  State<_RemoteCheckIn> createState() => _RemoteCheckInState();
}

class _RemoteCheckInState extends State<_RemoteCheckIn> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _nationality = TextEditingController(text: 'PE');
  String _documentType = 'DNI';
  XFile? _photo;
  bool _sending = false;

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
      showAppSnack(context, 'Agrega una foto de tu documento.', error: true);
      return;
    }
    setState(() => _sending = true);
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    await runAsync(
      context,
      () => widget.store.remote!.completeCheckIn(widget.stay.id,
          documentType: _documentType, documentNumber: _number.text, nationality: _nationality.text, document: bytes, fileName: photo.name),
      success: '¡Check-in completado! Tu código de acceso está en "Llave digital".',
    );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _askForHelp() async {
    final message = await askText(context, title: 'Ayuda con el check-in', label: '¿Qué necesitas?', maxLines: 3);
    if (message == null || !mounted) return;
    await runAsync(context, () => widget.store.remote!.requestCheckInAssistance(widget.stay.id, message),
        success: 'Recepción recibió tu pedido de ayuda.');
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final instructions = stay.paymentInstructions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountSummary(stay: stay, store: widget.store),
        const SizedBox(height: 20),
        if (stay.awaitingPayment) ...[
          const Text('Paga tu reserva', style: TextStyle(fontFamily: kSerif, fontSize: 22)),
          const Text('Cuando el hotel registre tu pago podrás hacer el check-in desde aquí.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (instructions?['accountHolder'] != null) InfoRow(Icons.person_outline, 'A nombre de ${instructions!['accountHolder']}'),
                if (instructions?['yapeNumber'] != null) InfoRow(Icons.phone_iphone, 'Yape ${instructions!['yapeNumber']}'),
                if (instructions?['plinNumber'] != null) InfoRow(Icons.phone_iphone, 'Plin ${instructions!['plinNumber']}'),
                if (instructions?['bankAccountNumber'] != null)
                  InfoRow(Icons.account_balance_outlined, '${instructions!['bankName'] ?? 'Banco'} ${instructions['bankAccountNumber']}'),
                if (instructions == null) const InfoRow(Icons.support_agent, 'Recepción te indicará cómo pagar.'),
                if (stay.paymentDueAt != null) InfoRow(Icons.timer_outlined, 'Paga antes del ${fmtDateTime(stay.paymentDueAt!)}', color: kWarning),
              ],
            ),
          ),
        ] else ...[
          const Text('Check-in digital', style: TextStyle(fontFamily: kSerif, fontSize: 22)),
          const Text('Tu reserva está pagada. Regístrate y recibe tu código de acceso.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final type in const [('DNI', 'DNI'), ('PASSPORT', 'Pasaporte'), ('CE', 'Carné de extranjería')])
                ChoiceChip(label: Text(type.$2), selected: _documentType == type.$1, onSelected: (_) => setState(() => _documentType = type.$1)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'Número de documento')),
          const SizedBox(height: 10),
          TextField(
            controller: _nationality,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Nacionalidad (código de 2 letras)', counterText: ''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Tomar foto')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Galería')),
              ),
            ],
          ),
          if (_photo != null) InfoRow(Icons.check_circle_outline, 'Documento: ${_photo!.name}', color: kSuccess),
          const SizedBox(height: 14),
          AppButton(text: 'Completar check-in', icon: Icons.key_outlined, dark: true, loading: _sending, onPressed: _send),
        ],
        TextButton.icon(onPressed: _askForHelp, icon: const Icon(Icons.support_agent), label: const Text('¿Problemas? Pedir ayuda a recepción')),
      ],
    );
  }
}
