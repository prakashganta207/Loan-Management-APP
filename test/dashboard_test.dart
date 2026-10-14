import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/format.dart';
import 'package:loan_chit_manager/core/theme.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/screens/dashboard/dashboard_screen.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';

import 'test_db.dart';

/// Lets real database I/O (sqflite ffi) finish between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('AUDIT A1: double tap on "Mark paid" records one payment', (tester) async {
    await tester.runAsync(() async {
      await useFreshTestDatabase();
      final b = await BorrowerService().create(name: 'Ravi');
      await LoanService().createLoan(borrowerId: b, loanName: 'Shop loan', totalPayable: 3000,
          dailyPayment: 300, durationDays: 10, startDate: todayKey());
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const DashboardScreen()));
    await settle(tester);

    final markPaid = find.byTooltip('Mark paid');
    expect(markPaid, findsOneWidget);
    await tester.tap(markPaid);
    await tester.tap(markPaid);
    await settle(tester);

    final rows = await tester.runAsync(
        () async => (await AppDatabase.instance.database).query('loan_payments'));
    expect(rows, hasLength(1));
    expect(rows!.single['amount_paid'], 300);
    await tester.runAsync(() => AppDatabase.instance.close());
  });
}
