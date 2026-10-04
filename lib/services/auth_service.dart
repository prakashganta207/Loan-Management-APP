import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.hasPin,
    required this.biometricEnabled,
  });
  final int id;
  final String username;
  final bool hasPin;
  final bool biometricEnabled;
}

/// Local-only auth. Secrets are stored as `salt$hash` (iterated SHA-256),
/// never as plaintext.
class AuthService {
  AuthService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  static const _iterations = 10000;

  static String hashSecret(String secret, {String? salt}) {
    final rnd = Random.secure();
    final s = salt ?? base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    List<int> digest = utf8.encode('$s:$secret');
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return '$s\$${base64UrlEncode(digest)}';
  }

  static bool verifySecret(String secret, String? stored) {
    if (stored == null) return false;
    final idx = stored.indexOf('\$');
    if (idx <= 0) return false;
    return hashSecret(secret, salt: stored.substring(0, idx)) == stored;
  }

  Future<Map<String, Object?>?> _row() async {
    final db = await _app.database;
    final rows = await db.query('users', orderBy: 'id ASC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> hasUser() async => (await _row()) != null;

  Future<AppUser?> currentUser() async {
    final r = await _row();
    if (r == null) return null;
    return AppUser(
      id: r['id'] as int,
      username: r['username'] as String? ?? '',
      hasPin: r['pin_hash'] != null,
      biometricEnabled: (r['biometric_enabled'] as int? ?? 0) == 1,
    );
  }

  static void _checkPassword(String pw) {
    if (pw.length < 6) throw const ValidationException('Password must be at least 6 characters');
  }

  static void _checkPin(String pin) {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const ValidationException('PIN must be 4 to 6 digits');
    }
  }

  Future<void> createUser({required String username, required String password, String? pin}) async {
    if (username.trim().isEmpty) throw const ValidationException('Username is required');
    _checkPassword(password);
    if (pin != null && pin.isNotEmpty) _checkPin(pin);
    if (await hasUser()) throw const ValidationException('An account already exists');
    final db = await _app.database;
    await db.insert('users', {
      'username': username.trim(),
      'password_hash': hashSecret(password),
      'pin_hash': (pin == null || pin.isEmpty) ? null : hashSecret(pin),
      'biometric_enabled': 0,
      'created_at': nowStamp(),
    });
  }

  Future<bool> verifyPassword(String password) async =>
      verifySecret(password, (await _row())?['password_hash'] as String?);

  Future<bool> verifyPin(String pin) async =>
      verifySecret(pin, (await _row())?['pin_hash'] as String?);

  Future<void> changePassword(String current, String next) async {
    if (!await verifyPassword(current)) {
      throw const ValidationException('Current password is wrong');
    }
    _checkPassword(next);
    final db = await _app.database;
    await db.update('users', {'password_hash': hashSecret(next)});
  }

  /// Pass null to remove the PIN.
  Future<void> setPin(String? pin) async {
    if (pin != null) _checkPin(pin);
    final db = await _app.database;
    await db.update('users', {'pin_hash': pin == null ? null : hashSecret(pin)});
  }

  Future<void> setBiometric(bool enabled) async {
    final db = await _app.database;
    await db.update('users', {'biometric_enabled': enabled ? 1 : 0});
  }

  /// "Forgot password": wipes local credentials only. Business data stays.
  Future<void> resetAuth() async {
    final db = await _app.database;
    await db.delete('users');
  }
}
