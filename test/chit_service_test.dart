import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/backup_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';

import 'test_db.dart';

void main() {
  late ChitService chits;
  late int chitId;
  late List<int> memberIds;

  setUp(() async {
    await useFreshTestDatabase();
    chits = ChitService();
    chitId = await chits.createChit(
      name: 'Diwali chit',
      chitValue: 100000,
      members: 4,
      durationMonths: 4,
      commissionPercent: 5,
      commissionMode: CommissionMode.fromDividend,
      startDate: '2026-01-10',
    );
    memberIds = [
      for (final n in ['Anu', 'Bala', 'Chitra', 'Devi'])
        await chits.addMember(chitId: chitId, name: n),
    ];
  });

  tearDown(() => AppDatabase.instance.close());

  test('member count cannot exceed the chit size', () async {
    await expectLater(() => chits.addMember(chitId: chitId, name: 'Extra'),
        throwsA(isA<ValidationException>()));
  });

  test('auction stores split, marks winner and creates contributions', () async {
    await chits.recordAuction(
        chitId: chitId,
        monthNumber: 1,
        winnerMemberId: memberIds[0],
        winningAmount: 80000,
        auctionDate: '2026-01-10');
    final a = (await chits.auctions(chitId)).single;
    expect(a.discount, 20000);
    expect(a.commissionAmount, 5000);
    expect(a.dividendPerMember, 3750);
    expect((await chits.members(chitId)).first.hasWon, isTrue);

    final contribs = await chits.contributions(chitId, 1);
    expect(contribs, hasLength(4));
    expect(contribs.every((c) => c.amount == 21250), isTrue); // 25000 − 3750
    expect(a.winnerPayout, 80000);
  });

  group('from_winner chit', () {
    late int winnerChit;
    late List<int> ids;

    setUp(() async {
      winnerChit = await chits.createChit(
        name: 'Pongal chit',
        chitValue: 100000,
        members: 4,
        durationMonths: 4,
        commissionPercent: 5,
        startDate: '2026-01-10',
      );
      ids = [
        for (final n in ['Esha', 'Farid', 'Gita', 'Hari'])
          await chits.addMember(chitId: winnerChit, name: n),
      ];
    });

    test('is the default for new chits', () async {
      expect((await chits.getChit(winnerChit)).commissionMode, CommissionMode.fromWinner);
    });

    test('auction stores winner payout and contributions of winning ÷ members', () async {
      expect(await chits.ensureContributions(winnerChit, 1), 4);
      expect((await chits.contributions(winnerChit, 1)).every((c) => c.amount == 25000), isTrue);

      await chits.recordAuction(
          chitId: winnerChit, monthNumber: 1, winnerMemberId: ids[0],
          winningAmount: 80000, auctionDate: '2026-01-10');
      final a = (await chits.auctions(winnerChit)).single;
      expect(a.discount, 20000);
      expect(a.commissionAmount, 5000);
      expect(a.dividendPool, 20000);
      expect(a.dividendPerMember, 5000);
      expect(a.winnerPayout, 75000);

      // Pending rows created before the auction are re-priced: 80000 ÷ 4.
      expect((await chits.contributions(winnerChit, 1)).every((c) => c.amount == 20000), isTrue);
      await chits.ensureContributions(winnerChit, 1);
      expect((await chits.contributions(winnerChit, 1)).every((c) => c.amount == 20000), isTrue);
    });

    test('a member cannot win twice and a month is auctioned once', () async {
      await chits.recordAuction(
          chitId: winnerChit, monthNumber: 1, winnerMemberId: ids[0],
          winningAmount: 80000, auctionDate: '2026-01-10');
      await expectLater(() => chits.recordAuction(
            chitId: winnerChit, monthNumber: 2, winnerMemberId: ids[0],
            winningAmount: 85000, auctionDate: '2026-02-10'),
        throwsA(isA<ValidationException>()));
      await expectLater(() => chits.recordAuction(
            chitId: winnerChit, monthNumber: 1, winnerMemberId: ids[1],
            winningAmount: 85000, auctionDate: '2026-01-10'),
        throwsA(isA<ValidationException>()));
    });

    test('commission mode can change before the first auction, then locks', () async {
      Future<void> setMode(String mode) => chits.updateChit(
          id: winnerChit, name: 'Pongal chit', chitValue: 100000, members: 4,
          durationMonths: 4, commissionPercent: 5, commissionMode: mode,
          startDate: '2026-01-10');

      await setMode(CommissionMode.fromDividend);
      expect((await chits.getChit(winnerChit)).commissionMode, CommissionMode.fromDividend);
      await setMode(CommissionMode.fromWinner);

      await chits.recordAuction(
          chitId: winnerChit, monthNumber: 1, winnerMemberId: ids[0],
          winningAmount: 80000, auctionDate: '2026-01-10');
      await expectLater(() => setMode(CommissionMode.fromDividend),
          throwsA(isA<ValidationException>()));
      expect((await chits.getChit(winnerChit)).commissionMode, CommissionMode.fromWinner);
    });

    test('rejects an unknown commission mode', () async {
      await expectLater(() => chits.createChit(
            name: 'Bad', members: 2, durationMonths: 2, startDate: '2026-01-01',
            commissionMode: 'from_nobody'),
        throwsA(isA<ValidationException>()));
    });
  });

  test('a member cannot win twice', () async {
    await chits.recordAuction(
        chitId: chitId, monthNumber: 1, winnerMemberId: memberIds[0],
        winningAmount: 80000, auctionDate: '2026-01-10');
    await expectLater(() => chits.recordAuction(
          chitId: chitId, monthNumber: 2, winnerMemberId: memberIds[0],
          winningAmount: 85000, auctionDate: '2026-02-10'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('a month can only be auctioned once', () async {
    await chits.recordAuction(
        chitId: chitId, monthNumber: 1, winnerMemberId: memberIds[0],
        winningAmount: 80000, auctionDate: '2026-01-10');
    await expectLater(() => chits.recordAuction(
          chitId: chitId, monthNumber: 1, winnerMemberId: memberIds[1],
          winningAmount: 85000, auctionDate: '2026-01-10'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('backup snapshot round-trips', () async {
    await chits.recordAuction(
        chitId: chitId, monthNumber: 1, winnerMemberId: memberIds[0],
        winningAmount: 80000, auctionDate: '2026-01-10');
    final backup = BackupService();
    final snapshot = await backup.buildSnapshot();
    await chits.addMember(chitId: await chits.createChit(
        name: 'Temp', members: 2, durationMonths: 2, startDate: '2026-01-01'), name: 'X');
    await backup.restoreSnapshot(snapshot);
    final all = await chits.listChits();
    expect(all, hasLength(1));
    expect(all.single.auctionsDone, 1);
  });
}
