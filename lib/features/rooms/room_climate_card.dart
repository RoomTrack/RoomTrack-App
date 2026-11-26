import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';
import '../../core/hotel_store.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

const Map<String, String> _fanSpeeds = {'Low': 'Baja', 'Medium': 'Media', 'High': 'Alta'};

/// The room's thermostat (IoT): the guest of the room, maintenance and administrators read and set it.
class RoomClimateCard extends StatefulWidget {
  final int roomId;

  const RoomClimateCard({super.key, required this.roomId});

  @override
  State<RoomClimateCard> createState() => _RoomClimateCardState();
}

class _RoomClimateCardState extends State<RoomClimateCard> {
  final _remote = HotelStore.instance.remote!;
  RoomClimate? _climate;
  String? _error;
  double _target = 22;
  String _fan = 'Medium';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final climate = await _remote.roomClimate(widget.roomId);
      if (!mounted) return;
      setState(() {
        _climate = climate;
        _error = null;
        _target = climate.temperature.clamp(16, 30).roundToDouble();
        _fan = _fanSpeeds.keys.firstWhere((k) => k.toUpperCase() == climate.fanSpeed, orElse: () => _fan);
      });
    } on DomainException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _apply() async {
    setState(() => _sending = true);
    await runAsync(context, () async {
      final climate = await _remote.setThermostat(widget.roomId, _target, _fan);
      if (mounted) setState(() => _climate = climate);
    }, success: 'Climatización ajustada a ${_target.round()} °C.');
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final climate = _climate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Climatización'),
        AppCard(
          child: _error != null
              ? Row(
                  children: [
                    Expanded(child: Text(_error!, style: const TextStyle(color: kMuted))),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ],
                )
              : climate == null
                  ? const LinearProgressIndicator()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(Icons.thermostat, color: kGold, size: 32),
                            Text('${climate.temperature.toStringAsFixed(1)} °C',
                                style: const TextStyle(fontFamily: kSerif, fontSize: 28, color: kSecondary)),
                            Pill(
                              text: climate.motionDetected ? 'Con presencia' : 'Sin presencia',
                              color: climate.motionDetected ? kSuccess : kMuted,
                              icon: Icons.sensors,
                            ),
                          ],
                        ),
                        if (climate.powerSaving)
                          const InfoRow(Icons.eco_outlined, 'Ahorro de energía activado: no se detectó a nadie en la habitación.', color: kSuccess),
                        if (climate.updatedAt != null)
                          Text('Actualizado ${fmtDateTime(climate.updatedAt!)}', style: const TextStyle(color: kMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text('Temperatura deseada: ${_target.round()} °C', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Slider(
                          value: _target,
                          min: 16,
                          max: 30,
                          divisions: 14,
                          label: '${_target.round()} °C',
                          onChanged: (v) => setState(() => _target = v),
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Ventilador', style: TextStyle(fontWeight: FontWeight.w800)),
                            for (final fan in _fanSpeeds.entries)
                              ChoiceChip(label: Text(fan.value), selected: _fan == fan.key, onSelected: (_) => setState(() => _fan = fan.key)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AppButton(text: 'Aplicar', icon: Icons.ac_unit, outlined: true, loading: _sending, onPressed: _apply),
                      ],
                    ),
        ),
      ],
    );
  }
}
