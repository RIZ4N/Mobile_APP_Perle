const defaultExpenseCategories = [
  'Perlengkapan',
  'Konsumsi',
  'Transportasi',
  'Program Kerja',
  'Lainnya',
];

class Expense {
  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    this.category,
    required this.spentOn,
    this.paidByName,
    this.receiptPath,
    this.receiptLocalPath,
    this.note,
    this.createdBy,
    required this.createdAt,
  });

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map['id']! as String,
    description: map['description']! as String,
    amount: map['amount']! as int,
    category: map['category'] as String?,
    spentOn: DateTime.parse(map['spent_on']! as String),
    paidByName: map['paid_by_name'] as String?,
    receiptPath: map['receipt_path'] as String?,
    receiptLocalPath: map['receipt_local_path'] as String?,
    note: map['note'] as String?,
    createdBy: map['created_by'] as String?,
    createdAt: map['created_at']! as String,
  );

  final String id;
  final String description;

  /// Rupiah, tanpa desimal.
  final int amount;
  final String? category;
  final DateTime spentOn;

  /// Siapa yang menalangi.
  final String? paidByName;

  /// Path foto struk di Supabase Storage (null = belum terunggah / tidak ada).
  final String? receiptPath;

  /// Salinan foto struk di HP ini (hanya ada di HP yang memotretnya).
  final String? receiptLocalPath;
  final String? note;
  final String? createdBy;
  final String createdAt;

  bool get hasReceipt => receiptPath != null || receiptLocalPath != null;
}
