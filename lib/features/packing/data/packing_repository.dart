import 'package:sqflite/sqflite.dart';

import '../../../core/utils/ids.dart';

class PackingCheck {
  const PackingCheck({required this.itemId, this.packedBy, this.packedAt});

  final String itemId;
  final String? packedBy;
  final String? packedAt;
}

class PackingRepository {
  PackingRepository(this._db, this._onWrite);

  final Database _db;
  final void Function() _onWrite;

  /// Barang yang sudah dicentang, dipetakan per id barang.
  Future<Map<String, PackingCheck>> packed() async {
    final rows = await _db.query('packing_checks', where: 'is_packed = 1');
    return {
      for (final r in rows)
        r['item_id']! as String: PackingCheck(
          itemId: r['item_id']! as String,
          packedBy: r['packed_by'] as String?,
          packedAt: r['packed_at'] as String?,
        ),
    };
  }

  Future<void> setPacked(
    String itemId, {
    required bool packed,
    required String? userId,
  }) async {
    final now = nowIso();
    await _db.insert('packing_checks', {
      'item_id': itemId,
      'is_packed': packed ? 1 : 0,
      'packed_by': packed ? userId : null,
      'packed_at': packed ? now : null,
      'updated_at': now,
      'dirty': 1,
      'sync_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _onWrite();
  }

  /// Mengosongkan semua centang (mis. untuk packing pulang).
  Future<void> resetAll() async {
    await _db.update('packing_checks', {
      'is_packed': 0,
      'packed_by': null,
      'packed_at': null,
      'updated_at': nowIso(),
      'dirty': 1,
    }, where: 'is_packed = 1');
    _onWrite();
  }
}
