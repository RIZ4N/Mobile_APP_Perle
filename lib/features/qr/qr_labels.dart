import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../items/data/item.dart';
import 'qr_codec.dart';

/// Lembar label QR ukuran A4, tiga label per baris, siap dicetak lalu
/// digunting dan ditempel di barang.
Future<Uint8List> buildQrLabelsPdf(List<Item> items) {
  const margin = 12 * PdfPageFormat.mm;
  const columns = 3;
  final labelWidth = (PdfPageFormat.a4.width - 2 * margin) / columns;
  const labelHeight = 62 * PdfPageFormat.mm;

  final doc = pw.Document(title: 'Label QR Perle KKN');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (context) => [
        pw.Wrap(
          children: [
            for (final item in items)
              pw.Container(
                width: labelWidth,
                height: labelHeight,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.grey400,
                    width: 0.5,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: encodeItemQr(item.id),
                      width: 36 * PdfPageFormat.mm,
                      height: 36 * PdfPageFormat.mm,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _printable(item.name),
                      maxLines: 2,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _printable(item.category),
                      maxLines: 1,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Font bawaan PDF hanya mengenal Latin-1; karakter lain (emoji, dsb.) diganti
/// agar pembuatan lembar label tidak gagal gara-gara satu nama barang.
String _printable(String text) =>
    String.fromCharCodes(text.runes.map((r) => r <= 0xFF ? r : 0x3F /* ? */));

/// Membuka dialog cetak/simpan PDF bawaan Android.
Future<void> printQrLabels(List<Item> items) async {
  final bytes = await buildQrLabelsPdf(items);
  await Printing.layoutPdf(
    name: 'Label QR Perle KKN',
    onLayout: (_) async => bytes,
  );
}
