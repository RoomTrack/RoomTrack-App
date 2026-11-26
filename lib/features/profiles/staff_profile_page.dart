import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';
import 'contact_fields.dart';

/// The HR record of a collaborator (administrators): position, habitual shift, contact, document and their
/// assignments to the hotel. An account without a record gets one here.
class StaffProfilePage extends StatefulWidget {
  final AppUser user;

  const StaffProfilePage({super.key, required this.user});

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> {
  final _remote = HotelStore.instance.remote!;
  late Future<StaffProfile?> _profile = _remote.staffProfileOf(widget.user.id);
  final _contact = ContactControllers();
  final _position = TextEditingController();
  final _document = TextEditingController();
  String _shift = 'Morning';
  int _documentType = 0;
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _contact.dispose();
    _position.dispose();
    _document.dispose();
    super.dispose();
  }

  void _fill(StaffProfile? profile) {
    if (_filled) return;
    _filled = true;
    _contact.fill(profile?.contact ?? const ContactData());
    _position.text = profile?.position ?? widget.user.role.label;
    _document.text = profile?.documentNumber ?? '';
    _documentType = profile?.documentType ?? 0;
    _shift = kHabitualShifts.containsKey(profile?.shift) ? profile!.shift : 'Morning';
  }

  Future<void> _run(Future<StaffProfile> Function() call, String success) async {
    setState(() => _saving = true);
    StaffProfile? updated;
    await runAsync(context, () async => updated = await call(), success: success);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (updated != null) _profile = Future.value(updated);
    });
  }

  Future<void> _saveAll(StaffProfile profile) => _run(() async {
        var p = profile;
        if (_position.text.trim() != p.position) p = await _remote.setStaffPosition(p, _position.text);
        if (_shift != p.shift) p = await _remote.setStaffShift(p, _shift);
        final contact = _contact.value;
        if (contact.toJson().toString() != p.contact.toJson().toString()) p = await _remote.setStaffContact(p, contact);
        if (_document.text.trim().isNotEmpty && (_document.text.trim() != p.documentNumber || _documentType != p.documentType)) {
          p = await _remote.setStaffDocument(p, _documentType, _document.text);
        }
        return p;
      }, 'Ficha actualizada.');

  Future<void> _rename(StaffProfile profile) async {
    final first = TextEditingController(text: profile.firstName);
    final last = TextEditingController(text: profile.lastName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre legal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: first, decoration: const InputDecoration(labelText: 'Nombres')),
            TextField(controller: last, decoration: const InputDecoration(labelText: 'Apellidos')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true && mounted) await _run(() => _remote.renameStaff(profile, first.text, last.text), 'Nombre actualizado.');
  }

  Future<void> _addAssignment(StaffProfile profile) async {
    var role = 'Staff';
    var start = DateUtils.dateOnly(HotelStore.instance.now);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Nueva asignación en el hotel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final r in kAssignmentRoles.entries)
                    ChoiceChip(label: Text(r.value), selected: role == r.key, onSelected: (_) => setLocal(() => role = r.key)),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Desde ${fmtDate(start)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                      context: dialogContext, firstDate: start.subtract(const Duration(days: 365)), lastDate: start.add(const Duration(days: 365)), initialDate: start);
                  if (picked != null) setLocal(() => start = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Asignar')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) await _run(() => _remote.addStaffAssignment(profile, role, start), 'Asignación registrada.');
  }

  Future<void> _assignmentAction(StaffProfile profile, StaffAssignment assignment, String action) async {
    switch (action) {
      case 'suspend':
        await _run(() => _remote.suspendAssignment(profile, assignment), 'Asignación suspendida.');
      case 'reactivate':
        await _run(() => _remote.reactivateAssignment(profile, assignment), 'Asignación reactivada.');
      case 'terminate':
        final ok = await confirm(context, 'Terminar asignación', 'Terminará hoy como ${assignment.roleLabel}.', action: 'Terminar');
        if (ok && mounted) {
          await _run(() => _remote.terminateAssignment(profile, assignment, HotelStore.instance.now), 'Asignación terminada.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.user.name, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: FutureBuilder(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) return EmptyState(icon: Icons.error_outline, message: '${snapshot.error}');
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          final profile = snapshot.data;
          _fill(profile);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(profile == null ? widget.user.name : '${profile.firstName} ${profile.lastName}',
                              style: const TextStyle(fontFamily: kSerif, fontSize: 22)),
                        ),
                        if (profile != null) IconButton(tooltip: 'Nombre legal', onPressed: () => _rename(profile), icon: const Icon(Icons.edit_outlined)),
                      ],
                    ),
                    InfoRow(Icons.mail_outline, widget.user.email),
                    if (profile == null)
                      const InfoRow(Icons.info_outline, 'Esta cuenta aún no tiene ficha de personal.')
                    else ...[
                      InfoRow(Icons.qr_code_2, 'Código ${profile.code}'),
                      if (!profile.active) const InfoRow(Icons.block, 'Ficha desactivada', color: kError),
                    ],
                  ],
                ),
              ),
              const SectionHeader(title: 'Puesto y turno'),
              TextField(controller: _position, decoration: const InputDecoration(labelText: 'Puesto')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in kHabitualShifts.entries)
                    ChoiceChip(label: Text(s.value), selected: _shift == s.key, onSelected: (_) => setState(() => _shift = s.key)),
                ],
              ),
              const SectionHeader(title: 'Contacto'),
              ContactFields(controllers: _contact),
              const SectionHeader(title: 'Documento de identidad'),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < kDocumentTypes.length; i++)
                    ChoiceChip(label: Text(kDocumentTypes[i]), selected: _documentType == i, onSelected: (_) => setState(() => _documentType = i)),
                ],
              ),
              TextField(controller: _document, decoration: const InputDecoration(labelText: 'Número de documento')),
              const SizedBox(height: 16),
              AppButton(
                text: profile == null ? 'Crear ficha' : 'Guardar ficha',
                icon: Icons.save,
                loading: _saving,
                onPressed: () => profile == null
                    ? _run(
                        () => _remote.createStaffProfile(widget.user,
                            position: _position.text,
                            shift: _shift,
                            contact: _contact.value,
                            documentType: _documentType,
                            documentNumber: _document.text),
                        'Ficha creada y asignada al hotel.')
                    : _saveAll(profile),
              ),
              if (profile != null) ...[
                SectionHeader(
                  title: 'Asignaciones',
                  trailing: TextButton.icon(onPressed: () => _addAssignment(profile), icon: const Icon(Icons.add), label: const Text('Nueva')),
                ),
                if (profile.assignments.isEmpty) const EmptyState(message: 'Sin asignaciones.'),
                for (final a in profile.assignments)
                  AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.roleLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${fmtDate(a.start)}${a.end == null ? '' : ' → ${fmtDate(a.end!)}'} · ${a.statusLabel}',
                                  style: const TextStyle(color: kMuted)),
                            ],
                          ),
                        ),
                        if (a.status != 'Terminated')
                          PopupMenuButton<String>(
                            onSelected: (action) => _assignmentAction(profile, a, action),
                            itemBuilder: (_) => [
                              if (a.status == 'Suspended')
                                const PopupMenuItem(value: 'reactivate', child: Text('Reactivar'))
                              else
                                const PopupMenuItem(value: 'suspend', child: Text('Suspender')),
                              const PopupMenuItem(value: 'terminate', child: Text('Terminar')),
                            ],
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: profile.active ? kError : kSuccess),
                  onPressed: () => _run(() => _remote.setStaffProfileActive(profile, !profile.active),
                      profile.active ? 'Ficha desactivada.' : 'Ficha reactivada.'),
                  icon: Icon(profile.active ? Icons.block : Icons.check_circle_outline),
                  label: Text(profile.active ? 'Desactivar ficha' : 'Reactivar ficha'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
