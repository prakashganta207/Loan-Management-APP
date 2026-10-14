import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/backup_service.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/chit_loan_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';
import 'package:loan_chit_manager/widgets/common.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Writes a database exactly as the v1 app would have left it: one chit
/// (100000, 20 members, 5%) with a month-1 auction won at 80000.
Future<String> createV1Database(Directory dir) async {
  final path = p.join(dir.path, 'v1.db');
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabase.createV1Schema(db),
      ));
  const now = '2026-01-10T10:00:00.000';
  final chitId = await db.insert('chit_groups', {
    'chit_name': 'Old chit',
    'chit_value': 100000,
    'number_of_members': 20,
    'duration_months': 20,
    'commission_percent': 5,
    'start_date': '2026-01-10',
    'status': 'active',
    'created_at': now,
    'updated_at': now,
  });
  final memberIds = [
    for (var i = 1; i <= 20; i++)
      await db.insert('chit_members', {
        'chit_group_id': chitId,
        'member_name': 'Member $i',
        'membership_status': 'active',
        'has_won': i == 1 ? 1 : 0,
        'joined_at': now,
      }),
  ];
  await db.insert('chit_auctions', {
    'chit_group_id': chitId,
    'month_number': 1,
    'auction_date': '2026-01-10',
    'winner_member_id': memberIds.first,
    'winning_amount': 80000,
    'discount': 20000,
    'commission_amount': 5000,
    'dividend_pool': 15000,
    'dividend_per_member': 750,
    'created_at': now,
  });
  await db.close();
  return path;
}

Future<List<String>> columns(Database db, String table) async =>
    (await db.rawQuery('PRAGMA table_info($table)')).map((r) => '${r['name']}').toList();

void main() {
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('lcm_migration_');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await dir.delete(recursive: true);
  });

  test('v1 database upgrades to the current schema keeping old chits on from_dividend', () async {
    final path = await createV1Database(dir);
    await AppDatabase.instance.close();
    AppDatabase.factoryOverride = databaseFactoryFfi;
    AppDatabase.pathOverride = path;

    final db = await AppDatabase.instance.database;
    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final chits = ChitService();
    final old = (await chits.listChits()).single.group;
    expect(old.commissionMode, CommissionMode.fromDividend);
    final auction = (await chits.auctions(old.id!)).single;
    expect(auction.winnerPayout, 80000);
    final raw = await db.query('chit_auctions', columns: ['winner_payout']);
    expect(raw.single['winner_payout'], 80000); // backfilled in the DB, not just the model

    // Month 2 of the old chit still uses the old maths.
    final members = await chits.members(old.id!);
    await chits.recordAuction(
        chitId: old.id!, monthNumber: 2, winnerMemberId: members[1].id!,
        winningAmount: 80000, auctionDate: '2026-02-10');
    final m2 = (await chits.auctions(old.id!)).last;
    expect(m2.dividendPerMember, 750);
    expect(m2.winnerPayout, 80000);
    expect((await chits.contributions(old.id!, 2)).first.amount, 4250);

    // The CHECK constraint came with the migration.
    await expectLater(
        () => db.update('chit_groups', {'commission_mode': 'bogus'}), throwsA(anything));
  });

  test('fresh v2 database has the same chit columns as an upgraded one', () async {
    final upgradedPath = await createV1Database(dir);
    AppDatabase.factoryOverride = databaseFactoryFfi;
    AppDatabase.pathOverride = upgradedPath;
    final upgraded = await AppDatabase.instance.database;
    final upgradedCols = {
      for (final t in ['chit_groups', 'chit_auctions', 'loans']) t: await columns(upgraded, t),
    };
    await AppDatabase.instance.close();

    await useFreshTestDatabase();
    final fresh = await AppDatabase.instance.database;
    for (final t in upgradedCols.keys) {
      expect(await columns(fresh, t), upgradedCols[t]);
    }
    expect(upgradedCols['chit_groups'], contains('commission_mode'));
    expect(upgradedCols['chit_auctions'], contains('winner_payout'));
    expect(upgradedCols['chit_auctions'], containsAll(['loan_setup_status', 'loan_id']));
    expect(upgradedCols['loans'],
        containsAll(['repayment_type', 'late_interest_percent', 'grace_days',
            'source_chit_auction_id']));
  });

  test('v2 database with auctions and daily loans opens on v3: loans daily, auctions pending',
      () async {
    // Build the database exactly as app v1.0.0 (schema v2) would have left it.
    final path = p.join(dir.path, 'v2.db');
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await AppDatabase.createV1Schema(db);
            await AppDatabase.migrate(db, 1, 2);
          },
        ));
    const now = '2026-01-10T10:00:00.000';
    final b = await old.insert('borrowers', {
      'name': 'Ravi', 'is_archived': 0, 'created_at': now, 'updated_at': now});
    final loanId = await old.insert('loans', {
      'borrower_id': b, 'loan_name': 'Shop loan', 'total_payable': 30000, 'daily_payment': 300,
      'duration_days': 100, 'fine_per_day': 10, 'start_date': '2026-01-01', 'status': 'active',
      'created_at': now, 'updated_at': now});
    await old.insert('loan_payments', {
      'loan_id': loanId, 'payment_date': '2026-01-01', 'scheduled_amount': 300,
      'amount_paid': 300, 'fine_amount': 0, 'status': 'paid', 'created_at': now});
    final chitId = await old.insert('chit_groups', {
      'chit_name': 'Old chit', 'chit_value': 100000, 'number_of_members': 2,
      'duration_months': 2, 'commission_percent': 5, 'commission_mode': 'from_winner',
      'start_date': '2026-01-10', 'status': 'active', 'created_at': now, 'updated_at': now});
    final m = await old.insert('chit_members', {
      'chit_group_id': chitId, 'member_name': 'Anu', 'membership_status': 'active',
      'has_won': 1, 'joined_at': now});
    await old.insert('chit_auctions', {
      'chit_group_id': chitId, 'month_number': 1, 'auction_date': '2026-01-10',
      'winner_member_id': m, 'winning_amount': 80000, 'discount': 20000,
      'commission_amount': 5000, 'dividend_pool': 20000, 'dividend_per_member': 10000,
      'winner_payout': 75000, 'created_at': now});
    expect(await old.getVersion(), 2);
    await old.close();

    AppDatabase.factoryOverride = databaseFactoryFfi;
    AppDatabase.pathOverride = path;
    final db = await AppDatabase.instance.database;
    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final loan = await LoanService().getLoan(loanId);
    expect(loan.repaymentType, RepaymentType.daily);
    expect([loan.lateInterestPercent, loan.graceDays, loan.sourceChitAuctionId], [0, 0, null]);
    final s = await LoanService().summary(loanId);
    expect([s.totalPaid, s.outstanding, s.nextDueDate], [300, 29700, '2026-01-02']);

    final waiting = await ChitLoanService().items();
    expect(waiting.single.memberName, 'Anu');
    expect(waiting.single.status, LoanSetupStatus.pending);
    expect(waiting.single.prize, 75000);

    // The ledger guards still hold after the upgrade.
    await expectLater(() => db.update('loan_payments', {'amount_paid': 1}), throwsA(anything));
  });

  group('backup restore', () {
    setUp(useFreshTestDatabase);

    test('accepts a v1 backup and fills the new columns', () async {
      final chits = ChitService();
      final id = await chits.createChit(
          name: 'X', chitValue: 100000, members: 2, durationMonths: 2,
          commissionMode: CommissionMode.fromWinner, startDate: '2026-01-01');
      final m = await chits.addMember(chitId: id, name: 'A');
      await chits.addMember(chitId: id, name: 'B');
      await chits.recordAuction(
          chitId: id, monthNumber: 1, winnerMemberId: m, winningAmount: 90000,
          auctionDate: '2026-01-01');

      // Turn the current snapshot into what a v1 app would have exported.
      final snapshot = await BackupService().buildSnapshot();
      snapshot['schema_version'] = 1;
      final tables = snapshot['tables'] as Map<String, dynamic>;
      for (final entry in {'chit_groups': 'commission_mode', 'chit_auctions': 'winner_payout'}
          .entries) {
        tables[entry.key] = [
          for (final r in tables[entry.key] as List)
            Map<String, Object?>.from(r as Map)..remove(entry.value),
        ];
      }

      await BackupService().restoreSnapshot(snapshot);
      final restored = (await chits.listChits()).single.group;
      expect(restored.commissionMode, CommissionMode.fromDividend);
      final db = await AppDatabase.instance.database;
      expect((await db.query('chit_auctions')).single['winner_payout'], 90000);
    });

    test('AUDIT A5: a damaged backup gives a plain message and changes nothing', () async {
      await ChitService().createChit(
          name: 'Keep me', members: 2, durationMonths: 2, startDate: '2026-01-01');
      for (final damage in <void Function(Map<String, dynamic>)>[
        (t) => t['loans'] = ['not a row'],
        (t) => t['borrowers'] = [
              {'id': 1, 'nme': 'typo column'}
            ],
        (t) => t['chit_groups'] = 'not a list',
      ]) {
        final snapshot = await BackupService().buildSnapshot();
        damage(snapshot['tables'] as Map<String, dynamic>);
        await expectLater(
          () => BackupService().restoreSnapshot(snapshot),
          throwsA(isA<ValidationException>().having((e) => e.message, 'message',
              'This backup file is damaged or not from this app. Nothing was changed.')),
        );
      }
      expect((await ChitService().listChits()).single.group.chitName, 'Keep me');
    });

    test('AUDIT A5: unexpected errors are shown in plain words', () {
      final text = errorText(StateError('Bad state: cursor window full'));
      expect(text, startsWith('Something went wrong. Please try again.'));
      expect(errorText(const ValidationException('Name is required')), 'Name is required');
    });

    test('round-trips a monthly loan created for a chit winner', () async {
      final chits = ChitService();
      final chitId = await chits.createChit(name: 'Z', chitValue: 100000, members: 2,
          durationMonths: 2, commissionPercent: 5, startDate: '2026-01-10');
      final m = await chits.addMember(chitId: chitId, name: 'Anu', phone: '9000000001');
      await chits.recordAuction(chitId: chitId, monthNumber: 1, winnerMemberId: m,
          winningAmount: 80000, auctionDate: '2026-01-10');
      final auctionId = (await chits.auctions(chitId)).single.id!;
      final loanId = await ChitLoanService().setUpLoan(
          auctionId: auctionId, loanName: 'Prize loan', repaymentType: RepaymentType.monthly,
          totalPayable: 75000, installment: 25000, installmentCount: 3,
          lateInterestPercent: 2, graceDays: 5, startDate: '2026-02-10');
      await LoanService().recordPayment(
          loanId: loanId, slotDate: '2026-02-10', amount: 25000, fine: 50);

      final snapshot = await BackupService().buildSnapshot();
      await BackupService().restoreSnapshot(snapshot);

      final loan = await LoanService().getLoan(loanId);
      expect(loan.isMonthly, isTrue);
      expect([loan.installmentAmount, loan.installmentCount, loan.lateInterestPercent,
          loan.graceDays, loan.sourceChitAuctionId], [25000, 3, 2, 5, auctionId]);
      final s = await LoanService().summary(loanId);
      expect([s.totalPaid, s.totalFine, s.nextDueDate], [25000, 50, '2026-03-10']);
      final a = (await chits.auctions(chitId)).single;
      expect([a.loanSetupStatus, a.loanId], [LoanSetupStatus.created, loanId]);
      expect(await ChitLoanService().items(), isEmpty);
    });

    test('a v2 backup restores with daily loans and pending auctions', () async {
      final chits = ChitService();
      final chitId = await chits.createChit(name: 'Z', chitValue: 100000, members: 2,
          durationMonths: 2, startDate: '2026-01-10');
      final m = await chits.addMember(chitId: chitId, name: 'Anu');
      await chits.recordAuction(chitId: chitId, monthNumber: 1, winnerMemberId: m,
          winningAmount: 80000, auctionDate: '2026-01-10');
      final b = await BorrowerService().create(name: 'Ravi');
      await LoanService().createLoan(borrowerId: b, loanName: 'L', totalPayable: 3000,
          dailyPayment: 300, durationDays: 10, startDate: '2026-01-01');

      final snapshot = await BackupService().buildSnapshot();
      snapshot['schema_version'] = 2;
      final tables = snapshot['tables'] as Map<String, dynamic>;
      for (final entry in {
        'loans': ['repayment_type', 'late_interest_percent', 'grace_days',
            'source_chit_auction_id'],
        'chit_auctions': ['loan_setup_status', 'loan_id'],
      }.entries) {
        tables[entry.key] = [
          for (final r in tables[entry.key] as List)
            Map<String, Object?>.from(r as Map)..removeWhere((k, _) => entry.value.contains(k)),
        ];
      }
      await BackupService().restoreSnapshot(snapshot);
      expect((await LoanService().listLoans()).single.repaymentType, RepaymentType.daily);
      expect((await ChitLoanService().items()).single.status, LoanSetupStatus.pending);
    });

    test('rejects a backup from a newer schema', () async {
      final snapshot = await BackupService().buildSnapshot();
      snapshot['schema_version'] = AppDatabase.schemaVersion + 1;
      await expectLater(
          () => BackupService().restoreSnapshot(snapshot), throwsA(isA<ValidationException>()));
    });

    test('v2 backup round-trips commission mode and winner payout', () async {
      final chits = ChitService();
      final id = await chits.createChit(
          name: 'Y', chitValue: 100000, members: 2, durationMonths: 2, commissionPercent: 5,
          startDate: '2026-01-01');
      final m = await chits.addMember(chitId: id, name: 'A');
      await chits.recordAuction(
          chitId: id, monthNumber: 1, winnerMemberId: m, winningAmount: 90000,
          auctionDate: '2026-01-01');
      final snapshot = await BackupService().buildSnapshot();
      expect(snapshot['schema_version'], AppDatabase.schemaVersion);
      await BackupService().restoreSnapshot(snapshot);
      final restored = (await chits.listChits()).single.group;
      expect(restored.commissionMode, CommissionMode.fromWinner);
      expect((await chits.auctions(id)).single.winnerPayout, 85000);
    });
  });
}
