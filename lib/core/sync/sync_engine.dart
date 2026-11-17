import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../utils/ids.dart';
import 'remote_store.dart';
import 'sync_tables.dart';

class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.failed,
  });

  /// Baris lokal yang berhasil terkirim.
  final int pushed;

  /// Baris lokal yang berubah karena data server.
  final int pulled;

  /// Baris yang ditolak server (tetap tersimpan lokal, lihat `sync_error`).
  final int failed;
}

/// Sinkronisasi dua arah SQLite ⇄ Supabase.
///
/// 1. Unggah foto struk yang belum terunggah.
/// 2. Push: kirim semua baris `dirty = 1` dengan upsert.
/// 3. Pull: ambil baris server yang `updated_at`-nya melewati kursor.
///
/// Konflik diselesaikan "tulisan terakhir yang menang" per baris: perubahan
/// lokal yang belum terkirim tidak ditimpa pull, lalu menimpa server saat push.
class SyncEngine {
  SyncEngine({required this.db, required this.remote, this.pageSize = 500});

  final Database db;
  final RemoteStore remote;
  final int pageSize;

  /// Server mengisi `updated_at` saat transaksi dimulai, jadi baris yang
  /// commit-nya terlambat bisa punya stempel sedikit di belakang kursor.
  /// Mundurkan kursor sejauh ini agar baris seperti itu tidak terlewat.
  static const _cursorOverlap = Duration(seconds: 30);

  Future<SyncResult> sync() async {
    var failed = await _uploadReceipts();
    var pushed = 0;
    for (final table in syncTables.where((t) => t.pushable)) {
      final r = await _push(table);
      pushed += r.pushed;
      failed += r.failed;
    }
    var pulled = 0;
    for (final table in syncTables) {
      pulled += await _pull(table);
    }
    return SyncResult(pushed: pushed, pulled: pulled, failed: failed);
  }

  /// Jumlah baris yang menunggu dikirim.
  Future<int> pendingCount() async {
    var total = 0;
    for (final t in syncTables.where((t) => t.pushable)) {
      total += await _count(t.name, 'dirty = 1');
    }
    return total;
  }

  /// Jumlah baris yang terakhir kali ditolak server.
  Future<int> failedCount() async {
    var total = 0;
    for (final t in syncTables.where((t) => t.pushable)) {
      total += await _count(t.name, 'sync_error IS NOT NULL');
    }
    return total;
  }

  /// Membuang perubahan lokal yang ditolak server, lalu mengulang pull penuh
  /// sehingga versi server kembali dipakai.
  Future<void> discardFailed() async {
    await db.transaction((txn) async {
      for (final t in syncTables.where((t) => t.pushable)) {
        await txn.delete(t.name, where: 'sync_error IS NOT NULL');
      }
      await txn.delete('sync_meta');
    });
  }

  Future<int> _count(String table, String where) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $table WHERE $where',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------- struk

  Future<int> _uploadReceipts() async {
    final rows = await db.query(
      'expenses',
      columns: ['id', 'receipt_local_path'],
      where:
          'receipt_local_path IS NOT NULL AND receipt_path IS NULL '
          'AND deleted_at IS NULL',
    );
    var failed = 0;
    for (final row in rows) {
      final id = row['id']! as String;
      final file = File(row['receipt_local_path']! as String);
      if (!file.existsSync()) {
        await db.update(
          'expenses',
          {'receipt_local_path': null},
          where: 'id = ?',
          whereArgs: [id],
        );
        continue;
      }
      try {
        final path = await remote.uploadReceipt(expenseId: id, file: file);
        await db.update(
          'expenses',
          {'receipt_path': path, 'updated_at': nowIso(), 'dirty': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      } on RemoteRejected catch (e) {
        failed++;
        await db.update(
          'expenses',
          {'sync_error': 'Unggah struk ditolak: ${e.message}'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    return failed;
  }

  // ----------------------------------------------------------------- push

  Future<({int pushed, int failed})> _push(SyncTable t) async {
    final rows = await db.query(t.name, where: 'dirty = 1');
    if (rows.isEmpty) return (pushed: 0, failed: 0);

    try {
      await remote.upsert(
        t.name,
        rows.map(t.toRemote).toList(),
        onConflict: t.pk,
      );
      await _markClean(t, rows);
      return (pushed: rows.length, failed: 0);
    } on RemoteRejected {
      // Satu baris bermasalah menggagalkan seluruh batch → kirim satu per
      // satu supaya baris yang sehat tetap terkirim.
    }

    var pushed = 0;
    var failed = 0;
    for (final row in rows) {
      try {
        await remote.upsert(t.name, [t.toRemote(row)], onConflict: t.pk);
        await _markClean(t, [row]);
        pushed++;
      } on RemoteRejected catch (e) {
        failed++;
        await db.update(
          t.name,
          {'sync_error': e.message},
          where: '${t.pk} = ?',
          whereArgs: [row[t.pk]],
        );
      }
    }
    return (pushed: pushed, failed: failed);
  }

  Future<void> _markClean(SyncTable t, List<Map<String, Object?>> rows) async {
    final batch = db.batch();
    for (final row in rows) {
      // Cocokkan updated_at: bila baris diubah lagi selagi push berjalan,
      // ia tetap dirty dan ikut putaran berikutnya.
      batch.update(
        t.name,
        {'dirty': 0, 'sync_error': null},
        where: '${t.pk} = ? AND updated_at = ?',
        whereArgs: [row[t.pk], row['updated_at']],
      );
    }
    await batch.commit(noResult: true);
  }

  // ----------------------------------------------------------------- pull

  Future<int> _pull(SyncTable t) async {
    final cursor = await _cursor(t.name);
    final since = cursor == null
        ? null
        : DateTime.parse(cursor)
              .subtract(_cursorOverlap)
              .toUtc()
              .toIso8601String();

    var newest = cursor == null ? null : DateTime.parse(cursor);
    var changed = 0;
    var offset = 0;

    while (true) {
      final page = await remote.fetchChanged(
        t.name,
        pk: t.pk,
        since: since,
        limit: pageSize,
        offset: offset,
      );

      await db.transaction((txn) async {
        for (final remoteRow in page) {
          final row = t.toLocal(remoteRow);
          final updatedAt = DateTime.parse(row['updated_at']! as String);
          if (newest == null || updatedAt.isAfter(newest!)) newest = updatedAt;

          final existing = await txn.query(
            t.name,
            columns: ['dirty', 'updated_at'],
            where: '${t.pk} = ?',
            whereArgs: [row[t.pk]],
          );
          if (existing.isEmpty) {
            await txn.insert(t.name, {...row, 'dirty': 0});
            changed++;
          } else if (existing.first['dirty'] == 1) {
            // Ada perubahan lokal yang belum terkirim → jangan ditimpa.
            continue;
          } else if (existing.first['updated_at'] != row['updated_at']) {
            await txn.update(
              t.name,
              row,
              where: '${t.pk} = ?',
              whereArgs: [row[t.pk]],
            );
            changed++;
          }
        }
      });

      if (page.length < pageSize) break;
      offset += page.length;
    }

    final newCursor = newest?.toUtc().toIso8601String();
    if (newCursor != null && newCursor != cursor) {
      await db.insert('sync_meta', {
        'table_name': t.name,
        'cursor': newCursor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return changed;
  }

  Future<String?> _cursor(String table) async {
    final rows = await db.query(
      'sync_meta',
      columns: ['cursor'],
      where: 'table_name = ?',
      whereArgs: [table],
    );
    return rows.isEmpty ? null : rows.first['cursor'] as String?;
  }
}
