/// Isi QR label barang: `PERLE-ITEM:<id barang>`. Awalan dipakai untuk
/// membedakan label Perle dari QR lain yang kebetulan terpindai.
const _prefix = 'PERLE-ITEM:';

String encodeItemQr(String itemId) => '$_prefix$itemId';

/// Mengembalikan id barang, atau null bila [raw] bukan label Perle.
String? decodeItemQr(String raw) {
  final value = raw.trim();
  if (!value.startsWith(_prefix)) return null;
  final id = value.substring(_prefix.length);
  return id.isEmpty ? null : id;
}
