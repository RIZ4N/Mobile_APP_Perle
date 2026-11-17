import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const appLocale = 'id_ID';

final _rupiah = NumberFormat.currency(
  locale: appLocale,
  symbol: 'Rp ',
  decimalDigits: 0,
);
final _thousands = NumberFormat.decimalPattern(appLocale);
final _date = DateFormat('d MMM yyyy', appLocale);
final _dateTime = DateFormat('d MMM yyyy, HH.mm', appLocale);
final _isoDate = DateFormat('yyyy-MM-dd');

String formatRupiah(int amount) => _rupiah.format(amount);

String formatDate(DateTime date) => _date.format(date);

String formatDateTime(DateTime dateTime) =>
    _dateTime.format(dateTime.toLocal());

/// `yyyy-MM-dd` untuk kolom bertipe date.
String toIsoDate(DateTime date) => _isoDate.format(date);

/// Membaca angka dari teks berformat ("25.000" → 25000).
int? parseAmount(String text) {
  final digits = text.replaceAll(RegExp('[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// Menambahkan pemisah ribuan selagi mengetik nominal.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final amount = parseAmount(newValue.text);
    if (amount == null) return const TextEditingValue();
    final text = _thousands.format(amount);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String formatThousands(int amount) => _thousands.format(amount);
