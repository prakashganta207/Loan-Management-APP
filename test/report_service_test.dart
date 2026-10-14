import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/format.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';
import 'package:loan_chit_manager/services/report_service.dart';

import 'test_db.dart';

void main() {
  setUp(useFreshTestDatabase);
  tearDown(() => AppDatabase.instance.close());

  final today = dateOnly(DateTime.now());

  Future<int> loanFrom(DateTime start, {String name = 'Ravi'}) async {
    final b = await BorrowerService().create(name: name);
    return LoanService().createLoan(borrowerId: b, loanName: 'Shop loan', totalPayable: 3000,
        dailyPayment: 300, durationDays: 10, startDate: dateKey(start));
  }

  /// Writes ledger rows as if they had been recorded on [recordedOn].
  Future<void> paidEarlier(int loanId, List<DateTime> slots, DateTime recordedOn) async {
    final db = await AppDatabase.instance.database;
    for (final s in slots) {
      await db.insert('loan_payments', {
        'loan_id': loanId,
        'payment_date': dateKey(s),
        'scheduled_amount': 300,
        'amount_paid': 300,
        'fine_amount': 0,
        'status': 'paid',
        'created_at': recordedOn.add(const Duration(hours: 10)).toIso8601String(),
      });
    }
  }

  test('AUDIT A2: a borrower who paid ahead is not due or pending today', () async {
    final yesterday = addDays(today, -1);
    final ahead = await loanFrom(yesterday);
    // Yesterday they paid ₹900: yesterday, today and tomorrow.
    await paidEarlier(ahead, [yesterday, today, addDays(today, 1)], yesterday);
    final behind = await loanFrom(addDays(today, -3), name: 'Sita'); // nothing paid

    final d = await ReportService().dashboard();
    expect(d.items.map((i) => i.summary.loan.id), [behind]);
    expect(d.expected, 300);
    expect(d.pendingBorrowers, 1);
  });

  test('a borrower who pays ahead today still shows as collected today', () async {
    final id = await loanFrom(today);
    await LoanService().recordPayment(loanId: id, slotDate: todayKey(), amount: 900);

    final d = await ReportService().dashboard();
    expect(d.items, hasLength(1));
    expect(d.items.single.isCollected, isTrue);
    expect(d.collected, 900);
    expect(d.pendingBorrowers, 0);
  });
}
