enum LoanAction {
  pinjam('pinjam', 'Pinjam'),
  kembali('kembali', 'Kembali');

  const LoanAction(this.code, this.label);

  final String code;
  final String label;

  static LoanAction fromCode(String code) =>
      code == 'kembali' ? LoanAction.kembali : LoanAction.pinjam;
}

class LoanLog {
  const LoanLog({
    required this.id,
    required this.itemId,
    required this.action,
    required this.quantity,
    required this.personName,
    this.note,
    required this.occurredAt,
    this.recordedBy,
    this.itemName,
  });

  factory LoanLog.fromMap(Map<String, Object?> map) => LoanLog(
    id: map['id']! as String,
    itemId: map['item_id']! as String,
    action: LoanAction.fromCode(map['action']! as String),
    quantity: map['quantity']! as int,
    personName: map['person_name']! as String,
    note: map['note'] as String?,
    occurredAt: DateTime.parse(map['occurred_at']! as String),
    recordedBy: map['recorded_by'] as String?,
    itemName: map['item_name'] as String?,
  );

  final String id;
  final String itemId;
  final LoanAction action;
  final int quantity;

  /// Peminjam (atau yang mengembalikan).
  final String personName;
  final String? note;
  final DateTime occurredAt;
  final String? recordedBy;

  /// Terisi hanya pada kueri yang menggabungkan tabel barang.
  final String? itemName;
}

/// Barang yang masih dipegang seseorang.
class Outstanding {
  const Outstanding({
    required this.itemId,
    required this.personName,
    required this.quantity,
    this.itemName,
  });

  final String itemId;
  final String personName;
  final int quantity;
  final String? itemName;
}
