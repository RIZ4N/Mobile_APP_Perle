import 'dart:io';

import 'package:perle/core/db/local_db.dart';
import 'package:perle/core/sync/remote_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database SQLite di memori dengan skema aplikasi.
Future<Database> openTestDb() {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: localDbVersion,
      onCreate: createLocalSchema,
      singleInstance: false,
    ),
  );
}

/// Tiruan server: menyimpan baris per tabel dan, seperti trigger di Supabase,
/// selalu mengisi `updated_at` dengan jam server.
class FakeRemote implements RemoteStore {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final uploads = <String>[];

  /// Jam server; maju satu detik tiap baris ditulis.
  DateTime clock = DateTime.utc(2027, 1, 5, 8);

  /// true = semua panggilan gagal seperti tidak ada jaringan.
  bool offline = false;

  /// Baris yang ditolak server (mis. melanggar RLS).
  bool Function(String table, Map<String, Object?> row)? reject;

  int upsertCalls = 0;

  void _checkOnline() {
    if (offline) throw const SocketException('offline');
  }

  String _tick() {
    clock = clock.add(const Duration(seconds: 1));
    // Meniru format timestamptz dari PostgREST.
    return clock.toIso8601String().replaceFirst('Z', '+00:00');
  }

  /// Menulis langsung ke "server" seolah-olah dari HP lain.
  void serverWrite(String table, Map<String, dynamic> row, {String pk = 'id'}) {
    (tables[table] ??= {})[row[pk] as String] = {...row, 'updated_at': _tick()};
  }

  Map<String, dynamic>? row(String table, String id) => tables[table]?[id];

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    required String onConflict,
  }) async {
    _checkOnline();
    upsertCalls++;
    // Seperti Postgres: satu baris ditolak → seluruh pernyataan batal.
    for (final r in rows) {
      if (reject?.call(table, r) ?? false) {
        throw RemoteRejected('ditolak: ${r[onConflict]}');
      }
    }
    for (final r in rows) {
      serverWrite(table, Map<String, dynamic>.of(r), pk: onConflict);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String pk,
    String? since,
    required int limit,
    required int offset,
  }) async {
    _checkOnline();
    final sinceTime = since == null ? null : DateTime.parse(since);
    final rows =
        (tables[table]?.values ?? const <Map<String, dynamic>>[])
            .where(
              (r) =>
                  sinceTime == null ||
                  !DateTime.parse(r['updated_at'] as String)
                      .isBefore(sinceTime),
            )
            .toList()
          ..sort((a, b) {
            final byTime = DateTime.parse(a['updated_at'] as String)
                .compareTo(DateTime.parse(b['updated_at'] as String));
            return byTime != 0
                ? byTime
                : (a[pk] as String).compareTo(b[pk] as String);
          });
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<String> uploadReceipt({
    required String expenseId,
    required File file,
  }) async {
    _checkOnline();
    final path = '$expenseId/${uploads.length + 1}.jpg';
    uploads.add(path);
    return path;
  }
}
