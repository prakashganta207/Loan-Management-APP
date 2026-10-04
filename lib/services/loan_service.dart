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

  Future<int> createLoan({
    required int borrowerId,
    required String loanName,
    required double totalPayable,
    required double dailyPayment,
    required int durationDays,
    double finePerDay = 0,
    required String startDate,
  }) async {
    if (loanName.trim().isEmpty) throw const ValidationException('Loan name is required');
    if (totalPayable <= 0) {
      throw const ValidationException('Total payable must be more than zero');
    }
    if (dailyPayment <= 0) {
      throw const ValidationException('Daily payment must be more than zero');
    }
    if (dailyPayment > totalPayable) {
      throw const ValidationException('Daily payment cannot be more than total payable');
    }
    if (durationDays <= 0) throw const ValidationException('Duration must be at least 1 day');
    if (finePerDay < 0) throw const ValidationException('Fine per day cannot be negative');
    _checkDate(startDate);

    final db = await _app.database;
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
      'daily_payment': round2(dailyPayment),
      'duration_days': durationDays,
      'fine_per_day': round2(finePerDay),
      'start_date': startDate,
      'status': RecordStatus.active,
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
      SELECT p.*, l.loan_name, b.name AS borrower_name
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
    final start = parseDate(loan.startDate);

    var covered = 0;
    for (var i = 0; i < loan.durationDays; i++) {
      if ((paidBySlot[dateKey(addDays(start, i))] ?? 0) >= loan.dailyPayment - kEps) covered++;
    }

    String? nextDue;
    if (outstanding > kEps) {
      // Bounded scan: duration plus ten years of extra slots for loans that run over.
      for (var i = 0; i < loan.durationDays + 3650; i++) {
        final k = dateKey(addDays(start, i));
        if ((paidBySlot[k] ?? 0) < loan.dailyPayment - kEps) {
          nextDue = k;
          break;
        }
      }
    }

    final overdue = nextDue == null ? 0 : math.max(0, daysBetween(parseDate(nextDue), today));
    final remaining = outstanding <= kEps || loan.dailyPayment <= 0
        ? 0
        : (outstanding / loan.dailyPayment - kEps).ceil();

    return LoanSummary(
      loan: loan,
      totalPaid: totalPaid,
      totalFine: totalFine,
      outstanding: outstanding,
      nextDueDate: nextDue,
      coveredDays: covered,
      daysRemaining: remaining,
      overdueDays: overdue,
    );
  }

  /// Fine for paying the [slotDate] instalment on [paidOn].
  static double suggestedFine(Loan loan, String slotDate, DateTime paidOn) {
    final late = daysBetween(parseDate(slotDate), paidOn);
    return late > 0 ? round2(late * loan.finePerDay) : 0;
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
      var date = parseDate(slotDate);
      var first = true;
      var guard = 0;

      while (remaining > kEps) {
        if (++guard > 20000) throw StateError('Payment allocation did not terminate');
        final key = dateKey(date);
        final already = paidBySlot[key] ?? 0;
        final need = round2(loan.dailyPayment - already);
        if (splitAcrossDays && need <= kEps) {
          date = addDays(date, 1);
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
          'scheduled_amount': loan.dailyPayment,
          'amount_paid': round2(alloc),
          'fine_amount': first ? round2(fine) : 0,
          'status': status,
          'note': cleanNote,
          'created_at': now,
        }));
        paidBySlot[key] = already + alloc;
        remaining = round2(remaining - alloc);
        first = false;
        date = addDays(date, 1);
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
      final existing = await _payments(txn, loanId);
      final paid = existing
          .where((p) => p.paymentDate == slotDate)
          .fold<double>(0, (sum, p) => sum + p.amountPaid);
      if (paid >= loan.dailyPayment - kEps) {
        throw ValidationException('${prettyDate(slotDate)} is already paid');
      }
      if (existing.any((p) => p.paymentDate == slotDate && p.status == PaymentStatus.missed)) {
        throw ValidationException('${prettyDate(slotDate)} is already marked missed');
      }
      return txn.insert('loan_payments', {
        'loan_id': loanId,
        'payment_date': slotDate,
        'scheduled_amount': loan.dailyPayment,
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

  static void _checkDate(String s) {
    try {
      parseDate(s);
    } catch (_) {
      throw ValidationException('Invalid date: $s');
    }
  }
}
