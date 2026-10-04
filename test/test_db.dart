import 'package:loan_chit_manager/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points the app database at a fresh in-memory SQLite (no emulator needed).
Future<void> useFreshTestDatabase() async {
  sqfliteFfiInit();
  await AppDatabase.instance.close();
  AppDatabase.factoryOverride = databaseFactoryFfi;
  AppDatabase.pathOverride = inMemoryDatabasePath;
}
