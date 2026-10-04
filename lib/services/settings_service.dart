import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

class SettingsKeys {
  static const upiId = 'upi_id';
  static const upiPayeeName = 'upi_payee_name';
  static const lastBackupAt = 'last_backup_at';
  static const backupReminder = 'backup_reminder';
}

class SettingsService {
  SettingsService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  Future<String?> get(String key) async {
    final db = await _app.database;
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value) async {
    final db = await _app.database;
    if (value == null || value.isEmpty) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getBool(String key) async => (await get(key)) == '1';
  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');
}
