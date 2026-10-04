import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';
import 'settings_service.dart';

class BackupService {
  BackupService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  static const appTag = 'loan_chit_manager';

  /// Everything except login credentials.
  Future<Map<String, dynamic>> buildSnapshot() async {
    final db = await _app.database;
    final tables = <String, dynamic>{};
    for (final t in AppDatabase.dataTables) {
      tables[t] = await db.query(t);
    }
    return {
      'app': appTag,
      'schema_version': AppDatabase.schemaVersion,
      'exported_at': nowStamp(),
      'tables': tables,
    };
  }

  Future<File> exportBackup() async {
    final snapshot = await buildSnapshot();
    final dir = await backupDirectory();
    final name = 'loan_chit_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert(snapshot));
    await SettingsService(_app).set(SettingsKeys.lastBackupAt, nowStamp());
    return file;
  }

  /// Android: Android/data/<package>/files/backups (visible in file managers).
  Future<Directory> backupDirectory() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'backups'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> restoreFromFile(String path) async {
    Object? decoded;
    try {
      decoded = jsonDecode(await File(path).readAsString());
    } catch (_) {
      throw const ValidationException('That file is not a readable backup');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationException('That file is not a Loan & Chit Manager backup');
    }
    await restoreSnapshot(decoded);
  }

  /// Replaces all business data with the snapshot, atomically.
  /// Older snapshots are accepted: columns they lack take the schema defaults
  /// (v1 chits become 'from_dividend', v1 auctions get winner_payout = winning_amount).
  Future<void> restoreSnapshot(Map<String, dynamic> data) async {
    if (data['app'] != appTag || data['tables'] is! Map) {
      throw const ValidationException('That file is not a Loan & Chit Manager backup');
    }
    final version = data['schema_version'];
    if (version is int && version > AppDatabase.schemaVersion) {
      throw const ValidationException('This backup is from a newer app version');
    }
    final tables = Map<String, dynamic>.from(data['tables'] as Map);
    final db = await _app.database;
    await db.transaction((txn) async {
      await AppDatabase.dropGuards(txn);
      for (final t in AppDatabase.dataTables.reversed) {
        await txn.delete(t);
      }
      for (final t in AppDatabase.dataTables) {
        final rows = (tables[t] as List?) ?? const [];
        for (final r in rows) {
          await txn.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
      await AppDatabase.backfillWinnerPayout(txn);
      await AppDatabase.createGuards(txn);
    });
  }
}
