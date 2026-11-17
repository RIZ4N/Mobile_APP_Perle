import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Di-override di `main()` setelah database dibuka.
final localDbProvider = Provider<Database>(
  (ref) => throw UnimplementedError('localDbProvider belum di-override'),
);

/// Penghitung revisi data lokal. Semua provider daftar `watch` nilai ini, jadi
/// setiap tulis lokal atau hasil pull cukup memanggil [DbRevision.bump] untuk
/// menyegarkan layar.
class DbRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dbRevisionProvider = NotifierProvider<DbRevision, int>(DbRevision.new);
