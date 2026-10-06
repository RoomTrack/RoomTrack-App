import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Create, edit role and deactivate staff accounts (US-03).
class StaffAdminPage extends StatelessWidget {
  const StaffAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final staff = store.users.where((u) => u.role.isStaff).toList()
        ..sort((a, b) => a.active == b.active ? a.role.index.compareTo(b.role.index) : (a.active ? -1 : 1));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(text: 'Dar de alta colaborador', icon: Icons.person_add_alt, onPressed: () => _create(context, store)),
          SectionHeader(title: 'Staff Operativo', subtitle: '${staff.where((u) => u.active).length} cuentas activas'),
          for (final user in staff)
            AppCard(
              color: user.active ? null : kLine,
              child: Row(
                children: [
                  UserAvatar(user),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(user.email, style: const TextStyle(color: kMuted, fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Pill(text: user.role.label, color: kPrimary),
                            const SizedBox(width: 6),
                            if (!user.active) const Pill(text: 'Desactivada', color: kError),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _onAction(context, store, user, value),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'role', child: Text('Cambiar rol')),
                      PopupMenuItem(value: 'toggle', child: Text(user.active ? 'Desactivar cuenta' : 'Reactivar cuenta')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _onAction(BuildContext context, HotelStore store, AppUser user, String action) async {
    if (action == 'toggle') {
      if (user.active) {
        final ok = await confirm(context, 'Desactivar cuenta', '${user.name} perderá el acceso de inmediato. Sus tareas abiertas se reasignarán.',
            action: 'Desactivar');
        if (!ok || !context.mounted) return;
      }
      final message = user.active ? 'Cuenta desactivada: perdió el acceso.' : 'Cuenta reactivada.';
      if (store.remote != null) {
        await runAsync(context, () => store.remote!.setActive(user, !user.active), success: message);
      } else {
        runAction(context, () => store.setActive(user, !user.active), success: message);
      }
      return;
    }
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Rol de ${user.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          for (final r in UserRole.values.where((r) => r.isStaff))
            ListTile(
              title: Text(r.label),
              trailing: r == user.role ? const Icon(Icons.check, color: kSuccess) : null,
              onTap: () => Navigator.pop(sheetContext, r),
            ),
        ],
      ),
    );
    if (role == null || !context.mounted) return;
    final message = 'Permisos actualizados a ${role.label}.';
    if (store.remote != null) {
      await runAsync(context, () => store.remote!.changeRole(user, role), success: message);
    } else {
      runAction(context, () => store.changeRole(user, role), success: message);
    }
  }

  Future<void> _create(BuildContext context, HotelStore store) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    var role = UserRole.housekeeping;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nuevo colaborador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo')),
              const SizedBox(height: 8),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
              const SizedBox(height: 8),
              if (store.isRemote)
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña inicial (mín. 8 caracteres)'),
                )
              else
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in UserRole.values.where((r) => r.isStaff))
                    ChoiceChip(label: Text(r.label), selected: role == r, onSelected: (_) => setLocal(() => role = r)),
                ],
              ),
              const SizedBox(height: 14),
              AppButton(text: 'Crear cuenta', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, true)),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    if (store.remote != null) {
      await runAsync(
        context,
        () => store.remote!.createStaff(name: name.text, email: email.text, role: role, password: password.text),
        success: 'Cuenta creada. Enviamos un enlace de verificación a ${email.text.trim()}; al entrar activará su app autenticadora.',
      );
      return;
    }
    try {
      final password = store.createStaff(name: name.text, email: email.text, phone: phone.text, role: role);
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cuenta creada'),
          content: Text('Enviamos las credenciales a ${email.text.trim()}.\n\nContraseña temporal: $password'),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Listo'))],
        ),
      );
    } on DomainException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }
}
