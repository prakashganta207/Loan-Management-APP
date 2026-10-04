import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/backup_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';
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

  test('v1 database upgrades to v2 keeping old chits on from_dividend', () async {
    final path = await createV1Database(dir);
    await AppDatabase.instance.close();
    AppDatabase.factoryOverride = databaseFactoryFfi;
    AppDatabase.pathOverride = path;

    final db = await AppDatabase.instance.database;
    expect(await db.getVersion(), 2);

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
      for (final t in ['chit_groups', 'chit_auctions']) t: await columns(upgraded, t),
    };
    await AppDatabase.instance.close();

    await useFreshTestDatabase();
    final fresh = await AppDatabase.instance.database;
    for (final t in upgradedCols.keys) {
      expect(await columns(fresh, t), upgradedCols[t]);
    }
    expect(upgradedCols['chit_groups'], contains('commission_mode'));
    expect(upgradedCols['chit_auctions'], contains('winner_payout'));
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

    test('rejects a backup from a newer schema', () async {
      final snapshot = await BackupService().buildSnapshot();
      snapshot['schema_version'] = 3;
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
      expect(snapshot['schema_version'], 2);
      await BackupService().restoreSnapshot(snapshot);
      final restored = (await chits.listChits()).single.group;
      expect(restored.commissionMode, CommissionMode.fromWinner);
      expect((await chits.auctions(id)).single.winnerPayout, 85000);
    });
  });
}
