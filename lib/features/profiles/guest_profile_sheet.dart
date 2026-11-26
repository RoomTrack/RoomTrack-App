import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';
import 'contact_fields.dart';

/// The front desk's view of a guest's record, looked up by the booking's e-mail: contact, document and (admins)
/// corrections and deactivation. Without a record it offers to create one.
Future<void> showGuestProfileSheet(BuildContext context, Stay stay) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          child: GuestProfileEditor(
            name: stay.guestName,
            email: stay.guestEmail,
            load: () => HotelStore.instance.remote!.guestProfileByEmail(stay.guestEmail),
          ),
        ),
      ),
    );

/// A guest record: the guest edits their own contact; the front desk also records the document once, and an
/// administrator corrects it or deactivates the record.
class GuestProfileEditor extends StatefulWidget {
  final String name;
  final String email;

  /// The account the record belongs to, when the guest creates their own.
  final int? userId;
  final Future<GuestProfile?> Function() load;

  const GuestProfileEditor({super.key, required this.name, required this.email, required this.load, this.userId});

  @override
  State<GuestProfileEditor> createState() => _GuestProfileEditorState();
}

class _GuestProfileEditorState extends State<GuestProfileEditor> {
  final _remote = HotelStore.instance.remote!;
  late Future<GuestProfile?> _profile = widget.load();
  final _contact = ContactControllers();
  final _document = TextEditingController();
  int _documentType = 0;
  String? _loadedId;
  bool _saving = false;

  UserRole get _role => HotelStore.instance.currentUser!.role;

  bool get _frontDesk => _role == UserRole.reception || _role == UserRole.admin;

  @override
  void dispose() {
    _contact.dispose();
    _document.dispose();
    super.dispose();
  }

  bool _filled = false;

  /// Copies a record into the fields once, so what is being typed is not overwritten on rebuilds.
  void _fill(GuestProfile? profile) {
    if (_filled && profile?.id == _loadedId) return;
    _filled = true;
    _loadedId = profile?.id;
    _contact.fill(profile?.contact ?? const ContactData());
    _document.text = profile?.documentNumber ?? '';
    _documentType = profile?.documentType ?? 0;
  }

  Future<void> _run(Future<GuestProfile> Function() call, String success) async {
    setState(() => _saving = true);
    GuestProfile? updated;
    await runAsync(context, () async => updated = await call(), success: success);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (updated != null) _profile = Future.value(updated);
    });
  }

  Future<void> _correct(GuestProfile profile) async {
    final reason = await askText(context, title: 'Corregir documento', label: 'Motivo de la corrección');
    if (reason == null || !mounted) return;
    await _run(() => _remote.correctGuestDocument(profile, _documentType, _document.text, reason), 'Documento corregido.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('${snapshot.error}', style: const TextStyle(color: kError));
        if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
        final profile = snapshot.data;
        _fill(profile);
        final canSetDocument = _frontDesk && (profile == null || profile.documentNumber.isEmpty);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(profile?.fullName ?? widget.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text(profile?.email.isNotEmpty == true ? profile!.email : widget.email, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 6),
            if (profile == null)
              const InfoRow(Icons.info_outline, 'Aún no hay ficha: complétala para guardar el contacto.')
            else ...[
              if (!profile.active) const InfoRow(Icons.block, 'Ficha desactivada', color: kError),
              if (profile.document.isNotEmpty) InfoRow(Icons.badge_outlined, profile.document),
            ],
            const SizedBox(height: 10),
            ContactFields(controllers: _contact),
            if (canSetDocument || (_role == UserRole.admin && profile != null)) ...[
              const SizedBox(height: 12),
              const Text('Documento de identidad', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < kDocumentTypes.length; i++)
                    ChoiceChip(label: Text(kDocumentTypes[i]), selected: _documentType == i, onSelected: (_) => setState(() => _documentType = i)),
                ],
              ),
              TextField(controller: _document, decoration: const InputDecoration(labelText: 'Número de documento')),
            ],
            const SizedBox(height: 16),
            AppButton(
              text: profile == null ? 'Crear ficha' : 'Guardar contacto',
              icon: Icons.save,
              loading: _saving,
              onPressed: () => profile == null
                  ? _run(() async {
                      var created = await _remote.createGuestProfile(
                          name: widget.name, email: widget.email, contact: _contact.value, userId: widget.userId);
                      if (canSetDocument && _document.text.trim().isNotEmpty) {
                        created = await _remote.setGuestDocument(created, _documentType, _document.text);
                      }
                      return created;
                    }, 'Ficha creada.')
                  : _run(() => _remote.setGuestContact(profile, _contact.value), 'Contacto actualizado.'),
            ),
            if (profile != null && canSetDocument) ...[
              const SizedBox(height: 8),
              AppButton(
                text: 'Registrar documento',
                icon: Icons.badge_outlined,
                outlined: true,
                onPressed: () => _run(() => _remote.setGuestDocument(profile, _documentType, _document.text), 'Documento registrado.'),
              ),
            ],
            if (profile != null && _role == UserRole.admin) ...[
              if (profile.documentNumber.isNotEmpty) ...[
                const SizedBox(height: 8),
                AppButton(text: 'Corregir documento', icon: Icons.edit_note, outlined: true, onPressed: () => _correct(profile)),
              ],
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: profile.active ? kError : kSuccess),
                onPressed: () => _run(() => _remote.setGuestProfileActive(profile, !profile.active),
                    profile.active ? 'Ficha desactivada.' : 'Ficha reactivada.'),
                icon: Icon(profile.active ? Icons.block : Icons.check_circle_outline),
                label: Text(profile.active ? 'Desactivar ficha' : 'Reactivar ficha'),
              ),
            ],
          ],
        );
      },
    );
  }
}
