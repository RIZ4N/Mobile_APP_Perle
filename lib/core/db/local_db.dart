import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database SQLite lokal = sumber data seluruh layar. Supabase hanya disentuh
/// oleh mesin sinkronisasi.
///
/// Kolom tambahan khusus lokal di setiap tabel tersinkron:
///   * `dirty`      1 = ada perubahan lokal yang belum terkirim
///   * `sync_error` pesan penolakan server terakhir (null = aman)
const localDbVersion = 1;

const _syncColumns = '''
  dirty INTEGER NOT NULL DEFAULT 0,
  sync_error TEXT
''';

const _schema = <String>[
  '''
  CREATE TABLE profiles (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL,
    created_at TEXT,
    updated_at TEXT,
    $_syncColumns
  )
  ''',
  '''
  CREATE TABLE items (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit TEXT NOT NULL,
    status TEXT NOT NULL,
    source TEXT,
    carrier_id TEXT,
    carrier_name TEXT,
    notes TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    $_syncColumns
  )
  ''',
  '''
  CREATE TABLE packing_checks (
    item_id TEXT PRIMARY KEY,
    is_packed INTEGER NOT NULL DEFAULT 0,
    packed_by TEXT,
    packed_at TEXT,
    updated_at TEXT NOT NULL,
    $_syncColumns
  )
  ''',
  '''
  CREATE TABLE loan_logs (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL,
    action TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    person_name TEXT NOT NULL,
    note TEXT,
    occurred_at TEXT NOT NULL,
    recorded_by TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    $_syncColumns
  )
  ''',
  'CREATE INDEX loan_logs_item_idx ON loan_logs (item_id)',
  '''
  CREATE TABLE expenses (
    id TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    amount INTEGER NOT NULL,
    category TEXT,
    spent_on TEXT NOT NULL,
    paid_by_name TEXT,
    receipt_path TEXT,
    note TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    receipt_local_path TEXT,
    $_syncColumns
  )
  ''',
  // Kursor pull per tabel (updated_at server terakhir yang sudah diambil).
  '''
  CREATE TABLE sync_meta (
    table_name TEXT PRIMARY KEY,
    cursor TEXT
  )
  ''',
];

const localTables = [
  'profiles',
  'items',
  'packing_checks',
  'loan_logs',
  'expenses',
  'sync_meta',
];

Future<void> createLocalSchema(Database db, int version) async {
  for (final sql in _schema) {
    await db.execute(sql);
  }
}

Future<Database> openLocalDb() async {
  final path = p.join(await getDatabasesPath(), 'perle.db');
  return openDatabase(
    path,
    version: localDbVersion,
    onCreate: createLocalSchema,
  );
}

/// Mengosongkan semua data lokal (dipakai saat keluar akun).
Future<void> wipeLocalDb(Database db) async {
  await db.transaction((txn) async {
    for (final table in localTables) {
      await txn.delete(table);
    }
  });
}
