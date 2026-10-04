import '../core/errors.dart';
import '../core/format.dart';
import '../data/database.dart';
import '../models/models.dart';
import 'loan_service.dart';

class BorrowerWithBalance {
  const BorrowerWithBalance(this.borrower, this.outstanding, this.activeLoans);
  final Borrower borrower;
  final double outstanding;
  final int activeLoans;
}

class BorrowerService {
  BorrowerService([AppDatabase? db]) : _app = db ?? AppDatabase.instance;
  final AppDatabase _app;

  Future<int> create({required String name, String? phone, String? address, String? notes}) async {
    if (name.trim().isEmpty) throw const ValidationException('Name is required');
    final db = await _app.database;
    final now = nowStamp();
    return db.insert('borrowers', {
      'name': name.trim(),
      'phone': _clean(phone),
      'address': _clean(address),
      'notes': _clean(notes),
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> update(Borrower b) async {
    if (b.id == null) throw const ValidationException('Borrower not saved yet');
    if (b.name.trim().isEmpty) throw const ValidationException('Name is required');
    final db = await _app.database;
    await db.update(
      'borrowers',
      {
        'name': b.name.trim(),
        'phone': _clean(b.phone),
        'address': _clean(b.address),
        'notes': _clean(b.notes),
        'updated_at': nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [b.id],
    );
  }

  Future<void> setArchived(int id, bool archived) async {
    final db = await _app.database;
    if (archived) {
      final active = await db.query('loans',
          where: 'borrower_id = ? AND status = ?', whereArgs: [id, RecordStatus.active]);
      if (active.isNotEmpty) {
        throw const ValidationException(
            'This borrower still has active loans. Complete them before archiving.');
      }
    }
    await db.update('borrowers', {'is_archived': archived ? 1 : 0, 'updated_at': nowStamp()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<Borrower> get(int id) async {
    final db = await _app.database;
    final rows = await db.query('borrowers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const ValidationException('Borrower not found');
    return Borrower.fromMap(rows.first);
  }

  Future<List<Borrower>> list({bool includeArchived = false, String query = ''}) async {
    final db = await _app.database;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('is_archived = 0');
    if (query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ?)');
      args.addAll(['%${query.trim()}%', '%${query.trim()}%']);
    }
    final rows = await db.query('borrowers',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'is_archived ASC, name COLLATE NOCASE ASC');
    return rows.map(Borrower.fromMap).toList();
  }

  Future<List<BorrowerWithBalance>> listWithBalances(
      {bool includeArchived = false, String query = ''}) async {
    final borrowers = await list(includeArchived: includeArchived, query: query);
    final summaries = await LoanService(_app).summaries(status: RecordStatus.active);
    final outstanding = <int, double>{};
    final counts = <int, int>{};
    for (final s in summaries) {
      final id = s.loan.borrowerId;
      outstanding[id] = (outstanding[id] ?? 0) + s.outstanding;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return borrowers
        .map((b) => BorrowerWithBalance(b, round2(outstanding[b.id] ?? 0), counts[b.id] ?? 0))
        .toList();
  }

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
