import 'package:flutter/material.dart';

import '../../core/backend/remote_reports.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/ui.dart';

/// Post-stay survey: the stay as a whole, one score per area and a comment (US-21). With the backend it is stored
/// there, where the administrator reads it and the satisfaction by area is calculated (US-26).
class RatingCard extends StatefulWidget {
  final Stay stay;

  const RatingCard({super.key, required this.stay});

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> {
  final Map<Area, int> _scores = {Area.housekeeping: 0, Area.reception: 0, Area.maintenance: 0};
  int _overall = 0;
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
    if (_overall == 0 || _scores.values.any((v) => v == 0)) {
      showAppSnack(context, 'Califica tu estancia y las tres áreas.', error: true);
      return;
    }
    final remote = HotelStore.instance.remote;
    if (remote != null && remote.hasStayReviews) {
      runAsync(
        context,
        () => remote.submitStayReview(
          widget.stay.id,
          overall: _overall,
          frontDesk: _scores[Area.reception],
          housekeeping: _scores[Area.housekeeping],
          maintenance: _scores[Area.maintenance],
          comment: _comment.text,
        ),
        success: '¡Gracias por tu evaluación!',
      );
      return;
    }
    runAction(
      context,
      () => HotelStore.instance.submitRating(
        widget.stay.id,
        cleaning: _scores[Area.housekeeping]!,
        attention: _scores[Area.reception]!,
        maintenance: _scores[Area.maintenance]!,
        overall: _overall,
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
          _stars('General', _overall, (star) => setState(() => _overall = star)),
          for (final area in _labels.keys) _stars(_labels[area]!, _scores[area]!, (star) => setState(() => _scores[area] = star)),
          const SizedBox(height: 8),
          TextField(controller: _comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Comentario (opcional)')),
          const SizedBox(height: 12),
          AppButton(text: 'Enviar evaluación', icon: Icons.send, onPressed: _submit),
        ],
      ),
    );
  }

  Widget _stars(String label, int value, ValueChanged<int> onChanged) => Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          for (var star = 1; star <= 5; star++)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '$label $star',
              onPressed: () => onChanged(star),
              icon: Icon(star <= value ? Icons.star : Icons.star_border, color: kWarning),
            ),
        ],
      );
}
