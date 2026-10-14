import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/chit_loan_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';
import 'package:loan_chit_manager/services/report_service.dart';

import 'test_db.dart';

void main() {
  late ChitService chits;
  late ChitLoanService setup;
  late int chitId;
  late List<int> members;

  setUp(() async {
    await useFreshTestDatabase();
    chits = ChitService();
    setup = ChitLoanService();
    chitId = await chits.createChit(
        name: 'Diwali chit', chitValue: 100000, members: 4, durationMonths: 4,
        commissionPercent: 5, startDate: '2026-01-10');
    members = [
      await chits.addMember(chitId: chitId, name: 'Anu', phone: '9000000001'),
      await chits.addMember(chitId: chitId, name: 'Bala'),
      await chits.addMember(chitId: chitId, name: 'Chitra'),
      await chits.addMember(chitId: chitId, name: 'Devi'),
    ];
  });

  tearDown(() => AppDatabase.instance.close());

  Future<int> auction(int month, int member, {double winning = 80000}) async {
    await chits.recordAuction(chitId: chitId, monthNumber: month, winnerMemberId: member,
        winningAmount: winning, auctionDate: '2026-0$month-10');
    return (await chits.auctions(chitId)).firstWhere((a) => a.monthNumber == month).id!;
  }

  Future<int> setUpMonthly(int auctionId, {int? borrowerId}) => setup.setUpLoan(
        auctionId: auctionId,
        borrowerId: borrowerId,
        loanName: 'Diwali chit prize',
        repaymentType: RepaymentType.monthly,
        totalPayable: 75000,
        installment: 25000,
        installmentCount: 3,
        lateInterestPercent: 2,
        graceDays: 5,
        startDate: '2026-02-10',
      );

  test('saving an auction creates exactly one pending item', () async {
    final id = await auction(1, members[0]);
    final items = await setup.items();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.auctionId, id);
    expect(item.memberName, 'Anu');
    expect(item.chitName, 'Diwali chit');
    expect(item.monthNumber, 1);
    expect(item.prize, 75000); // winner payout: 80,000 − 5% commission
    expect(item.status, LoanSetupStatus.pending);
    expect(await setup.count(), 1);
    expect((await ReportService().dashboard()).chitLoansWaiting, 1);
  });

  test('setup creates one loan, links it, and a second setup is rejected', () async {
    final id = await auction(1, members[0]);
    final loanId = await setUpMonthly(id);

    final loan = await LoanService().getLoan(loanId);
    expect(loan.isMonthly, isTrue);
    expect(loan.sourceChitAuctionId, id);
    expect(loan.lateInterestPercent, 2);
    expect(loan.graceDays, 5);
    expect(loan.borrowerName, 'Anu'); // created from the chit member
    final a = (await chits.auctions(chitId)).single;
    expect(a.loanSetupStatus, LoanSetupStatus.created);
    expect(a.loanId, loanId);
    expect(await setup.items(), isEmpty);

    await expectLater(() => setUpMonthly(id), throwsA(isA<ValidationException>()));
    final db = await AppDatabase.instance.database;
    expect(await db.query('loans'), hasLength(1));
  });

  test('two setups started together still create only one loan', () async {
    final id = await auction(1, members[0]);
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        setUpMonthly(id).then((_) => 'ok').catchError((Object e) => 'rejected'),
    ]);
    expect(results.where((r) => r == 'ok'), hasLength(1));
    final db = await AppDatabase.instance.database;
    expect(await db.query('loans'), hasLength(1));
    expect(await db.query('borrowers'), hasLength(1));
  });

  test('a failed setup changes nothing', () async {
    final id = await auction(1, members[0]);
    await expectLater(
        () => setup.setUpLoan(auctionId: id, loanName: 'x', repaymentType: RepaymentType.monthly,
            totalPayable: 1000, installment: 5000, installmentCount: 1, startDate: '2026-02-10'),
        throwsA(isA<ValidationException>())); // instalment > total
    final db = await AppDatabase.instance.database;
    expect(await db.query('borrowers'), isEmpty); // the new borrower was rolled back
    expect((await setup.items()).single.status, LoanSetupStatus.pending);
  });

  test('borrower matching: same phone, or same name when there is no phone', () async {
    final byPhone = await BorrowerService().create(name: 'Anuradha', phone: '9000000001');
    final byName = await BorrowerService().create(name: 'bala');
    final chitra = await BorrowerService().create(name: 'Chitra', phone: '9111111111');
    await auction(1, members[0]);
    await auction(2, members[1]);
    await auction(3, members[2]);
    await auction(4, members[3]);
    final items = {for (final i in await setup.items()) i.memberName: i};
    expect(await setup.matchingBorrower(items['Anu']!), byPhone); // phone wins over name
    expect(await setup.matchingBorrower(items['Bala']!), byName); // no phone → name, any case
    expect(await setup.matchingBorrower(items['Chitra']!), chitra);
    expect(await setup.matchingBorrower(items['Devi']!), isNull); // nobody matches

    final loanId = await setUpMonthly(items['Bala']!.auctionId, borrowerId: byName);
    expect((await LoanService().getLoan(loanId)).borrowerId, byName);
  });

  test('dismiss hides the item, restore brings it back', () async {
    final id = await auction(1, members[0]);
    await setup.dismiss(id);
    expect(await setup.items(), isEmpty);
    expect((await setup.items(status: LoanSetupStatus.dismissed)).single.auctionId, id);
    await expectLater(() => setUpMonthly(id), throwsA(isA<ValidationException>()));
    await expectLater(() => setup.dismiss(id), throwsA(isA<ValidationException>()));

    await setup.restore(id);
    expect((await setup.items()).single.auctionId, id);
    expect(await setup.items(status: LoanSetupStatus.dismissed), isEmpty);
    await setUpMonthly(id);
    await expectLater(() => setup.restore(id), throwsA(isA<ValidationException>()));
  });

  test('remaining chit instalments for the winner', () async {
    final id = await auction(2, members[0]);
    final item = (await setup.items()).firstWhere((i) => i.auctionId == id);
    expect(await setup.remainingChitInstallments(item), 3); // months 2, 3, 4
    final row = (await chits.contributions(chitId, 2)).firstWhere((c) => c.memberName == 'Anu');
    await chits.setContributionPaid(row.id!, true);
    expect(await setup.remainingChitInstallments(item), 2);
  });

  test('loan source lookup links the loan back to the chit', () async {
    final id = await auction(1, members[0]);
    final loan = await LoanService().getLoan(await setUpMonthly(id));
    final source = await setup.sourceOf(loan);
    expect(source!.chitId, chitId);
    expect(source.monthNumber, 1);
    expect(source.loanId, loan.id);
  });

  test('no repeat winners and one auction per month still hold', () async {
    await auction(1, members[0]);
    await expectLater(() => auction(2, members[0]), throwsA(isA<ValidationException>()));
    await expectLater(() => auction(1, members[1]), throwsA(isA<ValidationException>()));
    expect(await setup.items(), hasLength(1));
  });
}
