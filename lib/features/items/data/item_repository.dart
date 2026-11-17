import 'package:sqflite/sqflite.dart';

import '../../../core/utils/ids.dart';
import 'item.dart';

class ItemRepository {
  ItemRepository(this._db, this._onWrite);

  final Database _db;
  final void Function() _onWrite;

  Future<List<Item>> all() async {
    final rows = await _db.query(
      'items',
      where: 'deleted_at IS NULL',
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(Item.fromMap).toList();
  }

  Future<Item?> byId(String id) async {
    final rows = await _db.query(
      'items',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Item.fromMap(rows.first);
  }

  /// Menyimpan barang baru atau perubahan atas barang yang sudah ada.
  Future<void> save(Item item) async {
    await _db.insert('items', {
      ...item.toMap(),
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
      'items',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    _onWrite();
  }
}
