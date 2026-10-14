import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/format.dart';
import 'package:loan_chit_manager/core/theme.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/screens/auth/login_screen.dart';
import 'package:loan_chit_manager/screens/loans/loan_details_screen.dart';
import 'package:loan_chit_manager/screens/loans/payment_entry_screen.dart';
import 'package:loan_chit_manager/services/auth_service.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';
import 'package:loan_chit_manager/services/settings_service.dart';

import 'dashboard_test.dart' show settle;
import 'test_db.dart';

void main() {
  testWidgets('AUDIT A4: closing the login screen during "Forgot password" does not crash',
      (tester) async {
    await tester.runAsync(() async {
      await useFreshTestDatabase();
      await AuthService().createUser(username: 'Lakshmi', password: 'secret1');
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const LoginScreen()));
    await settle(tester);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset login')); // starts resetAuth()...
    await tester.pumpWidget(const SizedBox()); // ...and the screen is closed at once
    await settle(tester);

    expect(tester.takeException(), isNull);
    await tester.runAsync(() => AppDatabase.instance.close());
  });

  for (final upiSet in [false, true]) {
    testWidgets('AUDIT A12: UPI buttons ${upiSet ? 'shown' : 'hidden'} when a UPI ID is '
        '${upiSet ? 'set' : 'not set'}', (tester) async {
      late int loanId;
      await tester.runAsync(() async {
        await useFreshTestDatabase();
        if (upiSet) await SettingsService().set(SettingsKeys.upiId, 'ravi@okbank');
        final b = await BorrowerService().create(name: 'Ravi');
        loanId = await LoanService().createLoan(borrowerId: b, loanName: 'Shop loan',
            totalPayable: 3000, dailyPayment: 300, durationDays: 10, startDate: todayKey());
      });
      final matcher = upiSet ? findsOneWidget : findsNothing;
      tester.view.physicalSize = const Size(400, 1600); // tall enough to build every button
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: LoanDetailsScreen(loanId: loanId)));
      await settle(tester);
      expect(find.text('Pay via UPI'), matcher);

      await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: PaymentEntryScreen(loanId: loanId)));
      await settle(tester);
      expect(find.text('Collect via UPI, then save'), matcher);
      await tester.runAsync(() => AppDatabase.instance.close());
    });
  }
}
