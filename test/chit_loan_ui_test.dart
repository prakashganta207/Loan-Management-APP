import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/theme.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/screens/dashboard/dashboard_screen.dart';
import 'package:loan_chit_manager/screens/loans/loan_list_screen.dart';
import 'package:loan_chit_manager/services/chit_loan_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';

import 'dashboard_test.dart' show settle;
import 'test_db.dart';

void main() {
  Future<void> seedWinner(WidgetTester tester) => tester.runAsync(() async {
        await useFreshTestDatabase();
        final c = ChitService();
        final chit = await c.createChit(name: 'Diwali chit', chitValue: 100000, members: 2,
            durationMonths: 2, commissionPercent: 5, startDate: '2026-01-10');
        final m = await c.addMember(chitId: chit, name: 'Anu', phone: '9000000001');
        await c.addMember(chitId: chit, name: 'Bala');
        await c.recordAuction(chitId: chit, monthNumber: 1, winnerMemberId: m,
            winningAmount: 80000, auctionDate: '2026-01-10');
      });

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('dashboard shows the chit winner banner', (tester) async {
    await seedWinner(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const DashboardScreen()));
    await settle(tester);
    expect(find.text('1 chit winner needs loan setup'), findsOneWidget);
    await tester.runAsync(() => AppDatabase.instance.close());
  });

  testWidgets('Loans: waiting winner → monthly loan setup creates and links one loan',
      (tester) async {
    tallScreen(tester);
    await seedWinner(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const LoanListScreen()));
    await settle(tester);
    expect(find.text('Waiting for setup (1)'), findsOneWidget);
    expect(find.text('Anu'), findsOneWidget);

    await tester.tap(find.text('Anu'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Loan setup'), findsOneWidget);
    expect(find.text('Repayment type'), findsOneWidget);
    // Total payable is pre-filled with the prize (80,000 − 5% commission).
    expect(find.widgetWithText(TextFormField, '75000.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Number of months *'), '3');
    await tester.pump();
    expect(find.widgetWithText(TextFormField, '25000.00'), findsOneWidget); // total ÷ months

    await tester.tap(find.text('Create loan'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);

    final loans = await tester.runAsync(() => LoanService().listLoans());
    expect(loans, hasLength(1));
    final loan = loans!.single;
    expect([loan.isMonthly, loan.installmentAmount, loan.installmentCount, loan.startDate],
        [true, 25000, 3, '2026-02-10']); // first due one month after the auction
    expect(loan.borrowerName, 'Anu');
    // After setup the app opens the new loan, which links back to the chit.
    expect(find.text('From chit: Diwali chit, month 1'), findsOneWidget);
    expect(find.text('₹25,000.00 / month'), findsOneWidget);
    await tester.runAsync(() => AppDatabase.instance.close());
  });

  testWidgets('Loans: "Not a loan" dismisses with confirmation, then restore', (tester) async {
    tallScreen(tester);
    await seedWinner(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const LoanListScreen()));
    await settle(tester);

    await tester.tap(find.byTooltip('Not a loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Not a loan'));
    await settle(tester);
    expect(find.text('Waiting for setup (0)'), findsOneWidget);
    expect(find.text('Dismissed (1)'), findsOneWidget);

    await tester.tap(find.text('Dismissed (1)'));
    await tester.pump();
    await tester.tap(find.text('Restore'));
    await settle(tester);
    final waiting = await tester.runAsync(() => ChitLoanService().items());
    expect(waiting!.single.status, LoanSetupStatus.pending);
    await tester.runAsync(() => AppDatabase.instance.close());
  });
}
