import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the single SQLite connection. Tests swap in the ffi factory and an
/// in-memory path via [factoryOverride] / [pathOverride].
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static DatabaseFactory? factoryOverride;
  static String? pathOverride;
  static const int schemaVersion = 1;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final factory = factoryOverride ?? databaseFactory;
    final path = pathOverride ??
        p.join(await factory.getDatabasesPath(), 'loan_chit_manager.db');
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        // Future schema changes: add onUpgrade migrations here, never edit _onCreate silently.
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Tables holding business data, in parent → child order (used by backup/restore).
  static const dataTables = [
    'app_settings',
    'borrowers',
    'loans',
    'loan_payments',
    'chit_groups',
    'chit_members',
    'chit_auctions',
    'chit_contributions',
  ];

  /// DB-level guards for the append-only ledger and "loans are never deleted".
  static const _guardTriggers = {
    'loan_payments_no_update':
        "CREATE TRIGGER loan_payments_no_update BEFORE UPDATE ON loan_payments "
            "BEGIN SELECT RAISE(ABORT, 'loan_payments is append-only'); END",
    'loan_payments_no_delete':
        "CREATE TRIGGER loan_payments_no_delete BEFORE DELETE ON loan_payments "
            "BEGIN SELECT RAISE(ABORT, 'loan_payments is append-only'); END",
    'loans_no_delete': "CREATE TRIGGER loans_no_delete BEFORE DELETE ON loans "
        "BEGIN SELECT RAISE(ABORT, 'loans are never deleted; archive instead'); END",
  };

  static Future<void> createGuards(DatabaseExecutor db) async {
    for (final sql in _guardTriggers.values) {
      await db.execute(sql);
    }
  }

  /// Only the restore flow drops these, inside its own transaction.
  static Future<void> dropGuards(DatabaseExecutor db) async {
    for (final name in _guardTriggers.keys) {
      await db.execute('DROP TRIGGER IF EXISTS $name');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        pin_hash TEXT,
        biometric_enabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE borrowers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_id INTEGER NOT NULL REFERENCES borrowers(id) ON DELETE RESTRICT,
        loan_name TEXT NOT NULL,
        total_payable REAL NOT NULL CHECK (total_payable >= 0),
        daily_payment REAL NOT NULL CHECK (daily_payment >= 0),
        duration_days INTEGER NOT NULL CHECK (duration_days > 0),
        fine_per_day REAL NOT NULL DEFAULT 0 CHECK (fine_per_day >= 0),
        start_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active','completed','archived')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE loan_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
        payment_date TEXT NOT NULL,
        scheduled_amount REAL NOT NULL CHECK (scheduled_amount >= 0),
        amount_paid REAL NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
        fine_amount REAL NOT NULL DEFAULT 0 CHECK (fine_amount >= 0),
        status TEXT NOT NULL CHECK (status IN ('paid','missed','partial')),
        note TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE chit_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chit_name TEXT NOT NULL,
        chit_value REAL CHECK (chit_value IS NULL OR chit_value >= 0),
        number_of_members INTEGER NOT NULL CHECK (number_of_members > 0),
        duration_months INTEGER NOT NULL CHECK (duration_months > 0),
        commission_percent REAL NOT NULL DEFAULT 0 CHECK (commission_percent >= 0),
        start_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active','completed','archived')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE chit_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chit_group_id INTEGER NOT NULL REFERENCES chit_groups(id) ON DELETE CASCADE,
        member_name TEXT NOT NULL,
        phone TEXT,
        membership_status TEXT NOT NULL DEFAULT 'active'
          CHECK (membership_status IN ('active','inactive')),
        has_won INTEGER NOT NULL DEFAULT 0,
        joined_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE chit_auctions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chit_group_id INTEGER NOT NULL REFERENCES chit_groups(id) ON DELETE CASCADE,
        month_number INTEGER NOT NULL,
        auction_date TEXT NOT NULL,
        winner_member_id INTEGER NOT NULL REFERENCES chit_members(id),
        winning_amount REAL NOT NULL CHECK (winning_amount >= 0),
        discount REAL,
        commission_amount REAL,
        dividend_pool REAL,
        dividend_per_member REAL,
        created_at TEXT NOT NULL,
        UNIQUE (chit_group_id, month_number)
      )''');
    await db.execute('''
      CREATE TABLE chit_contributions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chit_group_id INTEGER NOT NULL REFERENCES chit_groups(id) ON DELETE CASCADE,
        chit_member_id INTEGER NOT NULL REFERENCES chit_members(id) ON DELETE CASCADE,
        month_number INTEGER NOT NULL,
        amount REAL NOT NULL CHECK (amount >= 0),
        status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('paid','pending')),
        payment_date TEXT,
        created_at TEXT NOT NULL,
        UNIQUE (chit_member_id, month_number)
      )''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    await db.execute('CREATE INDEX idx_loans_borrower ON loans(borrower_id)');
    await db.execute('CREATE INDEX idx_payments_loan ON loan_payments(loan_id)');
    await db.execute('CREATE INDEX idx_payments_created ON loan_payments(created_at)');
    await db.execute('CREATE INDEX idx_members_group ON chit_members(chit_group_id)');
    await db.execute(
        'CREATE INDEX idx_contrib_group_month ON chit_contributions(chit_group_id, month_number)');

    await createGuards(db);
  }
}
