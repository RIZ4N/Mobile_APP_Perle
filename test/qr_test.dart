import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perle/features/items/data/item.dart';
import 'package:perle/features/qr/qr_codec.dart';
import 'package:perle/features/qr/qr_labels.dart';

void main() {
  test('isi QR bolak-balik ke id barang', () {
    const id = '3f2b8c1e-0d4a-4a7e-9b1c-5e6f7a8b9c0d';
    expect(decodeItemQr(encodeItemQr(id)), id);
    expect(decodeItemQr('  ${encodeItemQr(id)}\n'), id);
  });

  test('QR yang bukan label Perle ditolak', () {
    expect(decodeItemQr('https://example.com'), isNull);
    expect(decodeItemQr('PERLE-ITEM:'), isNull);
    expect(decodeItemQr(''), isNull);
  });

  test('lembar label QR memuat semua barang di beberapa halaman', () async {
    final items = [
      for (var i = 0; i < 40; i++)
        Item(
          id: 'id-$i',
          name: 'Barang nomor $i dengan nama yang agak panjang',
          category: 'Dapur',
          quantity: 1,
          unit: 'buah',
          status: ItemStatus.ada,
          createdAt: DateTime.utc(2027).toIso8601String(),
        ),
    ];
    final bytes = await buildQrLabelsPdf(items);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');

    // 3 kolom × 4 baris per halaman A4 → 40 label = 4 halaman.
    final pages = RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes));
    expect(pages.length, 4);

    // Nama dengan emoji/aksara lain tidak boleh menggagalkan lembar label.
    final odd = await buildQrLabelsPdf([
      Item(
        id: 'x',
        name: 'Kompor 🔥 – “besar”',
        category: 'Dapur',
        quantity: 1,
        unit: 'buah',
        status: ItemStatus.ada,
        createdAt: DateTime.utc(2027).toIso8601String(),
      ),
    ]);
    expect(odd, isNotEmpty);

    final out = Platform.environment['PERLE_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
