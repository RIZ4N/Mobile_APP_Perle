enum ItemStatus {
  ada('ada', 'Ada'),
  harusBeli('harus_beli', 'Harus beli'),
  pinjam('pinjam', 'Pinjam');

  const ItemStatus(this.code, this.label);

  /// Nilai yang disimpan di database.
  final String code;
  final String label;

  static ItemStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => ItemStatus.ada);
}

const defaultItemCategories = [
  'Dapur',
  'Kebersihan',
  'P3K & Obat',
  'Elektronik',
  'ATK',
  'Program Kerja',
  'Tidur',
  'Lainnya',
];

const defaultUnits = ['buah', 'set', 'pak', 'dus', 'lusin', 'rol', 'botol'];

class Item {
  const Item({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.status,
    this.source,
    this.carrierId,
    this.carrierName,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  factory Item.fromMap(Map<String, Object?> map) => Item(
    id: map['id']! as String,
    name: map['name']! as String,
    category: map['category']! as String,
    quantity: map['quantity']! as int,
    unit: map['unit']! as String,
    status: ItemStatus.fromCode(map['status']! as String),
    source: map['source'] as String?,
    carrierId: map['carrier_id'] as String?,
    carrierName: map['carrier_name'] as String?,
    notes: map['notes'] as String?,
    createdBy: map['created_by'] as String?,
    createdAt: map['created_at']! as String,
  );

  final String id;
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final ItemStatus status;

  /// Milik siapa / dipinjam dari mana.
  final String? source;

  /// Penanggung jawab pembawa. [carrierId] terisi bila ia punya akun.
  final String? carrierId;
  final String? carrierName;
  final String? notes;
  final String? createdBy;
  final String createdAt;

  /// Kolom data (tanpa kolom sinkronisasi).
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'quantity': quantity,
    'unit': unit,
    'status': status.code,
    'source': source,
    'carrier_id': carrierId,
    'carrier_name': carrierName,
    'notes': notes,
    'created_by': createdBy,
    'created_at': createdAt,
  };
}
