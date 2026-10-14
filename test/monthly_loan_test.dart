import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/core/format.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';
import 'package:loan_chit_manager/services/report_service.dart';

import 'test_db.dart';

void main() {
  late LoanService loans;
  late int borrowerId;

  setUp(() async {
    await useFreshTestDatabase();
    loans = LoanService();
    borrowerId = await BorrowerService().create(name: 'Kumar', phone: '9000000001');
  });

  tearDown(() => AppDatabase.instance.close());

  Future<int> monthly({
    double total = 60000,
    double instalment = 5000,
    int months = 12,
    double interest = 2,
    int grace = 0,
    String firstDue = '2026-01-31',
  }) =>
      loans.createLoan(
        borrowerId: borrowerId,
        loanName: 'Chit prize loan',
        totalPayable: total,
        dailyPayment: instalment,
        durationDays: months,
        startDate: firstDue,
        repaymentType: RepaymentType.monthly,
        lateInterestPercent: interest,
        graceDays: grace,
      );

  group('monthly schedule', () {
    test('31 Jan → 28 Feb (or 29 in a leap year) → 31 Mar → 30 Apr', () async {
      final loan = await loans.getLoan(await monthly());
      expect(loan.isMonthly, isTrue);
      expect(loan.installmentAmount, 5000);
      expect(loan.installmentCount, 12);
      expect([for (var i = 0; i < 4; i++) LoanService.slotKey(loan, i)],
          ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);

      final leap = await loans.getLoan(await monthly(firstDue: '2028-01-31'));
      expect(LoanService.slotKey(leap, 1), '2028-02-29');
      expect(LoanService.slotKey(leap, 2), '2028-03-31'); // from the start date, not chained
    });

    test('addMonthsClamped never drifts', () {
      final start = DateTime(2026, 1, 31);
      expect([for (var i = 0; i < 13; i++) dateKey(addMonthsClamped(start, i))].last,
          '2027-01-31');
      expect(dateKey(addMonthsClamped(DateTime(2026, 12, 15), 1)), '2027-01-15');
    });

    test('only instalment due dates can be paid or marked missed', () async {
      final id = await monthly();
      await expectLater(
          () => loans.recordPayment(loanId: id, slotDate: '2026-02-15', amount: 5000),
          throwsA(isA<ValidationException>()));
      await expectLater(() => loans.markMissed(loanId: id, slotDate: '2026-02-15'),
          throwsA(isA<ValidationException>()));
      await loans.markMissed(loanId: id, slotDate: '2026-02-28');
    });
  });

  group('monthly payments', () {
    test('paying 3 instalments at once creates 3 ledger rows', () async {
      final id = await monthly();
      final ids = await loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 15000);
      expect(ids, hasLength(3));
      final rows = await loans.payments(id);
      expect(rows.map((r) => r.paymentDate), ['2026-01-31', '2026-02-28', '2026-03-31']);
      expect(rows.every((r) => r.status == PaymentStatus.paid && r.amountPaid == 5000), isTrue);
      final s = await loans.summary(id);
      expect(s.outstanding, 45000);
      expect(s.nextDueDate, '2026-04-30');
      expect(s.coveredDays, 3); // instalments fully paid
      expect(s.daysRemaining, 9);
    });

    test('a partial payment tops up the same instalment first', () async {
      final id = await monthly();
      await loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 2000);
      var s = await loans.summary(id);
      expect(s.nextDueDate, '2026-01-31');
      expect(s.nextDueUnpaid, 3000);
      await loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 4000);
      s = await loans.summary(id);
      expect((await loans.payments(id)).map((r) => r.amountPaid), [2000, 3000, 1000]);
      expect(s.nextDueDate, '2026-02-28');
      expect(s.nextDueUnpaid, 4000);
    });

    test('overpaying is rejected', () async {
      final id = await monthly();
      await expectLater(
          () => loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 60000.01),
          throwsA(isA<ValidationException>()));
    });

    test('ledger stays append-only and status rules apply', () async {
      final id = await monthly(total: 10000, instalment: 5000, months: 2);
      await loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 10000);
      final db = await AppDatabase.instance.database;
      await expectLater(() => db.update('loan_payments', {'amount_paid': 1}), throwsA(anything));
      await loans.updateStatus(id, RecordStatus.completed);
      await loans.updateStatus(id, RecordStatus.archived);
    });
  });

  group('late interest (monthly)', () {
    test('5000 at 2% a month: 45 days late = 150.00, 15 grace days = 100.00, on time = 0',
        () async {
      final noGrace = await loans.getLoan(await monthly());
      final grace = await loans.getLoan(await monthly(grace: 15));
      expect(LoanService.lateInterest(noGrace, 5000, 45), 150.00);
      expect(LoanService.lateInterest(grace, 5000, 45), 100.00);
      expect(LoanService.lateInterest(noGrace, 5000, 0), 0);
      // The payment-entry suggestion uses the same formula from the due date.
      expect(LoanService.suggestedFine(noGrace, '2026-01-31', DateTime(2026, 3, 17)), 150.00);
      expect(LoanService.suggestedFine(grace, '2026-01-31', DateTime(2026, 3, 17)), 100.00);
      expect(LoanService.suggestedFine(noGrace, '2026-01-31', DateTime(2026, 1, 31)), 0);
      expect(LoanService.suggestedFine(noGrace, '2026-01-31', DateTime(2026, 1, 20)), 0);
    });

    test('interest is only on the unpaid part of the instalment, never the whole loan', () async {
      final id = await monthly();
      await loans.recordPayment(loanId: id, slotDate: '2026-01-31', amount: 2000);
      final loan = await loans.getLoan(id);
      final s = LoanService.computeSummary(loan, await loans.payments(id), DateTime(2026, 2, 15));
      // Jan instalment: 3000 unpaid, 15 days late → 3000 × 2% × 15/30 = 30. Feb not due yet.
      expect(s.overdueInstallments, 1);
      expect(s.accruedLateCharge, 30.00);
      expect(s.overdueDays, 15);
      expect(LoanService.suggestedFine(loan, '2026-01-31', DateTime(2026, 2, 15),
          unpaid: s.nextDueUnpaid), 30.00);
    });

    test('late interest is stored in fine_amount on the first row only', () async {
      final id = await monthly();
      await loans.recordPayment(
          loanId: id, slotDate: '2026-01-31', amount: 10000, fine: 150, note: 'late');
      final rows = await loans.payments(id);
      expect(rows.map((r) => r.fineAmount), [150, 0]);
      expect((await loans.summary(id)).totalFine, 150);
    });

    test('accrued interest adds up over every overdue instalment', () async {
      final id = await monthly();
      final loan = await loans.getLoan(id);
      final s = LoanService.computeSummary(loan, const [], DateTime(2026, 3, 31));
      // Jan 31 → 59 days late: 5000 × 2% × 59/30 = 196.67; Feb 28 → 31 days: 103.33.
      expect(s.overdueInstallments, 2);
      expect(s.accruedLateCharge, 300.00);
      expect(s.nextDueDate, '2026-01-31');
    });
  });

  group('daily loans after the migration', () {
    test('behave exactly as before', () async {
      final id = await loans.createLoan(
          borrowerId: borrowerId, loanName: 'Shop loan', totalPayable: 30000,
          dailyPayment: 300, durationDays: 100, finePerDay: 10, startDate: '2026-01-01');
      final loan = await loans.getLoan(id);
      expect(loan.repaymentType, RepaymentType.daily);
      expect(loan.isMonthly, isFalse);
      expect(await loans.recordPayment(loanId: id, slotDate: '2026-01-01', amount: 900),
          hasLength(3));
      final s = await loans.summary(id);
      expect([s.totalPaid, s.outstanding, s.nextDueDate, s.coveredDays],
          [900, 29100, '2026-01-04', 3]);
      expect(LoanService.suggestedFine(loan, '2026-01-01', DateTime(2026, 1, 4)), 30);
      expect(s.accruedLateCharge, 0);
    });
  });

  group('dashboard with monthly loans', () {
    Future<int> monthlyFrom(DateTime firstDue) => monthly(firstDue: dateKey(firstDue));

    test('not listed before the instalment is due', () async {
      await monthlyFrom(addDays(dateOnly(DateTime.now()), 5));
      expect((await ReportService().dashboard()).items, isEmpty);
    });

    test('listed when due today, expected = unpaid part; quick pay records the instalment',
        () async {
      final today = dateOnly(DateTime.now());
      final id = await monthlyFrom(today);
      await loans.recordPayment(loanId: id, slotDate: todayKey(), amount: 1000);
      var d = await ReportService().dashboard();
      expect(d.items.single.due, 5000); // 1000 today + 4000 still unpaid
      expect(d.items.single.stillDue, 4000);
      expect(d.pendingBorrowers, 1);

      await loans.recordPayment(
          loanId: id, slotDate: d.items.single.summary.nextDueDate!, amount: 4000);
      d = await ReportService().dashboard();
      expect(d.items.single.isCollected, isTrue);
      expect(d.pendingBorrowers, 0);
      expect(d.collected, 5000);
    });

    test('an overdue instalment shows with its unpaid amount', () async {
      final firstDue = addMonthsClamped(dateOnly(DateTime.now()), -2);
      await monthlyFrom(firstDue);
      final d = await ReportService().dashboard();
      expect(d.items.single.due, 5000);
      expect(d.items.single.summary.overdueInstallments, greaterThanOrEqualTo(2));
    });
  });
}
