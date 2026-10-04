import 'package:flutter/material.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/borrowers/borrower_list_screen.dart';
import 'screens/calculator/calculator_screen.dart';
import 'screens/chits/chit_list_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/loans/loan_list_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings/settings_screen.dart';

class LoanChitApp extends StatelessWidget {
  const LoanChitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loan & Chit Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      initialRoute: Routes.splash,
      routes: {
        Routes.splash: (_) => const SplashScreen(),
        Routes.login: (_) => const LoginScreen(),
        Routes.dashboard: (_) => const DashboardScreen(),
        Routes.borrowers: (_) => const BorrowerListScreen(),
        Routes.loans: (_) => const LoanListScreen(),
        Routes.chits: (_) => const ChitListScreen(),
        Routes.calculator: (_) => const CalculatorScreen(),
        Routes.reports: (_) => const ReportsScreen(),
        Routes.settings: (_) => const SettingsScreen(),
      },
    );
  }
}
