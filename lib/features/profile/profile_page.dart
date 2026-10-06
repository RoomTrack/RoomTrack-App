import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../core/session.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Contact data, password and notification preferences (US-02, US-22).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AppUser _user = HotelStore.instance.currentUser!;
  late final TextEditingController _name = TextEditingController(text: _user.name);
  late final TextEditingController _email = TextEditingController(text: _user.email);
  late final TextEditingController _phone = TextEditingController(text: _user.phone);
  late final TextEditingController _photo = TextEditingController(text: _user.photoUrl);
  final TextEditingController _current = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _photo, _current, _newPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(child: UserAvatar(_user, radius: 40)),
          const SizedBox(height: 8),
          Center(child: Pill(text: _user.role.label, color: kPrimary)),
          const SectionHeader(title: 'Mis datos'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _photo,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL de foto', prefixIcon: Icon(Icons.photo_camera_outlined)),
          ),
          const SizedBox(height: 12),
          if (store.isRemote)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: InfoRow(Icons.info_outline, 'El backend aún no permite editar estos datos: se guardan solo en este dispositivo.'),
            ),
          AppButton(
            text: 'Guardar cambios',
            icon: Icons.save,
            onPressed: () => runAction(
              context,
              () => store.updateProfile(_user, name: _name.text, email: _email.text, phone: _phone.text, photoUrl: _photo.text),
              success: 'Perfil actualizado.',
            ),
          ),
          const SectionHeader(title: 'Cambiar contraseña'),
          TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
          const SizedBox(height: 10),
          TextField(controller: _newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña')),
          const SizedBox(height: 12),
          AppButton(
            text: 'Actualizar contraseña',
            icon: Icons.lock_reset,
            outlined: true,
            onPressed: () async {
              final remote = store.remote;
              final ok = remote == null
                  ? runAction(context, () => store.changePassword(_user, _current.text, _newPassword.text),
                      success: 'Contraseña actualizada.')
                  : await runAsync(context, () => remote.changePassword(_current.text, _newPassword.text),
                      success: 'Contraseña actualizada.');
              if (ok) {
                _current.clear();
                _newPassword.clear();
              }
            },
          ),
          const SectionHeader(title: 'Notificaciones', subtitle: 'Elige qué avisos recibir.'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                for (final type in _typesFor(_user.role))
                  SwitchListTile(
                    title: Text(type.label),
                    value: _user.wants(type),
                    onChanged: (value) => store.setNotificationPref(_user, type, value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            text: 'Cerrar sesión',
            icon: Icons.logout,
            outlined: true,
            onPressed: () async {
              await SessionStore.clear();
              // The shell listens to the store and goes back to the login.
              final store = HotelStore.instance;
              if (store.remote != null) {
                await store.remote!.signOut();
              } else {
                store.signOut();
              }
            },
          ),
        ],
      );
    });
  }

  List<NotificationType> _typesFor(UserRole role) => switch (role) {
        UserRole.guest => [NotificationType.stay, NotificationType.message],
        UserRole.admin => NotificationType.values.where((t) => t != NotificationType.stay).toList(),
        _ => NotificationType.values.where((t) => t != NotificationType.stay && t != NotificationType.alert).toList(),
      };
}
