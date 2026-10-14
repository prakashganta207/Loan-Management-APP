// AUDIT A6 regression: every screen renders on a 360 dp phone with a 1.3× system font,
// with real (long, large) data and with an empty database. Overflow = test failure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/format.dart';
import 'package:loan_chit_manager/core/theme.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/screens/auth/login_screen.dart';
import 'package:loan_chit_manager/screens/borrowers/borrower_form_screen.dart';
import 'package:loan_chit_manager/screens/borrowers/borrower_list_screen.dart';
import 'package:loan_chit_manager/screens/borrowers/borrower_profile_screen.dart';
import 'package:loan_chit_manager/screens/calculator/calculator_screen.dart';
import 'package:loan_chit_manager/screens/chits/auction_entry_screen.dart';
import 'package:loan_chit_manager/screens/chits/chit_details_screen.dart';
import 'package:loan_chit_manager/screens/chits/chit_form_screen.dart';
import 'package:loan_chit_manager/screens/chits/chit_list_screen.dart';
import 'package:loan_chit_manager/screens/chits/member_form_screen.dart';
import 'package:loan_chit_manager/screens/dashboard/dashboard_screen.dart';
import 'package:loan_chit_manager/screens/loans/loan_details_screen.dart';
import 'package:loan_chit_manager/screens/loans/loan_form_screen.dart';
import 'package:loan_chit_manager/screens/loans/loan_list_screen.dart';
import 'package:loan_chit_manager/screens/loans/payment_entry_screen.dart';
import 'package:loan_chit_manager/screens/reports/reports_screen.dart';
import 'package:loan_chit_manager/screens/settings/settings_screen.dart';
import 'package:loan_chit_manager/services/auth_service.dart';
import 'package:loan_chit_manager/services/borrower_service.dart';
import 'package:loan_chit_manager/services/chit_service.dart';
import 'package:loan_chit_manager/services/loan_service.dart';

import 'test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Map<String, int> ids;

  Future<void> seed({bool empty = false}) async {
    await useFreshTestDatabase();
    ids = {};
    if (empty) return;
    await AuthService().createUser(username: 'Lakshmi Narayanan', password: 'secret1', pin: '1234');
    final b = await BorrowerService().create(name: 'Venkata Subramanian Ramakrishnan'); // no phone
    ids['borrower'] = b;
    final l = await LoanService().createLoan(
        borrowerId: b, loanName: 'Very long shop renovation loan name', totalPayable: 1234567.89,
        dailyPayment: 12345.67, durationDays: 100, finePerDay: 123.45,
        startDate: dateKey(addDays(DateTime.now(), -5)));
    ids['loan'] = l;
    await LoanService().recordPayment(loanId: l, slotDate: dateKey(addDays(DateTime.now(), -5)),
        amount: 30000, fine: 500);
    final c = ChitService();
    ids['chitNoValue'] = await c.createChit(
        name: 'No value chit', members: 3, durationMonths: 3, startDate: todayKey());
    final ch = await c.createChit(name: 'Deepavali mega chit group', chitValue: 10000000,
        members: 3, durationMonths: 3, commissionPercent: 5, startDate: todayKey());
    ids['chit'] = ch;
    final m = await c.addMember(chitId: ch, name: 'Member with a rather long name');
    await c.addMember(chitId: ch, name: 'B');
    await c.recordAuction(chitId: ch, monthNumber: 1, winnerMemberId: m, winningAmount: 8000000,
        auctionDate: todayKey());
    await c.ensureContributions(ch, 1);
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: screen));
    await settle(tester);
  }

  final screens = <String, Widget Function()>{
    'dashboard': () => const DashboardScreen(),
    'borrowers': () => const BorrowerListScreen(),
    'borrowerProfile': () => BorrowerProfileScreen(borrowerId: ids['borrower'] ?? 1),
    'borrowerForm': () => const BorrowerFormScreen(),
    'loans': () => const LoanListScreen(),
    'loanForm': () => const LoanFormScreen(),
    'loanDetails': () => LoanDetailsScreen(loanId: ids['loan'] ?? 1),
    'paymentEntry': () => PaymentEntryScreen(loanId: ids['loan'] ?? 1),
    'chits': () => const ChitListScreen(),
    'chitForm': () => const ChitFormScreen(),
    'chitDetails': () => ChitDetailsScreen(chitId: ids['chit'] ?? 1),
    'chitDetailsNoValue': () => ChitDetailsScreen(chitId: ids['chitNoValue'] ?? 1),
    'auctionEntry': () => AuctionEntryScreen(chitId: ids['chit'] ?? 1),
    'auctionNoValue': () => AuctionEntryScreen(chitId: ids['chitNoValue'] ?? 1),
    'memberForm': () => MemberFormScreen(chitId: ids['chit'] ?? 1),
    'calculator': () => const CalculatorScreen(),
    'reports': () => const ReportsScreen(),
    'settings': () => const SettingsScreen(),
    'login': () => const LoginScreen(),
  };

  for (final empty in [false, true]) {
    for (final e in screens.entries) {
      if (empty && {'borrowerProfile', 'loanDetails', 'paymentEntry', 'chitDetails',
          'chitDetailsNoValue', 'auctionEntry', 'auctionNoValue', 'memberForm'}.contains(e.key)) {
        continue;
      }
      testWidgets('${empty ? 'empty' : 'seeded'} ${e.key} at 360 dp, 1.3x text', (tester) async {
        await tester.runAsync(() => seed(empty: empty));
        await show(tester, e.value());
        if (e.key.startsWith('chitDetails') || e.key == 'reports') {
          for (final tab in ['Auctions', 'Contributions', 'Monthly', 'Overall']) {
            final f = find.text(tab);
            if (f.evaluate().isNotEmpty) {
              await tester.tap(f.first);
              await settle(tester);
              await tester.pump(const Duration(seconds: 1));
              await settle(tester);
            }
          }
        }
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: '${e.key} should have finished loading');
        await tester.runAsync(() => AppDatabase.instance.close());
      });
    }
  }
}
