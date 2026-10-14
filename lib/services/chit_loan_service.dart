import 'package:sqflite/sqflite.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'loan_service.dart';

/// Chit auction winners waiting for a loan to be set up ("Waiting for setup" on
/// the Loans screen). Every saved auction starts as a pending item.
class ChitLoanService {
  ChitLoanService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  static const _selectItems = '''
    SELECT a.id AS auction_id, a.chit_group_id, g.chit_name, a.month_number, a.auction_date,
           a.winner_member_id, m.member_name, m.phone, a.winner_payout, a.winning_amount,
           a.loan_setup_status, a.loan_id
    FROM chit_auctions a
    JOIN chit_groups g ON g.id = a.chit_group_id
    JOIN chit_members m ON m.id = a.winner_member_id''';

  /// Items with [status] (pending by default), newest auction first.
  Future<List<ChitLoanItem>> items({String status = LoanSetupStatus.pending}) async {
    final db = await _app.database;
    final rows = await db.rawQuery(
        '$_selectItems WHERE a.loan_setup_status = ? ORDER BY a.auction_date DESC, a.id DESC',
        [status]);
    return rows.map(ChitLoanItem.fromMap).toList();
  }

  Future<int> count({String status = LoanSetupStatus.pending}) async {
    final db = await _app.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM chit_auctions WHERE loan_setup_status = ?', [status]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<ChitLoanItem> item(int auctionId) async => _item(await _app.database, auctionId);

  Future<ChitLoanItem> _item(DatabaseExecutor db, int auctionId) async {
    final rows = await db.rawQuery('$_selectItems WHERE a.id = ?', [auctionId]);
    if (rows.isEmpty) throw const ValidationException('Auction not found');
    return ChitLoanItem.fromMap(rows.first);
  }

  /// The chit auction a loan was created from, if any.
  Future<ChitLoanItem?> sourceOf(Loan loan) async {
    final id = loan.sourceChitAuctionId;
    if (id == null) return null;
    final db = await _app.database;
    final rows = await db.rawQuery('$_selectItems WHERE a.id = ?', [id]);
    return rows.isEmpty ? null : ChitLoanItem.fromMap(rows.first);
  }

  /// An existing (not archived) borrower with the member's phone, or with the
  /// same name when the member has no phone.
  Future<int?> matchingBorrower(ChitLoanItem item) async {
    final db = await _app.database;
    final phone = item.memberPhone?.trim() ?? '';
    final rows = phone.isNotEmpty
        ? await db.query('borrowers',
            columns: ['id'], where: 'is_archived = 0 AND phone = ?', whereArgs: [phone], limit: 1)
        : await db.query('borrowers',
            columns: ['id'],
            where: 'is_archived = 0 AND name = ? COLLATE NOCASE',
            whereArgs: [item.memberName.trim()],
            limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Chit contributions this member still owes, counting from the auction month
  /// (info only: months left minus the ones already marked paid).
  Future<int> remainingChitInstallments(ChitLoanItem item) async {
    final db = await _app.database;
    final g = await db.query('chit_groups',
        columns: ['duration_months'], where: 'id = ?', whereArgs: [item.chitId], limit: 1);
    if (g.isEmpty) return 0;
    final months = (g.first['duration_months'] as int) - item.monthNumber + 1;
    final paid = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM chit_contributions '
        'WHERE chit_member_id = ? AND month_number >= ? AND status = ?',
        [item.memberId, item.monthNumber, ContributionStatus.paid]);
    final left = months - ((paid.first['c'] as int?) ?? 0);
    return left < 0 ? 0 : left;
  }

  /// Creates the winner's loan and links it to the auction in ONE transaction, so
  /// a double tap (or a second setup) can never create two loans for one auction.
  /// With [borrowerId] null, a borrower is created from the chit member.
  Future<int> setUpLoan({
    required int auctionId,
    int? borrowerId,
    required String loanName,
    required String repaymentType,
    required double totalPayable,
    required double installment,
    required int installmentCount,
    double finePerDay = 0,
    double lateInterestPercent = 0,
    int graceDays = 0,
    required String startDate,
  }) async {
    final db = await _app.database;
    return db.transaction((txn) async {
      final item = await _item(txn, auctionId);
      if (item.status == LoanSetupStatus.created) {
        throw const ValidationException('A loan was already set up for this chit winner');
      }
      if (item.status == LoanSetupStatus.dismissed) {
        throw const ValidationException('This winner was dismissed. Restore it first.');
      }
      final now = nowStamp();
      final borrower = borrowerId ??
          await txn.insert('borrowers', {
            'name': item.memberName.trim(),
            'phone': (item.memberPhone == null || item.memberPhone!.trim().isEmpty)
                ? null
                : item.memberPhone!.trim(),
            'is_archived': 0,
            'created_at': now,
            'updated_at': now,
          });
      final loanId = await LoanService.insertLoan(txn,
          borrowerId: borrower,
          loanName: loanName,
          totalPayable: totalPayable,
          installment: installment,
          installmentCount: installmentCount,
          finePerDay: finePerDay,
          startDate: startDate,
          repaymentType: repaymentType,
          lateInterestPercent: lateInterestPercent,
          graceDays: graceDays,
          sourceChitAuctionId: auctionId);
      final updated = await txn.update(
          'chit_auctions', {'loan_setup_status': LoanSetupStatus.created, 'loan_id': loanId},
          where: 'id = ? AND loan_setup_status = ?',
          whereArgs: [auctionId, LoanSetupStatus.pending]);
      if (updated != 1) {
        throw const ValidationException('A loan was already set up for this chit winner');
      }
      return loanId;
    });
  }

  /// "Not a loan": hides a pending item (it can be restored).
  Future<void> dismiss(int auctionId) =>
      _move(auctionId, LoanSetupStatus.pending, LoanSetupStatus.dismissed);

  /// Puts a dismissed item back in the waiting list.
  Future<void> restore(int auctionId) =>
      _move(auctionId, LoanSetupStatus.dismissed, LoanSetupStatus.pending);

  Future<void> _move(int auctionId, String from, String to) async {
    final db = await _app.database;
    final n = await db.update('chit_auctions', {'loan_setup_status': to},
        where: 'id = ? AND loan_setup_status = ?', whereArgs: [auctionId, from]);
    if (n != 1) {
      throw ValidationException('Only ${LoanSetupStatus.label(from).toLowerCase()} items '
          'can be ${to == LoanSetupStatus.dismissed ? 'dismissed' : 'restored'}');
    }
  }
}
