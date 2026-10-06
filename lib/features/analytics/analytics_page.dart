import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Productivity, attention times and satisfaction by period (US-24, US-25, US-26).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  int _days = 30;
  DateTimeRange? _custom;

  Period _period(HotelStore store) =>
      _custom == null ? Period.lastDays(store.now, _days) : Period(_custom!.start, _custom!.end.add(const Duration(hours: 23, minutes: 59)));

  @override
  Widget build(BuildContext context) {
    return StoreBuilder(builder: (context, store) {
      final period = _period(store);
      final productivity = store.productivity(period);
      final areas = store.areaComparison(period);
      final byType = store.cleaningMinutesByType(period);
      final trend = store.weeklyTrend(period);
      final satisfaction = store.satisfactionByArea(period);
      final byStaff = store.satisfactionByStaff(period);
      final maxCompleted = productivity.fold<int>(1, (m, p) => max(m, p.completed)).toDouble();
      final slowestArea = areas.reduce((a, b) => a.delayed >= b.delayed ? a : b);

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (store.remote != null) const _MonthlyMetricsCard(),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final days in [7, 30])
                ChoiceChip(
                  label: Text('Últimos $days días'),
                  selected: _custom == null && _days == days,
                  onSelected: (_) => setState(() {
                    _custom = null;
                    _days = days;
                  }),
                ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_custom == null ? 'Rango…' : '${fmtDate(_custom!.start)} - ${fmtDate(_custom!.end)}'),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: store.now.subtract(const Duration(days: 365)),
                    lastDate: store.now,
                  );
                  if (picked != null) setState(() => _custom = picked);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppButton(text: 'Exportar Excel (CSV)', icon: Icons.table_view_outlined, outlined: true, onPressed: () => _export(context, store, period)),
          const SectionHeader(title: 'Productividad del personal', subtitle: 'Tareas completadas, promedio y pendientes'),
          AppCard(
            child: Column(
              children: [
                for (final p in productivity)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BarRow(label: p.user.name, value: p.completed.toDouble(), max: maxCompleted, display: '${p.completed}'),
                        Text('${p.user.role.label} · ${p.avgMinutes.toStringAsFixed(0)} min promedio · ${p.pending} pendientes',
                            style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader(title: 'Comparación entre áreas'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in areas)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.area.icon, color: kPrimaryDark),
                    title: Text(a.area.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${a.completed} atendidas · ${a.pending} pendientes · ${a.avgMinutes.toStringAsFixed(0)} min prom.'),
                    trailing: Pill(text: '${a.delayed} con demora', color: a.delayed > 0 ? kWarning : kSuccess),
                  ),
                if (slowestArea.delayed > 0)
                  InfoRow(Icons.insights, '${slowestArea.area.label} presenta más demoras en el período.', color: kWarning),
              ],
            ),
          ),
          const SectionHeader(title: 'Tiempos de atención'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Limpieza promedio por tipo', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final entry in byType.entries)
                  BarRow(label: entry.key.label, value: entry.value, max: 60, display: '${entry.value.toStringAsFixed(0)} min', color: kWarning),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(child: Text('Resolución de incidencias', style: TextStyle(fontWeight: FontWeight.w800))),
                    Text('${store.incidentResolutionHours(period).toStringAsFixed(1)} h', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ],
                ),
                const Text('Desde el reporte hasta el cierre', style: TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
          ),
          const SectionHeader(title: 'Tendencia semanal', subtitle: 'Minutos de limpieza por semana'),
          AppCard(child: TrendChart(points: trend)),
          const SectionHeader(title: 'Satisfacción del huésped'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in satisfaction.entries)
                  BarRow(
                    label: entry.key.label,
                    value: entry.value,
                    max: 5,
                    display: entry.value == 0 ? '-' : '${entry.value.toStringAsFixed(1)} ★',
                    color: entry.value >= 4 ? kSuccess : kWarning,
                  ),
                const Divider(height: 24),
                const Text('Por colaborador', style: TextStyle(fontWeight: FontWeight.w800)),
                if (byStaff.isEmpty) const Text('Sin evaluaciones en el período.', style: TextStyle(color: kMuted)),
                for (final s in byStaff)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(s.user, radius: 16),
                    title: Text(s.user.name),
                    subtitle: Text('${s.user.role.label} · ${s.count} evaluaciones'),
                    trailing: Text('${s.average.toStringAsFixed(1)} ★', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Future<void> _export(BuildContext context, HotelStore store, Period period) async {
    final csv = store.exportCsv(period);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reporte exportado'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Se copió al portapapeles en formato CSV (ábrelo con Excel).', style: TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              SelectableText(csv, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
      ),
    );
  }
}

class TrendChart extends StatelessWidget {
  final List<TrendPoint> points;

  const TrendChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<double>(1, (m, p) => max(m, p.cleaningMinutes));
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(point.cleaningMinutes == 0 ? '-' : point.cleaningMinutes.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Container(
                      height: 100 * (point.cleaningMinutes / maxValue),
                      decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(8)),
                    ),
                    const SizedBox(height: 4),
                    Text('${point.weekStart.day}/${point.weekStart.month}', style: const TextStyle(fontSize: 10, color: kMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Revenue, bookings and occupancy of the month, computed by the backend's analytics service.
class _MonthlyMetricsCard extends StatefulWidget {
  const _MonthlyMetricsCard();

  @override
  State<_MonthlyMetricsCard> createState() => _MonthlyMetricsCardState();
}

class _MonthlyMetricsCardState extends State<_MonthlyMetricsCard> {
  late final Future<MonthlyMetrics> _metrics = HotelStore.instance.remote!.monthlyMetrics();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _metrics,
      builder: (context, snapshot) {
        final m = snapshot.data;
        return AppCard(
          color: kSoftGreen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Este mes (backend)', style: TextStyle(fontFamily: kSerif, fontSize: 20)),
              const SizedBox(height: 8),
              if (snapshot.hasError) Text('${snapshot.error}', style: const TextStyle(color: kError)),
              if (m == null && !snapshot.hasError) const LinearProgressIndicator(),
              if (m != null)
                Wrap(
                  spacing: 18,
                  runSpacing: 10,
                  children: [
                    _Metric('Ingresos', money(m.revenue)),
                    _Metric('Reservas', '${m.bookings}'),
                    _Metric('Ocupación', '${(m.occupancyRate <= 1 ? m.occupancyRate * 100 : m.occupancyRate).toStringAsFixed(0)}%'),
                    _Metric('Canceladas', '${m.cancelled}'),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary)),
          Text(label, style: const TextStyle(color: kMuted)),
        ],
      );
}
