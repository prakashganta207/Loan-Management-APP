import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/theme.dart';
import 'package:loan_chit_manager/data/database.dart';
import 'package:loan_chit_manager/screens/auth/login_screen.dart';
import 'package:loan_chit_manager/services/auth_service.dart';

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
}
