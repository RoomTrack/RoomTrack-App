import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Security events of the hotel's accounts: sign-ins, failures, role changes, MFA resets... (administrators).
class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  final _remote = HotelStore.instance.remote!;
  final List<AuditEntry> _entries = [];
  String? _action;
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _remote.auditLog(page: _page + 1, action: _action);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.items);
        _page = page.page;
        _totalPages = page.totalPages;
        _total = page.total;
      });
    } on DomainException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String? action) {
    setState(() {
      _action = action;
      _entries.clear();
      _page = 0;
    });
    _next();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _action,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Evento', prefixIcon: Icon(Icons.filter_list)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            for (final entry in AuditEntry.actions.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _filter,
        ),
        SectionHeader(title: '$_total eventos', subtitle: 'Los más recientes primero.'),
        if (_error != null) Text(_error!, style: const TextStyle(color: kError)),
        if (!_loading && _error == null && _entries.isEmpty) const EmptyState(icon: Icons.policy_outlined, message: 'Sin eventos.'),
        for (final entry in _entries)
          AppCard(
            borderColor: entry.succeeded ? null : kError,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(entry.succeeded ? Icons.verified_user_outlined : Icons.gpp_bad_outlined, color: entry.succeeded ? kPrimary : kError),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.actionLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (entry.actorEmail != null) Text('Por ${entry.actorEmail}', style: const TextStyle(color: kMuted)),
                      if (entry.targetEmail != null && entry.targetEmail != entry.actorEmail)
                        Text('Cuenta: ${entry.targetEmail}', style: const TextStyle(color: kMuted)),
                      Text('${fmtDateTime(entry.at)}${entry.ip == null ? '' : ' · ${entry.ip}'}',
                          style: const TextStyle(color: kMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (!_loading && _page < _totalPages)
          TextButton.icon(onPressed: _next, icon: const Icon(Icons.expand_more), label: const Text('Cargar más')),
      ],
    );
  }
}
