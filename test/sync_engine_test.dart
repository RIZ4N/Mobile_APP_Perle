import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perle/core/sync/sync_engine.dart';
import 'package:perle/features/expenses/data/expense.dart';
import 'package:perle/features/expenses/data/expense_repository.dart';
import 'package:perle/features/items/data/item.dart';
import 'package:perle/features/items/data/item_repository.dart';
import 'package:perle/features/packing/data/packing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

Item _item(String id, String name, {int quantity = 1}) => Item(
  id: id,
  name: name,
  category: 'Dapur',
  quantity: quantity,
  unit: 'buah',
  status: ItemStatus.ada,
  createdAt: DateTime.utc(2027).toIso8601String(),
);

/// Satu "HP": database lokal + mesin sinkron ke server yang sama.
class _Device {
  _Device(this.db, FakeRemote remote, {int pageSize = 500})
    : engine = SyncEngine(db: db, remote: remote, pageSize: pageSize),
      items = ItemRepository(db, () {}),
      packing = PackingRepository(db, () {}),
      expenses = ExpenseRepository(db, () {});

  final Database db;
  final SyncEngine engine;
  final ItemRepository items;
  final PackingRepository packing;
  final ExpenseRepository expenses;

  static Future<_Device> open(FakeRemote remote, {int pageSize = 500}) async =>
      _Device(await openTestDb(), remote, pageSize: pageSize);
}

void main() {
  late FakeRemote remote;
  late _Device hpA;
  late _Device hpB;

  setUp(() async {
    remote = FakeRemote();
    hpA = await _Device.open(remote);
    hpB = await _Device.open(remote);
  });

  tearDown(() async {
    await hpA.db.close();
    await hpB.db.close();
  });

  test(
    'barang yang dibuat offline terkirim saat online dan muncul di HP lain',
    () async {
      remote.offline = true;
      await hpA.items.save(_item('i1', 'Kompor'));
      await hpA.items.save(_item('i2', 'Wajan'));

      await expectLater(hpA.engine.sync(), throwsA(isA<SocketException>()));
      expect(await hpA.engine.pendingCount(), 2);
      expect(
        (await hpA.items.all()).length,
        2,
        reason: 'tetap bisa dibaca offline',
      );

      remote.offline = false;
      final result = await hpA.engine.sync();
      expect(result.pushed, 2);
      expect(await hpA.engine.pendingCount(), 0);

      await hpB.engine.sync();
      expect((await hpB.items.all()).map((i) => i.name), ['Kompor', 'Wajan']);
    },
  );

  test(
    'sinkron ulang tanpa perubahan tidak mengirim atau mengubah apa pun',
    () async {
      await hpA.items.save(_item('i1', 'Kompor'));
      await hpA.engine.sync();
      final calls = remote.upsertCalls;

      final again = await hpA.engine.sync();
      expect(again.pushed, 0);
      expect(again.pulled, 0);
      expect(remote.upsertCalls, calls);
    },
  );

  test('hapus (soft delete) ikut tersinkron ke HP lain', () async {
    await hpA.items.save(_item('i1', 'Kompor'));
    await hpA.engine.sync();
    await hpB.engine.sync();
    expect(await hpB.items.all(), hasLength(1));

    await hpA.items.delete('i1');
    await hpA.engine.sync();
    await hpB.engine.sync();
    expect(await hpB.items.all(), isEmpty);
    expect(remote.row('items', 'i1')!['deleted_at'], isNotNull);
  });

  test(
    'perubahan lokal yang belum terkirim tidak ditimpa pull, lalu menang',
    () async {
      await hpA.items.save(_item('i1', 'Kompor', quantity: 1));
      await hpA.engine.sync();
      await hpB.engine.sync();

      // B mengubah saat offline, sementara A mengubah dan sudah terkirim.
      await hpB.items.save(_item('i1', 'Kompor', quantity: 5));
      await hpA.items.save(_item('i1', 'Kompor', quantity: 2));
      await hpA.engine.sync();

      await hpB.engine.sync();
      expect((await hpB.items.byId('i1'))!.quantity, 5);
      expect(remote.row('items', 'i1')!['quantity'], 5);

      await hpA.engine.sync();
      expect((await hpA.items.byId('i1'))!.quantity, 5);
    },
  );

  test('baris yang ditolak server tidak menghalangi baris lain', () async {
    await hpA.items.save(_item('ok', 'Kompor'));
    await hpA.items.save(_item('bad', 'Terlarang'));
    remote.reject = (table, row) => row['id'] == 'bad';

    final result = await hpA.engine.sync();
    expect(result.pushed, 1);
    expect(result.failed, 1);
    expect(remote.row('items', 'ok'), isNotNull);
    expect(remote.row('items', 'bad'), isNull);
    expect(await hpA.engine.failedCount(), 1);
    expect(await hpA.engine.pendingCount(), 1);

    // Setelah penyebab penolakan hilang, baris terkirim pada putaran berikut.
    remote.reject = null;
    await hpA.engine.sync();
    expect(remote.row('items', 'bad'), isNotNull);
    expect(await hpA.engine.failedCount(), 0);
  });

  test(
    'discardFailed membuang perubahan yang ditolak dan memulihkan versi server',
    () async {
      await hpA.items.save(_item('i1', 'Kompor', quantity: 1));
      await hpA.engine.sync();

      await hpA.items.save(_item('i1', 'Kompor', quantity: 99));
      remote.reject = (table, row) => true;
      await hpA.engine.sync();
      expect(await hpA.engine.failedCount(), 1);

      await hpA.engine.discardFailed();
      await hpA.engine.sync();
      expect(await hpA.engine.failedCount(), 0);
      expect((await hpA.items.byId('i1'))!.quantity, 1);
    },
  );

  test(
    'centang packing tersinkron sebagai boolean dan bisa di-reset',
    () async {
      await hpA.items.save(_item('i1', 'Kompor'));
      await hpA.packing.setPacked('i1', packed: true, userId: 'u1');
      await hpA.engine.sync();
      expect(remote.row('packing_checks', 'i1')!['is_packed'], isTrue);

      await hpB.engine.sync();
      expect((await hpB.packing.packed()).keys, ['i1']);
      expect((await hpB.packing.packed())['i1']!.packedBy, 'u1');

      await hpB.packing.resetAll();
      await hpB.engine.sync();
      await hpA.engine.sync();
      expect(await hpA.packing.packed(), isEmpty);
    },
  );

  test('pull berhalaman mengambil semua baris', () async {
    for (var i = 0; i < 7; i++) {
      remote.serverWrite('items', {
        ..._item('i$i', 'Barang $i').toMap(),
        'deleted_at': null,
      });
    }
    final hp = await _Device.open(remote, pageSize: 3);
    addTearDown(hp.db.close);

    final result = await hp.engine.sync();
    expect(result.pulled, 7);
    expect(await hp.items.all(), hasLength(7));
  });

  test(
    'foto struk diunggah saat online, lalu path-nya ikut tersinkron',
    () async {
      final dir = await Directory.systemTemp.createTemp('perle_test');
      addTearDown(() => dir.delete(recursive: true));
      final photo = File('${dir.path}/struk.jpg')..writeAsBytesSync([1, 2, 3]);

      await hpA.expenses.save(
        Expense(
          id: 'e1',
          description: 'Gas 3 kg',
          amount: 22000,
          spentOn: DateTime(2027, 1, 6),
          receiptLocalPath: photo.path,
          createdAt: DateTime.utc(2027).toIso8601String(),
        ),
      );

      remote.offline = true;
      await expectLater(hpA.engine.sync(), throwsA(isA<SocketException>()));
      expect(remote.uploads, isEmpty);

      remote.offline = false;
      await hpA.engine.sync();
      expect(remote.uploads, ['e1/1.jpg']);
      expect(remote.row('expenses', 'e1')!['receipt_path'], 'e1/1.jpg');
      expect(
        remote.row('expenses', 'e1')!.containsKey('receipt_local_path'),
        isFalse,
        reason: 'path lokal tidak boleh terkirim ke server',
      );

      // Tidak diunggah dua kali.
      await hpA.engine.sync();
      expect(remote.uploads, hasLength(1));

      // HP lain menerima path server; HP asal tetap menyimpan salinan lokal.
      await hpB.engine.sync();
      final onB = (await hpB.expenses.byId('e1'))!;
      expect(onB.receiptPath, 'e1/1.jpg');
      expect(onB.receiptLocalPath, isNull);
      expect(onB.spentOn, DateTime(2027, 1, 6));
      expect((await hpA.expenses.byId('e1'))!.receiptLocalPath, photo.path);
    },
  );
}
