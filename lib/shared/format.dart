String _two(int n) => n.toString().padLeft(2, '0');

String money(double value) => '\$${value.toStringAsFixed(2)}';

String fmtDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

String timeAgo(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'hace ${diff.inDays} d';
  return fmtDate(d);
}

const List<String> _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// `10 oct`, as written in the mockups.
String fmtDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// `11:00 a. m.`
String fmtHour12(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${_two(d.minute)} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// `hoy`, `mañana` or `el 13 oct`.
String relativeDay(DateTime d, DateTime now) {
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return switch (days) {
    0 => 'hoy',
    1 => 'mañana',
    -1 => 'ayer',
    _ => 'el ${fmtDayMonth(d)}',
  };
}
