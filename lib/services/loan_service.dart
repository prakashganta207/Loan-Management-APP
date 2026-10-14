import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';
import '../models/models.dart';

class LoanService {
  LoanService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  static const _selectLoan =
      'SELECT l.*, b.name AS borrower_name FROM loans l JOIN borrowers b ON b.id = l.borrower_id';

  /// Creates a loan. For monthly loans [dailyPayment] is the monthly instalment,
  /// [durationDays] the number of months and [startDate] the first due date.
  Future<int> createLoan({
    required int borrowerId,
    required String loanName,
    required double totalPayable,
    required double dailyPayment,
    required int durationDays,
    double finePerDay = 0,
    required String startDate,
    String repaymentType = RepaymentType.daily,
    double lateInterestPercent = 0,
    int graceDays = 0,
  }) async {
    final db = await _app.database;
    return insertLoan(db,
        borrowerId: borrowerId,
        loanName: loanName,
        totalPayable: totalPayable,
        installment: dailyPayment,
        installmentCount: durationDays,
        finePerDay: finePerDay,
        startDate: startDate,
        repaymentType: repaymentType,
        lateInterestPercent: lateInterestPercent,
        graceDays: graceDays);
  }

  /// Validates and inserts a loan on [db] (a database or an open transaction).
  static Future<int> insertLoan(
    DatabaseExecutor db, {
    required int borrowerId,
    required String loanName,
    required double totalPayable,
    required double installment,
    required int installmentCount,
    double finePerDay = 0,
    required String startDate,
    String repaymentType = RepaymentType.daily,
    double lateInterestPercent = 0,
    int graceDays = 0,
    int? sourceChitAuctionId,
  }) async {
    final monthly = repaymentType == RepaymentType.monthly;
    final what = monthly ? 'Monthly instalment' : 'Daily payment';
    if (!RepaymentType.all.contains(repaymentType)) {
      throw ValidationException('Unknown repayment type: $repaymentType');
    }
    if (loanName.trim().isEmpty) throw const ValidationException('Loan name is required');
    if (totalPayable <= 0) {
      throw const ValidationException('Total payable must be more than zero');
    }
    if (installment <= 0) throw ValidationException('$what must be more than zero');
    if (installment > totalPayable) {
      throw ValidationException('$what cannot be more than total payable');
    }
    if (installmentCount <= 0) {
      throw ValidationException('Duration must be at least 1 ${monthly ? 'month' : 'day'}');
    }
    if (finePerDay < 0) throw const ValidationException('Fine per day cannot be negative');
    if (lateInterestPercent < 0 || lateInterestPercent > 100) {
      throw const ValidationException('Late interest must be between 0 and 100% a month');
    }
    if (graceDays < 0) throw const ValidationException('Grace days cannot be negative');
    _checkDate(startDate);

    final borrower =
        await db.query('borrowers', where: 'id = ?', whereArgs: [borrowerId], limit: 1);
    if (borrower.isEmpty) throw const ValidationException('Choose a borrower');
    if (Borrower.fromMap(borrower.first).isArchived) {
      throw const ValidationException('This borrower is archived. Restore them first.');
    }
    final now = nowStamp();
    return db.insert('loans', {
      'borrower_id': borrowerId,
      'loan_name': loanName.trim(),
      'total_payable': round2(totalPayable),
      'daily_payment': round2(installment),
      'duration_days': installmentCount,
      'fine_per_day': monthly ? 0 : round2(finePerDay),
      'start_date': startDate,
      'status': RecordStatus.active,
      'repayment_type': repaymentType,
      'late_interest_percent': monthly ? lateInterestPercent : 0,
      'grace_days': monthly ? graceDays : 0,
      'source_chit_auction_id': sourceChitAuctionId,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Loan>> listLoans({String? status, int? borrowerId}) async {
    final db = await _app.database;
    final (where, args) = _filter(status, borrowerId);
    final rows = await db.rawQuery(
        '$_selectLoan$where ORDER BY l.start_date DESC, l.id DESC', args);
    return rows.map(Loan.fromMap).toList();
  }

  Future<Loan> getLoan(int id) async => _getLoan(await _app.database, id);

  Future<Loan> _getLoan(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery('$_selectLoan WHERE l.id = ?', [id]);
    if (rows.isEmpty) throw const ValidationException('Loan not found');
    return Loan.fromMap(rows.first);
  }

  Future<List<LoanPayment>> payments(int loanId) async =>
      _payments(await _app.database, loanId);

  Future<List<LoanPayment>> _payments(DatabaseExecutor db, int loanId) async {
    final rows = await db.query('loan_payments',
        where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'payment_date ASC, id ASC');
    return rows.map(LoanPayment.fromMap).toList();
  }

  /// Payment rows with loan + borrower names, newest first.
  Future<List<PaymentRow>> paymentRows({int? borrowerId, String? createdLike}) async {
    final db = await _app.database;
    final where = <String>[];
    final args = <Object?>[];
    if (borrowerId != null) {
      where.add('l.borrower_id = ?');
      args.add(borrowerId);
    }
    if (createdLike != null) {
      where.add('p.created_at LIKE ?');
      args.add('$createdLike%');
    }
    final rows = await db.rawQuery('''
      SELECT p.*, l.loan_name, l.repayment_type, b.name AS borrower_name
      FROM loan_payments p
      JOIN loans l ON l.id = p.loan_id
      JOIN borrowers b ON b.id = l.borrower_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY p.created_at DESC, p.id DESC''', args);
    return rows.map(PaymentRow.fromMap).toList();
  }

  Future<LoanSummary> summary(int loanId) async {
    final db = await _app.database;
    final loan = await _getLoan(db, loanId);
    return computeSummary(loan, await _payments(db, loanId), DateTime.now());
  }

  Future<List<LoanSummary>> summaries({String? status, int? borrowerId}) async {
    final loans = await listLoans(status: status, borrowerId: borrowerId);
    if (loans.isEmpty) return [];
    final db = await _app.database;
    final (where, args) = _filter(status, borrowerId);
    final rows = await db.rawQuery(
        'SELECT p.* FROM loan_payments p JOIN loans l ON l.id = p.loan_id$where '
        'ORDER BY p.payment_date ASC, p.id ASC',
        args);
    final byLoan = <int, List<LoanPayment>>{};
    for (final r in rows) {
      final p = LoanPayment.fromMap(r);
      byLoan.putIfAbsent(p.loanId, () => []).add(p);
    }
    final today = DateTime.now();
    return loans.map((l) => computeSummary(l, byLoan[l.id] ?? const [], today)).toList();
  }

  (String, List<Object?>) _filter(String? status, int? borrowerId) {
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('l.status = ?');
      args.add(status);
    }
    if (borrowerId != null) {
      where.add('l.borrower_id = ?');
      args.add(borrowerId);
    }
    return (where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}', args);
  }

  /// Due date of instalment [i] (0-based): start + i days, or start + i months
  /// clamped to the month's end. Always computed from the start date, never
  /// chained, so 31 Jan → 28/29 Feb → 31 Mar → 30 Apr.
  static DateTime slotDate(Loan loan, int i) {
    final start = parseDate(loan.startDate);
    return loan.isMonthly ? addMonthsClamped(start, i) : addDays(start, i);
  }

  static String slotKey(Loan loan, int i) => dateKey(slotDate(loan, i));

  /// Index of the instalment due on [date], or null when no instalment falls on it.
  static int? slotIndex(Loan loan, String date) {
    final d = parseDate(date);
    final start = parseDate(loan.startDate);
    if (d.isBefore(start)) return null;
    if (!loan.isMonthly) return daysBetween(start, d);
    final i = (d.year - start.year) * 12 + d.month - start.month;
    return slotKey(loan, i) == dateKey(d) ? i : null;
  }

  /// Amount due on instalment [i]: the instalment, except the last one, which is
  /// whatever is left of the total (₹1,000 at ₹300/day → 300, 300, 300, 100).
  static double slotDue(Loan loan, int i) {
    final due = round2(
        math.min(loan.installmentAmount, loan.totalPayable - loan.installmentAmount * i));
    return due < 0 ? 0 : due;
  }

  /// Monthly loans: simple interest on the overdue instalment only —
  /// unpaid × rate% × max(0, days late − grace days) ÷ 30. It is never charged on
  /// the whole loan and never compounds.
  static double lateInterest(Loan loan, double unpaid, int daysLate) {
    final chargeable = math.max(0, daysLate - loan.graceDays);
    return round2(unpaid * loan.lateInterestPercent / 100 * chargeable / 30);
  }

  /// Pure function: everything the UI shows about a loan comes from here.
  static LoanSummary computeSummary(Loan loan, List<LoanPayment> payments, DateTime today) {
    var totalPaid = 0.0;
    var totalFine = 0.0;
    final paidBySlot = <String, double>{};
    for (final p in payments) {
      totalPaid += p.amountPaid;
      totalFine += p.fineAmount;
      paidBySlot[p.paymentDate] = (paidBySlot[p.paymentDate] ?? 0) + p.amountPaid;
    }
    totalPaid = round2(totalPaid);
    totalFine = round2(totalFine);
    final outstanding = math.max(0.0, round2(loan.totalPayable - totalPaid));

    var covered = 0;
    for (var i = 0; i < loan.installmentCount; i++) {
      final due = slotDue(loan, i);
      if (due <= kEps) break;
      if ((paidBySlot[slotKey(loan, i)] ?? 0) >= due - kEps) covered++;
    }

    String? nextDue;
    var nextDueUnpaid = 0.0;
    var overdueCount = 0;
    var accrued = 0.0;
    final todayDate = dateOnly(today);
    if (outstanding > kEps) {
      // Bounded scan: duration plus extra slots (ten years) for loans that run over.
      final extra = loan.isMonthly ? 120 : 3650;
      for (var i = 0; i < loan.installmentCount + extra; i++) {
        final k = slotKey(loan, i);
        final paid = paidBySlot[k] ?? 0;
        if (paid >= loan.installmentAmount - kEps) continue;
        final unpaid = round2(loan.installmentAmount - paid);
        if (nextDue == null) {
          nextDue = k;
          nextDueUnpaid = math.min(unpaid, outstanding);
        }
        final due = slotDate(loan, i);
        if (!due.isBefore(todayDate)) break;
        // Overdue instalment (due before today).
        overdueCount++;
        if (loan.isMonthly) accrued += lateInterest(loan, unpaid, daysBetween(due, todayDate));
        // Stop once the overdue instalments already add up to the whole balance.
        if (overdueCount * loan.installmentAmount >= outstanding - kEps) break;
      }
    }

    final overdue = nextDue == null ? 0 : math.max(0, daysBetween(parseDate(nextDue), today));
    final remaining = outstanding <= kEps || loan.installmentAmount <= 0
        ? 0
        : (outstanding / loan.installmentAmount - kEps).ceil();

    return LoanSummary(
      loan: loan,
      totalPaid: totalPaid,
      totalFine: totalFine,
      outstanding: outstanding,
      nextDueDate: nextDue,
      coveredDays: covered,
      daysRemaining: remaining,
      overdueDays: overdue,
      overdueInstallments: overdueCount,
      accruedLateCharge: round2(accrued),
      nextDueUnpaid: round2(nextDueUnpaid),
      paidBySlot: paidBySlot,
    );
  }

  /// Late charge for paying the [slotDate] instalment on [paidOn].
  /// Daily: late days × fine per day. Monthly: [lateInterest] on [unpaid]
  /// (defaults to the full instalment).
  static double suggestedFine(Loan loan, String slotDate, DateTime paidOn, {double? unpaid}) {
    final late = daysBetween(parseDate(slotDate), paidOn);
    if (late <= 0) return 0;
    if (loan.isMonthly) return lateInterest(loan, unpaid ?? loan.installmentAmount, late);
    return round2(late * loan.finePerDay);
  }

  /// Records money received. With [splitAcrossDays], an amount bigger than one
  /// day's instalment becomes one ledger row per covered schedule day
  /// (₹900 on a ₹300/day loan → 3 rows). The fine goes on the first row.
  Future<List<int>> recordPayment({
    required int loanId,
    required String slotDate,
    required double amount,
    double fine = 0,
    String? note,
    bool splitAcrossDays = true,
  }) async {
    if (amount <= 0) throw const ValidationException('Amount must be more than zero');
    if (fine < 0) throw const ValidationException('Fine cannot be negative');
    _checkDate(slotDate);
    final cleanNote = (note == null || note.trim().isEmpty) ? null : note.trim();

    final db = await _app.database;
    return db.transaction((txn) async {
      final loan = await _getLoan(txn, loanId);
      if (loan.status != RecordStatus.active) {
        throw const ValidationException('Payments can only be recorded on active loans');
      }
      _checkNotBeforeStart(loan, slotDate);
      final startSlot = _requireSlot(loan, slotDate);
      final existing = await _payments(txn, loanId);
      final s = computeSummary(loan, existing, DateTime.now());
      if (amount > s.outstanding + kEps) {
        throw ValidationException(
            'Amount is more than the outstanding balance (${money(s.outstanding)})');
      }

      final paidBySlot = <String, double>{};
      for (final p in existing) {
        paidBySlot[p.paymentDate] = (paidBySlot[p.paymentDate] ?? 0) + p.amountPaid;
      }

      final now = nowStamp();
      final ids = <int>[];
      var running = s.totalPaid;
      var remaining = round2(amount);
      var slot = startSlot;
      var first = true;
      var guard = 0;

      while (remaining > kEps) {
        if (++guard > 20000) throw StateError('Payment allocation did not terminate');
        final key = slotKey(loan, slot);
        final already = paidBySlot[key] ?? 0;
        final need = round2(loan.installmentAmount - already);
        if (splitAcrossDays && need <= kEps) {
          slot++;
          continue;
        }
        final alloc = splitAcrossDays ? math.min(remaining, need) : remaining;
        running = round2(running + alloc);
        final clearsLoan = running >= loan.totalPayable - kEps;
        final status = (alloc >= need - kEps || clearsLoan)
            ? PaymentStatus.paid
            : PaymentStatus.partial;
        ids.add(await txn.insert('loan_payments', {
          'loan_id': loanId,
          'payment_date': key,
          'scheduled_amount': loan.installmentAmount,
          'amount_paid': round2(alloc),
          'fine_amount': first ? round2(fine) : 0,
          'status': status,
          'note': cleanNote,
          'created_at': now,
        }));
        paidBySlot[key] = already + alloc;
        remaining = round2(remaining - alloc);
        first = false;
        slot++;
        if (!splitAcrossDays) break;
      }
      await txn.update('loans', {'updated_at': now}, where: 'id = ?', whereArgs: [loanId]);
      return ids;
    });
  }

  /// Adds a zero-amount 'missed' row for a schedule day.
  Future<int> markMissed({required int loanId, required String slotDate, String? note}) async {
    _checkDate(slotDate);
    final db = await _app.database;
    return db.transaction((txn) async {
      final loan = await _getLoan(txn, loanId);
      if (loan.status != RecordStatus.active) {
        throw const ValidationException('Only active loans can be marked missed');
      }
      _checkNotBeforeStart(loan, slotDate);
      _requireSlot(loan, slotDate);
      final existing = await _payments(txn, loanId);
      final paid = existing
          .where((p) => p.paymentDate == slotDate)
          .fold<double>(0, (sum, p) => sum + p.amountPaid);
      if (paid >= loan.installmentAmount - kEps) {
        throw ValidationException('${prettyDate(slotDate)} is already paid');
      }
      if (existing.any((p) => p.paymentDate == slotDate && p.status == PaymentStatus.missed)) {
        throw ValidationException('${prettyDate(slotDate)} is already marked missed');
      }
      return txn.insert('loan_payments', {
        'loan_id': loanId,
        'payment_date': slotDate,
        'scheduled_amount': loan.installmentAmount,
        'amount_paid': 0,
        'fine_amount': 0,
        'status': PaymentStatus.missed,
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
        'created_at': nowStamp(),
      });
    });
  }

  /// active → completed (only once cleared) → archived. Loans are never deleted.
  Future<void> updateStatus(int loanId, String newStatus) async {
    final db = await _app.database;
    await db.transaction((txn) async {
      final loan = await _getLoan(txn, loanId);
      if (RecordStatus.next(loan.status) != newStatus) {
        throw ValidationException('A ${loan.status} loan cannot be moved to $newStatus');
      }
      if (newStatus == RecordStatus.completed) {
        final s = computeSummary(loan, await _payments(txn, loanId), DateTime.now());
        if (!s.isCleared) {
          throw ValidationException(
              'Outstanding balance is ${money(s.outstanding)}. It must be zero to complete.');
        }
      }
      await txn.update('loans', {'status': newStatus, 'updated_at': nowStamp()},
          where: 'id = ?', whereArgs: [loanId]);
    });
  }

  /// Monthly loans can only be paid against an instalment due date.
  static int _requireSlot(Loan loan, String slotDate) {
    final i = slotIndex(loan, slotDate);
    if (i == null) {
      throw ValidationException(
          '${prettyDate(slotDate)} is not an instalment due date for this loan');
    }
    return i;
  }

  static void _checkNotBeforeStart(Loan loan, String slotDate) {
    if (parseDate(slotDate).isBefore(parseDate(loan.startDate))) {
      throw ValidationException(
          'This loan starts on ${prettyDate(loan.startDate)}. Choose that day or later.');
    }
  }

  static void _checkDate(String s) {
    try {
      parseDate(s);
    } catch (_) {
      throw ValidationException('Invalid date: $s');
    }
  }
}
