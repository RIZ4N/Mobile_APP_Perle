import 'package:flutter_test/flutter_test.dart';
import 'package:perle/features/items/data/item.dart';
import 'package:perle/features/items/data/item_repository.dart';
import 'package:perle/features/loans/data/loan_log.dart';
import 'package:perle/features/loans/data/loan_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

void main() {
  late Database db;
  late LoanRepository loans;
  var writes = 0;

  setUp(() async {
    db = await openTestDb();
    writes = 0;
    loans = LoanRepository(db, () => writes++);
    final items = ItemRepository(db, () {});
    for (final (id, name) in [('i1', 'Sound system'), ('i2', 'Tikar')]) {
      await items.save(
        Item(
          id: id,
          name: name,
          category: 'Lainnya',
          quantity: 5,
          unit: 'buah',
          status: ItemStatus.ada,
          createdAt: DateTime.utc(2027).toIso8601String(),
        ),
      );
    }
  });

  tearDown(() => db.close());

  Future<void> record(
    String itemId,
    LoanAction action,
    int qty,
    String person,
  ) => loans.record(
    itemId: itemId,
    action: action,
    quantity: qty,
    personName: person,
    recordedBy: 'u1',
  );

  test('jumlah dipinjam = pinjam − kembali, per barang', () async {
    await record('i1', LoanAction.pinjam, 3, 'Pak RT');
    await record('i1', LoanAction.kembali, 1, 'Pak RT');
    await record('i2', LoanAction.pinjam, 2, 'Bu Kades');
    await record('i2', LoanAction.kembali, 2, 'Bu Kades');

    expect(await loans.outstandingByItem(), {'i1': 2});
    expect(writes, 4);
  });

  test(
    'peminjam digabung tanpa membedakan huruf besar/kecil dan spasi',
    () async {
      await record('i1', LoanAction.pinjam, 2, 'Pak RT');
      await record('i1', LoanAction.pinjam, 1, ' pak rt ');
      await record('i1', LoanAction.pinjam, 1, 'Karang Taruna');
      await record('i1', LoanAction.kembali, 1, 'PAK RT');

      final holders = await loans.outstanding(itemId: 'i1');
      expect(
        {for (final h in holders) h.personName.toLowerCase(): h.quantity},
        {'karang taruna': 1, 'pak rt': 2},
      );
      expect(holders.first.itemName, 'Sound system');
    },
  );

  test(
    'log yang dihapus tidak dihitung dan riwayat urut terbaru dulu',
    () async {
      await record('i1', LoanAction.pinjam, 2, 'Pak RT');
      await record('i1', LoanAction.pinjam, 1, 'Bu Kades');
      final logs = await loans.logs(itemId: 'i1');
      expect(logs.map((l) => l.personName), ['Bu Kades', 'Pak RT']);
      expect(logs.first.itemName, 'Sound system');

      await loans.delete(logs.first.id);
      expect(await loans.outstandingByItem(), {'i1': 2});
      expect(await loans.logs(), hasLength(1));
    },
  );
}
