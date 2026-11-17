import 'package:sqflite/sqflite.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import 'expense.dart';

class ExpenseRepository {
  ExpenseRepository(this._db, this._onWrite);

  final Database _db;
  final void Function() _onWrite;

  Future<List<Expense>> all() async {
    final rows = await _db.query(
      'expenses',
      where: 'deleted_at IS NULL',
      orderBy: 'spent_on DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<Expense?> byId(String id) async {
    final rows = await _db.query(
      'expenses',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Expense.fromMap(rows.first);
  }

  /// Menyimpan pengeluaran baru atau perubahannya. Foto struk baru cukup
  /// diisi di `receiptLocalPath` dengan `receiptPath` null; mesin sinkronisasi
  /// yang mengunggahnya saat online.
  Future<void> save(Expense e) async {
    await _db.insert('expenses', {
      'id': e.id,
      'description': e.description,
      'amount': e.amount,
      'category': e.category,
      'spent_on': toIsoDate(e.spentOn),
      'paid_by_name': e.paidByName,
      'receipt_path': e.receiptPath,
      'receipt_local_path': e.receiptLocalPath,
      'note': e.note,
      'created_by': e.createdBy,
      'created_at': e.createdAt,
      'updated_at': nowIso(),
      'deleted_at': null,
      'dirty': 1,
      'sync_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _onWrite();
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.update(
      'expenses',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    _onWrite();
  }
}
