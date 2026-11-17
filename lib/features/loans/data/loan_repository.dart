import 'package:sqflite/sqflite.dart';

import '../../../core/utils/ids.dart';
import 'loan_log.dart';

/// Riwayat pinjam/kembali. Tidak ada kolom "stok dipinjam" yang disimpan:
/// jumlahnya selalu dihitung dari log (pinjam − kembali), sehingga catatan
/// dari beberapa HP yang offline tidak saling menimpa.
class LoanRepository {
  LoanRepository(this._db, this._onWrite);

  final Database _db;
  final void Function() _onWrite;

  static const _signedQty =
      "SUM(CASE l.action WHEN 'pinjam' THEN l.quantity ELSE -l.quantity END)";

  Future<void> record({
    required String itemId,
    required LoanAction action,
    required int quantity,
    required String personName,
    String? note,
    required String? recordedBy,
  }) async {
    final now = nowIso();
    await _db.insert('loan_logs', {
      'id': newId(),
      'item_id': itemId,
      'action': action.code,
      'quantity': quantity,
      'person_name': personName.trim(),
      'note': note,
      'occurred_at': now,
      'recorded_by': recordedBy,
      'created_at': now,
      'updated_at': now,
      'dirty': 1,
    });
    _onWrite();
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.update(
      'loan_logs',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    _onWrite();
  }

  /// Log terbaru (semua barang, atau satu barang bila [itemId] diisi).
  Future<List<LoanLog>> logs({String? itemId, int limit = 200}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.*, i.name AS item_name
      FROM loan_logs l
      LEFT JOIN items i ON i.id = l.item_id
      WHERE l.deleted_at IS NULL ${itemId == null ? '' : 'AND l.item_id = ?'}
      ORDER BY l.occurred_at DESC
      LIMIT ?
      ''',
      [?itemId, limit],
    );
    return rows.map(LoanLog.fromMap).toList();
  }

  /// Jumlah yang sedang dipinjam, per id barang.
  Future<Map<String, int>> outstandingByItem() async {
    final rows = await _db.rawQuery('''
      SELECT l.item_id, $_signedQty AS qty
      FROM loan_logs l
      WHERE l.deleted_at IS NULL
      GROUP BY l.item_id
      HAVING qty > 0
    ''');
    return {for (final r in rows) r['item_id']! as String: r['qty']! as int};
  }

  /// Siapa memegang apa (semua barang, atau satu barang bila [itemId] diisi).
  Future<List<Outstanding>> outstanding({String? itemId}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.item_id, MIN(l.person_name) AS person_name,
             $_signedQty AS qty, i.name AS item_name
      FROM loan_logs l
      LEFT JOIN items i ON i.id = l.item_id
      WHERE l.deleted_at IS NULL ${itemId == null ? '' : 'AND l.item_id = ?'}
      GROUP BY l.item_id, LOWER(TRIM(l.person_name))
      HAVING qty > 0
      ORDER BY i.name COLLATE NOCASE, person_name COLLATE NOCASE
      ''',
      [?itemId],
    );
    return [
      for (final r in rows)
        Outstanding(
          itemId: r['item_id']! as String,
          personName: r['person_name']! as String,
          quantity: r['qty']! as int,
          itemName: r['item_name'] as String?,
        ),
    ];
  }
}
