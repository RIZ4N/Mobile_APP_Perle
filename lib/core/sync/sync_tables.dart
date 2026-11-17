/// Deskripsi satu tabel yang disinkronkan antara SQLite dan Supabase.
class SyncTable {
  const SyncTable({
    required this.name,
    required this.columns,
    this.pk = 'id',
    this.boolColumns = const {},
    this.timestampColumns = const {},
    this.pushable = true,
  });

  final String name;
  final String pk;

  /// Kolom yang ada di server. Kolom khusus lokal (dirty, sync_error,
  /// receipt_local_path) sengaja tidak dicantumkan sehingga tidak pernah
  /// terkirim, dan kolom server yang belum dikenal aplikasi diabaikan.
  final List<String> columns;

  /// Kolom boolean (SQLite menyimpannya sebagai 0/1).
  final Set<String> boolColumns;

  /// Kolom timestamptz; dinormalkan ke UTC ISO-8601 saat disimpan lokal.
  final Set<String> timestampColumns;

  /// false = hanya ditarik dari server (mis. profiles).
  final bool pushable;

  Map<String, Object?> toRemote(Map<String, Object?> local) {
    return {
      for (final c in columns)
        c: boolColumns.contains(c) ? local[c] == 1 : local[c],
    };
  }

  Map<String, Object?> toLocal(Map<String, dynamic> remote) {
    final out = <String, Object?>{};
    for (final c in columns) {
      final v = remote[c];
      if (v == null) {
        out[c] = null;
      } else if (boolColumns.contains(c)) {
        out[c] = v == true ? 1 : 0;
      } else if (timestampColumns.contains(c)) {
        out[c] = DateTime.parse(v as String).toUtc().toIso8601String();
      } else {
        out[c] = v;
      }
    }
    return out;
  }
}

const profilesTable = SyncTable(
  name: 'profiles',
  columns: ['id', 'full_name', 'role', 'created_at', 'updated_at'],
  timestampColumns: {'created_at', 'updated_at'},
  pushable: false,
);

const itemsTable = SyncTable(
  name: 'items',
  columns: [
    'id',
    'name',
    'category',
    'quantity',
    'unit',
    'status',
    'source',
    'carrier_id',
    'carrier_name',
    'notes',
    'created_by',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
  timestampColumns: {'created_at', 'updated_at', 'deleted_at'},
);

const packingChecksTable = SyncTable(
  name: 'packing_checks',
  pk: 'item_id',
  columns: ['item_id', 'is_packed', 'packed_by', 'packed_at', 'updated_at'],
  boolColumns: {'is_packed'},
  timestampColumns: {'packed_at', 'updated_at'},
);

const loanLogsTable = SyncTable(
  name: 'loan_logs',
  columns: [
    'id',
    'item_id',
    'action',
    'quantity',
    'person_name',
    'note',
    'occurred_at',
    'recorded_by',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
  timestampColumns: {'occurred_at', 'created_at', 'updated_at', 'deleted_at'},
);

const expensesTable = SyncTable(
  name: 'expenses',
  columns: [
    'id',
    'description',
    'amount',
    'category',
    'spent_on',
    'paid_by_name',
    'receipt_path',
    'note',
    'created_by',
    'created_at',
    'updated_at',
    'deleted_at',
  ],
  timestampColumns: {'created_at', 'updated_at', 'deleted_at'},
);

/// Urutan penting: induk (items) dikirim sebelum anak (packing, log) agar
/// foreign key di server terpenuhi.
const syncTables = [
  profilesTable,
  itemsTable,
  packingChecksTable,
  loanLogsTable,
  expensesTable,
];
