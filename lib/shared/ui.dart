import 'package:flutter/material.dart';

import '../core/hotel_store.dart';
import '../core/permissions.dart';
import '../domain/models.dart';

// Palette taken from the RoomTrack mockups: warm cream, deep green and gold.
const Color kPrimary = Color(0xFF1E433D);
const Color kPrimaryDark = Color(0xFF15302B);
const Color kSecondary = Color(0xFF1F2A27);
const Color kGold = Color(0xFFB08A4E);
const Color kMuted = Color(0xFF6E736D);
const Color kError = Color(0xFFC0392B);
const Color kSuccess = Color(0xFF2E7D5B);
const Color kWarning = Color(0xFFD08A2E);
const Color kSurface = Color(0xFFF6F2EA);
const Color kCardSurface = Color(0xFFFFFDF9);
const Color kSoftGreen = Color(0xFFE3ECE7);
const Color kLine = Color(0xFFECE5D8);

/// Serif used for page titles and hotel names in the mockups.
const String kSerif = 'Lora';

/// Rebuilds whenever the hotel changes, which is how every screen stays live.
class StoreBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, HotelStore store) builder;

  const StoreBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final store = HotelStore.instance;
    return ListenableBuilder(listenable: store, builder: (context, _) => builder(context, store));
  }
}

class RoomTrackLogo extends StatelessWidget {
  final double size;
  final bool withName;

  /// White mark with a green door, for dark backgrounds.
  final bool inverted;

  const RoomTrackLogo({super.key, this.size = 34, this.withName = false, this.inverted = false});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: inverted ? Colors.white : kPrimary, borderRadius: BorderRadius.circular(size * 0.28)),
      child: CustomPaint(painter: _ArchPainter(inverted ? kPrimary : Colors.white)),
    );
    if (!withName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.3),
        Text('RoomTrack', style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w700, color: kSecondary)),
      ],
    );
  }
}

/// Arched door of the RoomTrack mark.
class _ArchPainter extends CustomPainter {
  final Color color;

  _ArchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07;
    final left = size.width * 0.3;
    final right = size.width * 0.7;
    final bottom = size.height * 0.84;
    final radius = (right - left) / 2;
    final top = size.height * 0.2 + radius;
    final path = Path()
      ..moveTo(left, bottom)
      ..lineTo(left, top)
      ..arcToPoint(Offset(right, top), radius: Radius.circular(radius))
      ..lineTo(right, bottom);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(size.width * 0.58, size.height * 0.6), size.width * 0.035, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Large serif title with its subtitle, as at the top of every mockup screen.
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeader({super.key, required this.title, this.subtitle = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: kSerif, fontSize: 30, color: kSecondary, height: 1.15)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

/// Round white bell button of the mockup header.
class CircleIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final String tooltip;

  const CircleIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: kLine)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 42, height: 42, child: Center(child: icon)),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.borderColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color ?? kCardSurface,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor ?? kLine, width: borderColor == null ? 1 : 1.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool dark;
  final bool outlined;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.dark = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = loading
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Icon(icon ?? Icons.arrow_forward);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: shape, foregroundColor: kSecondary, side: const BorderSide(color: kLine)),
              onPressed: loading ? null : onPressed,
              icon: Icon(icon ?? Icons.arrow_forward),
              label: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: dark ? kSecondary : kPrimary,
                foregroundColor: Colors.white,
                shape: shape,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: loading ? null : onPressed,
              icon: iconWidget,
              label: Text(text),
            ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.subtitle = '', this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kMuted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, color: kPrimary, size: 40),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({super.key, this.message = 'Cargando...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kPrimary),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const Pill({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class PriorityPill extends StatelessWidget {
  final Priority priority;

  const PriorityPill(this.priority, {super.key});

  @override
  Widget build(BuildContext context) => Pill(
        text: priority.label,
        color: priority.color,
        icon: priority == Priority.urgent ? Icons.priority_high : null,
      );
}

class UserAvatar extends StatelessWidget {
  final AppUser? user;
  final double radius;

  const UserAvatar(this.user, {super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final url = user?.photoUrl ?? '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: kSoftGreen,
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      onForegroundImageError: url.isEmpty ? null : (_, _) {},
      child: Text(user?.initials ?? '?', style: TextStyle(color: kPrimaryDark, fontWeight: FontWeight.w900, fontSize: radius * 0.75)),
    );
  }
}

class ProgressLine extends StatelessWidget {
  final double value;
  final Color color;

  const ProgressLine(this.value, {super.key, this.color = kPrimary});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(value: value, minHeight: 8, color: color, backgroundColor: kLine),
      );
}

/// Shown when a role reaches a screen of another role (US-01, escenario 3).
class RoleGuard extends StatelessWidget {
  final Feature feature;
  final Widget child;

  const RoleGuard({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    final role = HotelStore.instance.currentUser?.role;
    if (role != null && canAccess(role, feature)) return child;
    return Scaffold(
      appBar: AppBar(),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: kError),
              SizedBox(height: 12),
              Text('Acceso denegado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('Tu rol no tiene permiso para usar esta función.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> openPage<T>(BuildContext context, Feature feature, Widget page) {
  return Navigator.push<T>(context, MaterialPageRoute(builder: (_) => RoleGuard(feature: feature, child: page)));
}

void showAppSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? kError : null));
}

/// Runs a store action and turns business rule errors into a snack bar. Returns true on success.
bool runAction(BuildContext context, void Function() action, {String? success}) {
  try {
    action();
    if (success != null) showAppSnack(context, success);
    return true;
  } on DomainException catch (e) {
    showAppSnack(context, e.message, error: true);
    return false;
  }
}

/// Async version of [runAction] for calls to the backend: shows its errors and returns true on success.
Future<bool> runAsync(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showAppSnack(context, success);
    return true;
  } on DomainException catch (e) {
    if (context.mounted) showAppSnack(context, e.message, error: true);
    return false;
  }
}

Future<String?> askText(BuildContext context, {required String title, String label = '', String initial = '', int maxLines = 1}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Aceptar')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Confirmar'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const InfoRow(this.icon, this.text, {super.key, this.color = kMuted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

/// Simple horizontal bar used by the analytics screens.
class BarRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String display;
  final Color color;

  const BarRow({super.key, required this.label, required this.value, required this.max, required this.display, this.color = kPrimary});

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(child: ProgressLine(ratio, color: color)),
          const SizedBox(width: 10),
          SizedBox(width: 64, child: Text(display, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}
