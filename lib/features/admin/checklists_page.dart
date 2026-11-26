import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// The cleaning protocol of each room type and the hotel default (US-07). New cleaning tasks get the protocol of their
/// room's type; a required step blocks marking the room as clean.
class ChecklistsPage extends StatefulWidget {
  const ChecklistsPage({super.key});

  @override
  State<ChecklistsPage> createState() => _ChecklistsPageState();
}

class _ChecklistsPageState extends State<ChecklistsPage> {
  final _remote = HotelStore.instance.remote!;
  late Future<(List<RoomTypeInfo>, List<ChecklistTemplate>)> _data = _load();

  Future<(List<RoomTypeInfo>, List<ChecklistTemplate>)> _load() async =>
      (await _remote.roomTypes(), await _remote.checklistTemplates());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protocolos de limpieza', style: TextStyle(fontWeight: FontWeight.w900))),
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(icon: Icons.error_outline, message: '${snapshot.error}');
          }
          final data = snapshot.data;
          if (data == null) return const LoadingView();
          final (types, templates) = data;
          final standard = templates.where((t) => t.roomTypeId == null).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const InfoRow(Icons.info_outline,
                  'Las tareas nuevas toman el protocolo del tipo de su habitación; las que ya existen conservan el suyo.'),
              const SectionHeader(title: 'Predeterminado del hotel', subtitle: 'Para los tipos sin protocolo propio.'),
              _TemplateTile(
                title: 'Todas las habitaciones',
                template: standard,
                onTap: () => _edit(null, 'Predeterminado del hotel', standard),
              ),
              const SectionHeader(title: 'Por tipo de habitación'),
              for (final type in types)
                Builder(builder: (context) {
                  final template = templates.where((t) => t.roomTypeId == type.id).firstOrNull;
                  return _TemplateTile(
                    title: type.name,
                    template: template,
                    fallback: 'Usa el predeterminado',
                    onTap: () => _edit(type.id, type.name, template ?? standard),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(int? roomTypeId, String title, ChecklistTemplate? base) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ChecklistEditor(roomTypeId: roomTypeId, title: title, base: base)),
    );
    if (saved == true && mounted) setState(() => _data = _load());
  }
}

class _TemplateTile extends StatelessWidget {
  final String title;
  final ChecklistTemplate? template;
  final String fallback;
  final VoidCallback onTap;

  const _TemplateTile({required this.title, required this.template, required this.onTap, this.fallback = 'Sin protocolo'});

  @override
  Widget build(BuildContext context) {
    final t = template;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.checklist_rtl, color: kPrimaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  t == null
                      ? fallback
                      : '${t.items.length} pasos · ${t.items.where((i) => i.required).length} obligatorios'
                          '${t.isStandard ? ' · estándar de RoomTrack' : t.updatedAt == null ? '' : ' · ${fmtDate(t.updatedAt!)}'}',
                  style: const TextStyle(color: kMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _ChecklistEditor extends StatefulWidget {
  final int? roomTypeId;
  final String title;
  final ChecklistTemplate? base;

  const _ChecklistEditor({required this.roomTypeId, required this.title, required this.base});

  @override
  State<_ChecklistEditor> createState() => _ChecklistEditorState();
}

class _Step {
  final TextEditingController label;
  bool required;

  _Step(String text, this.required) : label = TextEditingController(text: text);
}

class _ChecklistEditorState extends State<_ChecklistEditor> {
  late final List<_Step> _steps = [for (final i in widget.base?.items ?? const []) _Step(i.label, i.required)];
  bool _saving = false;

  @override
  void dispose() {
    for (final s in _steps) {
      s.label.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAsync(
      context,
      () => HotelStore.instance.remote!
          .saveChecklist(widget.roomTypeId, [for (final s in _steps) (label: s.label.text, required: s.required)]),
      success: 'Protocolo guardado: lo usarán las próximas tareas.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  void _move(int index, int by) => setState(() {
        final step = _steps.removeAt(index);
        _steps.insert(index + by, step);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${_steps.length} de 30 pasos como máximo. Los obligatorios deben marcarse antes de dar la habitación por limpia.',
              style: const TextStyle(color: kMuted)),
          const SizedBox(height: 8),
          for (var i = 0; i < _steps.length; i++)
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _steps[i].label,
                      maxLength: 150,
                      decoration: InputDecoration(labelText: 'Paso ${i + 1}', counterText: '', border: InputBorder.none),
                    ),
                  ),
                  Tooltip(
                    message: 'Obligatorio',
                    child: Checkbox(value: _steps[i].required, onChanged: (v) => setState(() => _steps[i].required = v ?? true)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) => switch (action) {
                      'up' => _move(i, -1),
                      'down' => _move(i, 1),
                      _ => setState(() => _steps.removeAt(i).label.dispose()),
                    },
                    itemBuilder: (_) => [
                      if (i > 0) const PopupMenuItem(value: 'up', child: Text('Subir')),
                      if (i < _steps.length - 1) const PopupMenuItem(value: 'down', child: Text('Bajar')),
                      const PopupMenuItem(value: 'remove', child: Text('Quitar')),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (_steps.length < 30)
            OutlinedButton.icon(
              onPressed: () => setState(() => _steps.add(_Step('', true))),
              icon: const Icon(Icons.add),
              label: const Text('Agregar paso'),
            ),
          const SizedBox(height: 16),
          AppButton(text: 'Guardar protocolo', icon: Icons.save, loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
