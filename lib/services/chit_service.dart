import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'chit_calculator.dart';

class ChitService {
  ChitService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  Future<int> createChit({
    required String name,
    double? chitValue,
    required int members,
    required int durationMonths,
    double commissionPercent = 0,
    String commissionMode = CommissionMode.fromWinner,
    required String startDate,
  }) async {
    _validate(name, chitValue, members, durationMonths, commissionPercent, commissionMode);
    final db = await _app.database;
    final now = nowStamp();
    return db.insert('chit_groups', {
      'chit_name': name.trim(),
      'chit_value': chitValue == null ? null : round2(chitValue),
      'number_of_members': members,
      'duration_months': durationMonths,
      'commission_percent': commissionPercent,
      'commission_mode': commissionMode,
      'start_date': startDate,
      'status': RecordStatus.active,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Edits a chit. Once an auction exists, the money terms are locked.
  Future<void> updateChit({
    required int id,
    required String name,
    double? chitValue,
    required int members,
    required int durationMonths,
    required double commissionPercent,
    required String commissionMode,
    required String startDate,
  }) async {
    _validate(name, chitValue, members, durationMonths, commissionPercent, commissionMode);
    final db = await _app.database;
    await db.transaction((txn) async {
      final current = await _getChit(txn, id);
      final memberCount = await _memberCount(txn, id);
      if (members < memberCount) {
        throw ValidationException('This chit already has $memberCount members');
      }
      final auctions = await txn.query('chit_auctions',
          columns: ['month_number'], where: 'chit_group_id = ?', whereArgs: [id]);
      if (auctions.isNotEmpty) {
        final termsChanged = current.chitValue != chitValue ||
            current.numberOfMembers != members ||
            (current.commissionPercent - commissionPercent).abs() > kEps ||
            current.commissionMode != commissionMode;
        if (termsChanged) {
          throw const ValidationException(
              'Chit value, members and commission are locked after the first auction');
        }
        final lastMonth = auctions.map((r) => r['month_number'] as int).reduce(math.max);
        if (durationMonths < lastMonth) {
          throw ValidationException('Month $lastMonth already has an auction');
        }
      }
      await txn.update(
        'chit_groups',
        {
          'chit_name': name.trim(),
          'chit_value': chitValue == null ? null : round2(chitValue),
          'number_of_members': members,
          'duration_months': durationMonths,
          'commission_percent': commissionPercent,
          'commission_mode': commissionMode,
          'start_date': startDate,
          'updated_at': nowStamp(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  void _validate(
      String name, double? value, int members, int months, double commission, String mode) {
    if (!CommissionMode.all.contains(mode)) {
      throw ValidationException('Unknown commission mode: $mode');
    }
    if (name.trim().isEmpty) throw const ValidationException('Chit name is required');
    if (value != null && value <= 0) {
      throw const ValidationException('Chit value must be more than zero');
    }
    if (members <= 0) throw const ValidationException('Members must be at least 1');
    if (months <= 0) throw const ValidationException('Duration must be at least 1 month');
    if (commission < 0 || commission > 100) {
      throw const ValidationException('Commission must be between 0 and 100%');
    }
  }

  Future<void> setStatus(int id, String newStatus) async {
    final db = await _app.database;
    final chit = await _getChit(db, id);
    if (RecordStatus.next(chit.status) != newStatus) {
      throw ValidationException('A ${chit.status} chit cannot be moved to $newStatus');
    }
    await db.update('chit_groups', {'status': newStatus, 'updated_at': nowStamp()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<ChitGroup> getChit(int id) async => _getChit(await _app.database, id);

  Future<ChitGroup> _getChit(DatabaseExecutor db, int id) async {
    final rows = await db.query('chit_groups', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const ValidationException('Chit not found');
    return ChitGroup.fromMap(rows.first);
  }

  Future<int> _memberCount(DatabaseExecutor db, int chitId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM chit_members WHERE chit_group_id = ? AND membership_status = ?',
        [chitId, MemberStatus.active]);
    return (r.first['c'] as int?) ?? 0;
  }

  static int currentMonth(ChitGroup g, DateTime today) {
    final m = monthsBetween(parseDate(g.startDate), today) + 1;
    return math.max(1, math.min(m, g.durationMonths));
  }

  Future<ChitSummary> summary(int chitId) async {
    final db = await _app.database;
    return _summary(db, await _getChit(db, chitId));
  }

  Future<ChitSummary> _summary(DatabaseExecutor db, ChitGroup g) async {
    final agg = await db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(commission_amount),0) AS comm, '
        'COALESCE(SUM(dividend_pool),0) AS divs FROM chit_auctions WHERE chit_group_id = ?',
        [g.id]);
    return ChitSummary(
      group: g,
      memberCount: await _memberCount(db, g.id!),
      currentMonth: currentMonth(g, DateTime.now()),
      auctionsDone: (agg.first['n'] as int?) ?? 0,
      totalCommission: ((agg.first['comm'] as num?) ?? 0).toDouble(),
      totalDividends: ((agg.first['divs'] as num?) ?? 0).toDouble(),
    );
  }

  Future<List<ChitSummary>> listChits({String? status}) async {
    final db = await _app.database;
    final rows = await db.query('chit_groups',
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status],
        orderBy: 'start_date DESC, id DESC');
    final out = <ChitSummary>[];
    for (final r in rows) {
      out.add(await _summary(db, ChitGroup.fromMap(r)));
    }
    return out;
  }

  Future<List<ChitMember>> members(int chitId) async {
    final db = await _app.database;
    final rows = await db.query('chit_members',
        where: 'chit_group_id = ?', whereArgs: [chitId], orderBy: 'id ASC');
    return rows.map(ChitMember.fromMap).toList();
  }

  Future<int> addMember({required int chitId, required String name, String? phone}) async {
    if (name.trim().isEmpty) throw const ValidationException('Member name is required');
    final db = await _app.database;
    return db.transaction((txn) async {
      final chit = await _getChit(txn, chitId);
      if (chit.status != RecordStatus.active) {
        throw const ValidationException('Members can only be added to active chits');
      }
      final count = await _memberCount(txn, chitId);
      if (count >= chit.numberOfMembers) {
        throw ValidationException('This chit is full (${chit.numberOfMembers} members)');
      }
      return txn.insert('chit_members', {
        'chit_group_id': chitId,
        'member_name': name.trim(),
        'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
        'membership_status': MemberStatus.active,
        'has_won': 0,
        'joined_at': nowStamp(),
      });
    });
  }

  Future<List<ChitAuction>> auctions(int chitId) async {
    final db = await _app.database;
    final rows = await db.rawQuery('''
      SELECT a.*, m.member_name AS winner_name
      FROM chit_auctions a JOIN chit_members m ON m.id = a.winner_member_id
      WHERE a.chit_group_id = ? ORDER BY a.month_number ASC''', [chitId]);
    return rows.map(ChitAuction.fromMap).toList();
  }

  /// Records a month's auction. Everything happens in one transaction so a
  /// member can never be marked winner twice, even with a double tap.
  Future<int> recordAuction({
    required int chitId,
    required int monthNumber,
    required int winnerMemberId,
    required double winningAmount,
    required String auctionDate,
  }) async {
    final db = await _app.database;
    return db.transaction((txn) async {
      final chit = await _getChit(txn, chitId);
      if (chit.status != RecordStatus.active) {
        throw const ValidationException('Auctions can only be recorded on active chits');
      }
      final value = chit.chitValue;
      if (value == null) {
        throw const ValidationException('Set the chit value (edit chit) before recording auctions');
      }
      if (monthNumber < 1 || monthNumber > chit.durationMonths) {
        throw ValidationException('Month must be between 1 and ${chit.durationMonths}');
      }
      final dup = await txn.query('chit_auctions',
          where: 'chit_group_id = ? AND month_number = ?', whereArgs: [chitId, monthNumber]);
      if (dup.isNotEmpty) throw ValidationException('Month $monthNumber already has an auction');

      final mRows = await txn.query('chit_members',
          where: 'id = ? AND chit_group_id = ?', whereArgs: [winnerMemberId, chitId]);
      if (mRows.isEmpty) throw const ValidationException('Winner is not a member of this chit');
      final winner = ChitMember.fromMap(mRows.first);
      if (winner.hasWon) {
        throw ValidationException('${winner.memberName} has already won in this chit');
      }
      if (winner.membershipStatus != MemberStatus.active) {
        throw ValidationException('${winner.memberName} is not an active member');
      }

      final calc = ChitCalculator.calculate(
        chitValue: value,
        members: chit.numberOfMembers,
        winningAmount: winningAmount,
        commissionPercent: chit.commissionPercent,
        commissionMode: chit.commissionMode,
      );
      final id = await txn.insert('chit_auctions', {
        'chit_group_id': chitId,
        'month_number': monthNumber,
        'auction_date': auctionDate,
        'winner_member_id': winnerMemberId,
        'winning_amount': round2(winningAmount),
        'discount': calc.discount,
        'commission_amount': calc.commission,
        'dividend_pool': calc.dividendPool,
        'dividend_per_member': calc.dividendPerMember,
        'winner_payout': calc.winnerPayout,
        'created_at': nowStamp(),
      });
      final updated = await txn.update('chit_members', {'has_won': 1},
          where: 'id = ? AND has_won = 0', whereArgs: [winnerMemberId]);
      if (updated != 1) {
        throw const ValidationException('Winner was updated by another action. Try again.');
      }
      await _ensureContributions(txn, chit, monthNumber, calc.effectiveContribution);
      return id;
    });
  }

  Future<List<ChitContribution>> contributions(int chitId, int month) async {
    final db = await _app.database;
    final rows = await db.rawQuery('''
      SELECT c.*, m.member_name FROM chit_contributions c
      JOIN chit_members m ON m.id = c.chit_member_id
      WHERE c.chit_group_id = ? AND c.month_number = ?
      ORDER BY m.id ASC''', [chitId, month]);
    return rows.map(ChitContribution.fromMap).toList();
  }

  /// Creates pending contribution rows for every active member for [month].
  /// Amount is the calculator's effective contribution if that month's auction
  /// exists, else the base (value ÷ members).
  Future<int> ensureContributions(int chitId, int month) async {
    final db = await _app.database;
    return db.transaction((txn) async {
      final chit = await _getChit(txn, chitId);
      if (month < 1 || month > chit.durationMonths) {
        throw ValidationException('Month must be between 1 and ${chit.durationMonths}');
      }
      final value = chit.chitValue;
      if (value == null) {
        throw const ValidationException('Set the chit value before tracking contributions');
      }
      final auction = await txn.query('chit_auctions',
          where: 'chit_group_id = ? AND month_number = ?', whereArgs: [chitId, month]);
      final amount = auction.isEmpty
          ? round2(value / chit.numberOfMembers)
          : ChitCalculator.calculate(
              chitValue: value,
              members: chit.numberOfMembers,
              winningAmount: ChitAuction.fromMap(auction.first).winningAmount,
              commissionPercent: chit.commissionPercent,
              commissionMode: chit.commissionMode,
            ).effectiveContribution;
      return _ensureContributions(txn, chit, month, amount);
    });
  }

  Future<int> _ensureContributions(
      DatabaseExecutor txn, ChitGroup chit, int month, double amount) async {
    final members = await txn.query('chit_members',
        where: 'chit_group_id = ? AND membership_status = ?',
        whereArgs: [chit.id, MemberStatus.active]);
    var created = 0;
    final now = nowStamp();
    for (final m in members) {
      final id = await txn.insert(
        'chit_contributions',
        {
          'chit_group_id': chit.id,
          'chit_member_id': m['id'],
          'month_number': month,
          'amount': amount,
          'status': ContributionStatus.pending,
          'payment_date': null,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (id > 0) created++;
    }
    // Rows generated before the auction get the post-dividend amount if still unpaid.
    await txn.update('chit_contributions', {'amount': amount},
        where: 'chit_group_id = ? AND month_number = ? AND status = ?',
        whereArgs: [chit.id, month, ContributionStatus.pending]);
    return created;
  }

  Future<void> setContributionPaid(int contributionId, bool paid) async {
    final db = await _app.database;
    await db.update(
      'chit_contributions',
      {
        'status': paid ? ContributionStatus.paid : ContributionStatus.pending,
        'payment_date': paid ? todayKey() : null,
      },
      where: 'id = ?',
      whereArgs: [contributionId],
    );
  }
}
