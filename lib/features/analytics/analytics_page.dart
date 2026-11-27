import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/remote_hotel.dart';
import '../../core/backend/remote_reports.dart';
import '../../core/hotel_store.dart';
import '../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/ui.dart';

/// Productivity, attention times and satisfaction by period (US-24, US-25, US-26). With the backend the figures are
/// its reports for the period and the CSV files are the ones it builds (US-34); in the demo the app calculates them.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  int _days = 30;
  DateTimeRange? _custom;

  /// Changes when the administrator picks another period: the backend's reports are asked again.
  String get _selection => _custom == null ? 'last-$_days' : '${_custom!.start}-${_custom!.end}';

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
      final remote = store.remote;

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
          AppButton(
            text: 'Exportar Excel (CSV)',
            icon: Icons.table_view_outlined,
            outlined: true,
            onPressed: () => remote == null ? _export(context, store, period) : _exportRemote(context, remote, period),
          ),
          if (remote != null) ...[
            _RemoteReports(key: ValueKey(_selection), period: period),
            const SectionHeader(title: 'Tendencia semanal', subtitle: 'Minutos de limpieza por semana'),
            AppCard(child: TrendChart(points: trend)),
          ] else ...[
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
        ],
      );
    });
  }

  /// US-34: the administrator picks a report and the backend builds its CSV for the period.
  Future<void> _exportRemote(BuildContext context, RemoteHotel remote, Period period) async {
    final report = await showModalBottomSheet<CsvReport>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('¿Qué reporte exportas?', style: TextStyle(fontWeight: FontWeight.w900))),
            for (final r in CsvReport.values)
              ListTile(leading: const Icon(Icons.table_view_outlined), title: Text(r.label), onTap: () => Navigator.pop(sheetContext, r)),
          ],
        ),
      ),
    );
    if (report == null || !context.mounted) return;
    String? csv;
    await runAsync(context, () async => csv = await remote.exportCsv(report, period));
    if (csv == null || !context.mounted) return;
    await _showCsv(context, csv!, report.label);
  }

  Future<void> _export(BuildContext context, HotelStore store, Period period) => _showCsv(context, store.exportCsv(period), null);

  Future<void> _showCsv(BuildContext context, String csv, String? title) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title ?? 'Reporte exportado'),
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

/// The backend's reports of the period: productivity (US-24), attention times (US-25) and satisfaction (US-26).
class _RemoteReports extends StatefulWidget {
  final Period period;

  const _RemoteReports({super.key, required this.period});

  @override
  State<_RemoteReports> createState() => _RemoteReportsState();
}

class _RemoteReportsState extends State<_RemoteReports> {
  late Future<(StaffReport, ServiceTimes, Satisfaction?)> _reports = _load();

  Future<(StaffReport, ServiceTimes, Satisfaction?)> _load() async {
    final remote = HotelStore.instance.remote!;
    final staff = remote.staffReport(widget.period);
    final times = remote.serviceTimes(widget.period);
    Satisfaction? satisfaction;
    try {
      satisfaction = await remote.satisfaction(widget.period);
    } on Exception {
      // The evaluations live in another service: without them the rest of the reports still show.
    }
    return (await staff, await times, satisfaction);
  }

  static String _minutes(double? value) => value == null ? '-' : '${value.toStringAsFixed(0)} min';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${snapshot.error}', style: const TextStyle(color: kError)),
                const SizedBox(height: 8),
                AppButton(text: 'Reintentar', icon: Icons.refresh, outlined: true, onPressed: () => setState(() => _reports = _load())),
              ],
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator());
        final (staff, times, satisfaction) = data;
        final maxCompleted = staff.collaborators.fold<int>(1, (m, c) => max(m, c.total)).toDouble();
        final busiest = staff.areas.isEmpty ? null : staff.areas.reduce((a, b) => (a.avgWorkMinutes ?? 0) >= (b.avgWorkMinutes ?? 0) ? a : b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: 'Productividad del personal', subtitle: '${staff.totalCompleted} tareas terminadas en el período'),
            AppCard(
              child: Column(
                children: [
                  if (staff.collaborators.isEmpty) const Text('Nadie terminó tareas en el período.', style: TextStyle(color: kMuted)),
                  for (final c in staff.collaborators)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BarRow(label: c.name, value: c.total.toDouble(), max: maxCompleted, display: '${c.total}'),
                          Text('${c.cleanings} limpiezas · ${c.incidents} incidencias · ${c.requests} solicitudes · '
                              '${_minutes(c.avgWorkMinutes)} promedio',
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
                  for (final a in staff.areas)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.area.icon, color: kPrimaryDark),
                      title: Text(a.area.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${a.completed} atendidas · ${a.collaborators} colaboradores · '
                          '${a.perCollaborator.toStringAsFixed(1)} por persona'),
                      trailing: Text(_minutes(a.avgWorkMinutes), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  if (busiest != null && (busiest.avgWorkMinutes ?? 0) > 0)
                    InfoRow(Icons.insights, '${busiest.area.label} es el área que más demora por tarea en el período.', color: kWarning),
                ],
              ),
            ),
            const SectionHeader(title: 'Tiempos de atención', subtitle: 'Promedios: espera hasta iniciar · trabajo · total'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, indicator) in [
                    ('Limpieza de habitaciones', times.cleaning),
                    ('Incidencias', times.incidents),
                    ('Solicitudes de huéspedes', times.requests),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(indicator.count == 0
                          ? 'Sin actividad en el período'
                          : '${_minutes(indicator.response)} · ${_minutes(indicator.work)} · ${indicator.count} medidas'),
                      trailing: Text(_minutes(indicator.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
            ),
            const SectionHeader(title: 'Satisfacción del huésped'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (satisfaction == null) const Text('Las evaluaciones no respondieron. Inténtalo más tarde.', style: TextStyle(color: kMuted)),
                  if (satisfaction != null) ...[
                    BarRow(
                      label: 'General',
                      value: satisfaction.overall.average ?? 0,
                      max: 5,
                      display: satisfaction.overall.average == null ? '-' : '${satisfaction.overall.average!.toStringAsFixed(1)} ★',
                      color: (satisfaction.overall.average ?? 0) >= 4 ? kSuccess : kWarning,
                    ),
                    for (final entry in satisfaction.byArea.entries)
                      BarRow(
                        label: entry.key.label,
                        value: entry.value.average ?? 0,
                        max: 5,
                        display: entry.value.average == null ? '-' : '${entry.value.average!.toStringAsFixed(1)} ★',
                        color: (entry.value.average ?? 0) >= 4 ? kSuccess : kWarning,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      satisfaction.overall.count == 0
                          ? 'Sin evaluaciones en el período.'
                          : '${satisfaction.overall.count} evaluaciones · '
                              '${satisfaction.overall.satisfiedPercent?.toStringAsFixed(0) ?? '-'}% satisfechos (4 o 5 ★)',
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
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
