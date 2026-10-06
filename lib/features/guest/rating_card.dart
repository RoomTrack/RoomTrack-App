import 'package:flutter/material.dart';

import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Post-stay survey, one score per area plus a comment (US-21).
class RatingCard extends StatefulWidget {
  final Stay stay;

  const RatingCard({super.key, required this.stay});

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> {
  final Map<Area, int> _scores = {Area.housekeeping: 0, Area.reception: 0, Area.maintenance: 0};
  final TextEditingController _comment = TextEditingController();

  static const Map<Area, String> _labels = {
    Area.housekeeping: 'Limpieza',
    Area.reception: 'Atención',
    Area.maintenance: 'Mantenimiento',
  };

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    if (_scores.values.any((v) => v == 0)) {
      showAppSnack(context, 'Califica las tres áreas.', error: true);
      return;
    }
    runAction(
      context,
      () => HotelStore.instance.submitRating(
        widget.stay.id,
        cleaning: _scores[Area.housekeeping]!,
        attention: _scores[Area.reception]!,
        maintenance: _scores[Area.maintenance]!,
        comment: _comment.text,
      ),
      success: '¡Gracias por tu evaluación!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: kPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Cómo fue tu estancia?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          for (final area in _labels.keys)
            Row(
              children: [
                SizedBox(width: 120, child: Text(_labels[area]!, style: const TextStyle(fontWeight: FontWeight.w700))),
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '$star',
                    onPressed: () => setState(() => _scores[area] = star),
                    icon: Icon(star <= _scores[area]! ? Icons.star : Icons.star_border, color: kWarning),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(controller: _comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Comentario (opcional)')),
          const SizedBox(height: 12),
          AppButton(text: 'Enviar evaluación', icon: Icons.send, onPressed: _submit),
        ],
      ),
    );
  }
}
