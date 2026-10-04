import 'package:intl/intl.dart';

final NumberFormat _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final DateFormat _dateKey = DateFormat('yyyy-MM-dd');
final DateFormat _monthKey = DateFormat('yyyy-MM');

/// ₹1,23,456.00 style formatting.
String money(num value) => _money.format(value);

/// Rounds to 2 decimals. All money math in services goes through this.
double round2(double v) => (v * 100).roundToDouble() / 100;

/// Tolerance for comparing rupee amounts.
const double kEps = 0.005;

String dateKey(DateTime d) => _dateKey.format(d);
String monthKey(DateTime d) => _monthKey.format(d);
String todayKey() => dateKey(DateTime.now());
String nowStamp() => DateTime.now().toIso8601String();

/// Parses `yyyy-MM-dd` (or a full timestamp) into a date with no time part.
DateTime parseDate(String s) {
  final d = DateTime.parse(s.length >= 10 ? s.substring(0, 10) : s);
  return DateTime(d.year, d.month, d.day);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [a] to [b] (negative if b is before a).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// Full months from [start] to [end], counting a month only once its day is reached.
int monthsBetween(DateTime start, DateTime end) {
  var m = (end.year - start.year) * 12 + end.month - start.month;
  if (end.day < start.day) m -= 1;
  return m;
}

String prettyDate(String? s) {
  if (s == null || s.isEmpty) return '—';
  try {
    return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

String prettyStamp(String? s) {
  if (s == null || s.isEmpty) return '—';
  try {
    return DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

String prettyMonth(String yyyyMm) {
  try {
    return DateFormat('MMMM yyyy').format(DateTime.parse('$yyyyMm-01'));
  } catch (_) {
    return yyyyMm;
  }
}

/// Parses user-typed amounts like "1,500" or " 300.5 ".
double? parseAmount(String s) => double.tryParse(s.trim().replaceAll(',', ''));
