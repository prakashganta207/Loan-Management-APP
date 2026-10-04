import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
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
