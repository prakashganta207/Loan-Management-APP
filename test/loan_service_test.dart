import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';

import 'test_db.dart';

void main() {
  late LoanService loans;
  late int loanId;

  setUp(() async {
    await useFreshTestDatabase();
    loans = LoanService();
    final borrowerId = await BorrowerService().create(name: 'Ravi', phone: '9876543210');
    loanId = await loans.createLoan(
      borrowerId: borrowerId,
      loanName: 'Shop loan',
      totalPayable: 30000,
      dailyPayment: 300,
      durationDays: 100,
      finePerDay: 10,
      startDate: '2026-01-01',
    );
  });

  tearDown(() => AppDatabase.instance.close());

  test('₹900 on a ₹300/day loan creates three ledger rows', () async {
    final ids = await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 900);
    expect(ids, hasLength(3));
    final rows = await loans.payments(loanId);
    expect(rows.map((r) => r.paymentDate), ['2026-01-01', '2026-01-02', '2026-01-03']);
    expect(rows.every((r) => r.status == PaymentStatus.paid && r.amountPaid == 300), isTrue);

    final s = await loans.summary(loanId);
    expect(s.totalPaid, 900);
    expect(s.outstanding, 29100);
    expect(s.nextDueDate, '2026-01-04');
    expect(s.coveredDays, 3);
  });

  test('partial payments fill the same day before moving on', () async {
    await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 100);
    var s = await loans.summary(loanId);
    expect(s.nextDueDate, '2026-01-01');
    expect((await loans.payments(loanId)).single.status, PaymentStatus.partial);

    await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 500);
    s = await loans.summary(loanId);
    expect(s.totalPaid, 600);
    expect(s.nextDueDate, '2026-01-03');
    final rows = await loans.payments(loanId);
    expect(rows.map((r) => r.amountPaid), [100, 200, 300]);
  });

  test('fine is stored on the first row only', () async {
    await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 600, fine: 20);
    final rows = await loans.payments(loanId);
    expect(rows.map((r) => r.fineAmount), [20, 0]);
    expect((await loans.summary(loanId)).totalFine, 20);
  });

  test('cannot pay more than the outstanding balance', () async {
    await expectLater(() => loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 30000.01),
      throwsA(isA<ValidationException>()),
    );
  });

  test('ledger is append-only at the database level', () async {
    await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 300);
    final db = await AppDatabase.instance.database;
    await expectLater(() => db.update('loan_payments', {'amount_paid': 1}), throwsA(anything));
    await expectLater(() => db.delete('loan_payments'), throwsA(anything));
    await expectLater(() => db.delete('loans'), throwsA(anything));
  });

  test('loan can only be completed once cleared, then archived', () async {
    await expectLater(() => loans.updateStatus(loanId, RecordStatus.completed),
        throwsA(isA<ValidationException>()));
    await loans.recordPayment(loanId: loanId, slotDate: '2026-01-01', amount: 30000);
    final s = await loans.summary(loanId);
    expect(s.isCleared, isTrue);
    expect(s.nextDueDate, isNull);
    await loans.updateStatus(loanId, RecordStatus.completed);
    await expectLater(() => loans.updateStatus(loanId, RecordStatus.active),
        throwsA(isA<ValidationException>()));
    await loans.updateStatus(loanId, RecordStatus.archived);
    expect((await loans.getLoan(loanId)).status, RecordStatus.archived);
  });

  test('missed day is recorded once and does not change balance', () async {
    await loans.markMissed(loanId: loanId, slotDate: '2026-01-01');
    await expectLater(() => loans.markMissed(loanId: loanId, slotDate: '2026-01-01'),
        throwsA(isA<ValidationException>()));
    final s = await loans.summary(loanId);
    expect(s.outstanding, 30000);
    expect(s.nextDueDate, '2026-01-01');
  });

  test('suggested fine counts late days', () async {
    final loan = await loans.getLoan(loanId);
    expect(LoanService.suggestedFine(loan, '2026-01-01', DateTime(2026, 1, 4)), 30);
    expect(LoanService.suggestedFine(loan, '2026-01-05', DateTime(2026, 1, 4)), 0);
  });
}
