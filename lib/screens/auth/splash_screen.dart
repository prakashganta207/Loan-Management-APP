import 'package:flutter/material.dart';

import '../../core/routes.dart';
import '../../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // Opens the database (creating it on first run) and checks for an account.
      final hasUser = await AuthService().hasUser();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.login, arguments: hasUser);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primaryContainer,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 84, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Loan & Chit Manager',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              if (_error == null)
                const CircularProgressIndicator()
              else
                Text('Could not open the database:\n$_error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
