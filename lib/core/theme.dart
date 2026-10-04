import 'package:flutter/material.dart';

/// Ledger-green base: reads as "money book", stays high-contrast outdoors.
class AppColors {
  static const seed = Color(0xFF1B5E20);
  static const paid = Color(0xFF2E7D32);
  static const partial = Color(0xFFE65100);
  static const missed = Color(0xFFC62828);
  static const neutral = Color(0xFF546E7A);
  static const info = Color(0xFF1565C0);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),
  );
}
