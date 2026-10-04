import 'dart:math' as math;

import '../core/format.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'loan_service.dart';
import 'settings_service.dart';

class TodayItem {
  const TodayItem({
    required this.summary,
    required this.due,
    required this.paidToday,
    required this.missedToday,
  });
  final LoanSummary summary;
  final double due;
  final double paidToday;
  final bool missedToday;

  bool get isCollected => paidToday >= due - kEps;
  double get stillDue => math.max(0.0, round2(due - paidToday));
}

class DashboardData {
  const DashboardData({
    required this.expected,
    required this.collected,
    required this.pendingBorrowers,
    required this.activeLoans,
    required this.activeChits,
    required this.items,
    required this.backupDue,
  });
  final double expected;
  final double collected;
  final int pendingBorrowers;
  final int activeLoans;
  final int activeChits;
  final List<TodayItem> items;
  final bool backupDue;
}

class DailyReport {
  const DailyReport({
    required this.date,
    required this.collected,
    required this.fines,
    required this.chitCollected,
    required this.expected,
    required this.rows,
  });
  final String date;
  final double collected;
  final double fines;
  final double chitCollected;

  /// Only known for today (it depends on the live schedule).
  final double? expected;
  final List<PaymentRow> rows;
}

class MonthlyReport {
  const MonthlyReport({
    required this.month,
    required this.loanCollected,
    required this.fines,
    required this.chitCollected,
    required this.commissions,
    required this.paymentCount,
  });
  final String month;
  final double loanCollected;
  final double fines;
  final double chitCollected;
  final double commissions;
  final int paymentCount;
}

class OverallReport {
  const OverallReport({
    required this.totalLent,
    required this.totalCollected,
    required this.outstanding,
    required this.totalFines,
    required this.activeLoans,
    required this.closedLoans,
    required this.activeChits,
    required this.totalCommissions,
    required this.totalDividends,
    required this.chitCollected,
  });
  final double totalLent;
  final double totalCollected;
  final double outstanding;
  final double totalFines;
  final int activeLoans;
  final int closedLoans;
  final int activeChits;
  final double totalCommissions;
  final double totalDividends;
  final double chitCollected;
}

/// "Today" / "this month" figures key off `created_at` (when money was
/// actually collected), not the schedule slot the payment covers.
class ReportService {
  ReportService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  Future<double> _sum(String sql, List<Object?> args) async {
    final db = await _app.database;
    final r = await db.rawQuery(sql, args);
    return round2(((r.first.values.first as num?) ?? 0).toDouble());
  }

  Future<int> _count(String sql, List<Object?> args) async {
    final db = await _app.database;
    final r = await db.rawQuery(sql, args);
    return (r.first.values.first as int?) ?? 0;
  }

  Future<List<TodayItem>> todaySchedule() async {
    final db = await _app.database;
    final today = todayKey();
    final todayDate = dateOnly(DateTime.now());
    final summaries = await LoanService(_app).summaries(status: RecordStatus.active);
    final rows = await db.rawQuery(
        "SELECT loan_id, COALESCE(SUM(amount_paid),0) AS paid, "
        "SUM(CASE WHEN status = 'missed' THEN 1 ELSE 0 END) AS missed "
        'FROM loan_payments WHERE created_at LIKE ? GROUP BY loan_id',
        ['$today%']);
    final paid = <int, double>{};
    final missed = <int, bool>{};
    for (final r in rows) {
      final id = r['loan_id'] as int;
      paid[id] = ((r['paid'] as num?) ?? 0).toDouble();
      missed[id] = ((r['missed'] as num?) ?? 0) > 0;
    }
    final items = <TodayItem>[];
    for (final s in summaries) {
      if (parseDate(s.loan.startDate).isAfter(todayDate)) continue;
      final p = paid[s.loan.id] ?? 0;
      if (s.isCleared && p <= kEps) continue;
      items.add(TodayItem(
        summary: s,
        due: round2(math.min(s.loan.dailyPayment, s.outstanding + p)),
        paidToday: round2(p),
        missedToday: missed[s.loan.id] ?? false,
      ));
    }
    int rank(TodayItem i) => i.isCollected ? 2 : (i.missedToday ? 1 : 0);
    items.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (a.summary.loan.borrowerName ?? '')
          .toLowerCase()
          .compareTo((b.summary.loan.borrowerName ?? '').toLowerCase());
    });
    return items;
  }

  Future<DashboardData> dashboard() async {
    final today = todayKey();
    final items = await todaySchedule();
    final collected = await _sum(
        'SELECT COALESCE(SUM(amount_paid),0) FROM loan_payments WHERE created_at LIKE ?',
        ['$today%']);
    final pending = items
        .where((i) => !i.isCollected && !i.missedToday)
        .map((i) => i.summary.loan.borrowerId)
        .toSet()
        .length;
    return DashboardData(
      expected: round2(items.fold(0.0, (s, i) => s + i.due)),
      collected: collected,
      pendingBorrowers: pending,
      activeLoans: await _count(
          'SELECT COUNT(*) FROM loans WHERE status = ?', [RecordStatus.active]),
      activeChits: await _count(
          'SELECT COUNT(*) FROM chit_groups WHERE status = ?', [RecordStatus.active]),
      items: items,
      backupDue: await _backupDue(),
    );
  }

  Future<bool> _backupDue() async {
    final settings = SettingsService(_app);
    if (!await settings.getBool(SettingsKeys.backupReminder)) return false;
    final last = await settings.get(SettingsKeys.lastBackupAt);
    if (last == null) return true;
    final at = DateTime.tryParse(last);
    return at == null || DateTime.now().difference(at).inDays >= 7;
  }

  Future<DailyReport> daily(String date) async {
    final rows = await LoanService(_app).paymentRows(createdLike: date);
    double? expected;
    if (date == todayKey()) {
      expected = round2((await todaySchedule()).fold(0.0, (s, i) => s + i.due));
    }
    return DailyReport(
      date: date,
      collected: round2(rows.fold(0.0, (s, r) => s + r.payment.amountPaid)),
      fines: round2(rows.fold(0.0, (s, r) => s + r.payment.fineAmount)),
      chitCollected: await _sum(
          'SELECT COALESCE(SUM(amount),0) FROM chit_contributions '
          'WHERE status = ? AND payment_date = ?',
          [ContributionStatus.paid, date]),
      expected: expected,
      rows: rows,
    );
  }

  Future<MonthlyReport> monthly(String yyyyMm) async {
    final like = '$yyyyMm%';
    return MonthlyReport(
      month: yyyyMm,
      loanCollected: await _sum(
          'SELECT COALESCE(SUM(amount_paid),0) FROM loan_payments WHERE created_at LIKE ?',
          [like]),
      fines: await _sum(
          'SELECT COALESCE(SUM(fine_amount),0) FROM loan_payments WHERE created_at LIKE ?',
          [like]),
      chitCollected: await _sum(
          'SELECT COALESCE(SUM(amount),0) FROM chit_contributions '
          'WHERE status = ? AND payment_date LIKE ?',
          [ContributionStatus.paid, like]),
      commissions: await _sum(
          'SELECT COALESCE(SUM(commission_amount),0) FROM chit_auctions WHERE auction_date LIKE ?',
          [like]),
      paymentCount: await _count(
          'SELECT COUNT(*) FROM loan_payments WHERE created_at LIKE ? AND amount_paid > 0',
          [like]),
    );
  }

  Future<OverallReport> overall() async {
    final summaries = await LoanService(_app).summaries(status: RecordStatus.active);
    return OverallReport(
      totalLent: await _sum('SELECT COALESCE(SUM(total_payable),0) FROM loans', []),
      totalCollected:
          await _sum('SELECT COALESCE(SUM(amount_paid),0) FROM loan_payments', []),
      outstanding: round2(summaries.fold(0.0, (s, x) => s + x.outstanding)),
      totalFines: await _sum('SELECT COALESCE(SUM(fine_amount),0) FROM loan_payments', []),
      activeLoans: summaries.length,
      closedLoans: await _count('SELECT COUNT(*) FROM loans WHERE status IN (?, ?)',
          [RecordStatus.completed, RecordStatus.archived]),
      activeChits: await _count(
          'SELECT COUNT(*) FROM chit_groups WHERE status = ?', [RecordStatus.active]),
      totalCommissions:
          await _sum('SELECT COALESCE(SUM(commission_amount),0) FROM chit_auctions', []),
      totalDividends:
          await _sum('SELECT COALESCE(SUM(dividend_pool),0) FROM chit_auctions', []),
      chitCollected: await _sum(
          'SELECT COALESCE(SUM(amount),0) FROM chit_contributions WHERE status = ?',
          [ContributionStatus.paid]),
    );
  }
}
