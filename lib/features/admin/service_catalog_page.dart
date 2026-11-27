import 'package:flutter/material.dart';

import '../../core/backend/remote_reports.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// The catalog of services the guests can ask for, with price, area and estimated time (US-33). With the backend it
/// lives there: the guests see the available ones and their requests keep the price of the moment.
class ServiceCatalogPage extends StatelessWidget {
  const ServiceCatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final services = store.services.toList()..sort((a, b) => a.area.index != b.area.index ? a.area.index.compareTo(b.area.index) : a.name.compareTo(b.name));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppButton(text: 'Agregar servicio', icon: Icons.add, onPressed: () => _edit(context, store, null)),
          const SectionHeader(title: 'Servicios', subtitle: 'Los no disponibles no se muestran a los huéspedes.'),
          if (services.isEmpty) const EmptyState(icon: Icons.room_service_outlined, message: 'Aún no hay servicios en el catálogo.'),
          for (final service in services)
            AppCard(
              onTap: () => _edit(context, store, service),
              child: Row(
                children: [
                  Icon(service.icon, color: service.available ? kPrimaryDark : kMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${service.area.label} · ~${service.minutes} min', style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(service.price == 0 ? 'Incluido' : money(service.price), style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (!service.available) const Pill(text: 'No disponible', color: kMuted),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Future<void> _edit(BuildContext context, HotelStore store, ServiceItem? service) async {
    final name = TextEditingController(text: service?.name ?? '');
    final description = TextEditingController(text: service?.description ?? '');
    final price = TextEditingController(text: service == null ? '0' : service.price.toStringAsFixed(2));
    final minutes = TextEditingController(text: service?.etaMinutes?.toString() ?? '');
    var area = service?.area ?? Area.housekeeping;
    var available = service?.available ?? true;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(service == null ? 'Nuevo servicio' : 'Editar servicio', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final a in Area.values)
                    ChoiceChip(label: Text(a.label), selected: area == a, onSelected: (_) => setLocal(() => area = a)),
                ]),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio', helperText: '0 = incluido'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Minutos', helperText: 'Vacío: ${area.etaMinutes} min'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: available,
                  onChanged: (value) => setLocal(() => available = value),
                  title: const Text('Disponible para los huéspedes'),
                ),
                AppButton(text: 'Guardar', icon: Icons.save, onPressed: () => Navigator.pop(sheetContext, 'save')),
                if (service != null) ...[
                  const SizedBox(height: 8),
                  AppButton(text: 'Eliminar', icon: Icons.delete_outline, outlined: true, onPressed: () => Navigator.pop(sheetContext, 'delete')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final remote = store.remote?.hasServiceCatalog == true ? store.remote : null;
    if (action == 'delete') {
      if (remote != null) {
        await runAsync(context, () => remote.deleteService(service!.id), success: 'Servicio eliminado.');
      } else {
        runAction(context, () => store.deleteService(service!.id), success: 'Servicio eliminado.');
      }
      return;
    }
    final amount = double.tryParse(price.text.trim().replaceAll(',', '.'));
    final eta = minutes.text.trim().isEmpty ? null : int.tryParse(minutes.text.trim());
    if (amount == null || (minutes.text.trim().isNotEmpty && eta == null)) {
      showAppSnack(context, 'Revisa el precio y los minutos.', error: true);
      return;
    }
    if (remote != null) {
      await runAsync(
        context,
        () => remote.saveService(existing: service, name: name.text, description: description.text, area: area,
            price: amount, etaMinutes: eta, available: available),
        success: 'Catálogo actualizado.',
      );
    } else {
      runAction(
        context,
        () => store.saveService(existing: service, name: name.text, description: description.text, area: area,
            price: amount, etaMinutes: eta, available: available),
        success: 'Catálogo actualizado.',
      );
    }
  }
}
