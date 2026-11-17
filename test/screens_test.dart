import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perle/features/expenses/presentation/expense_form_screen.dart';
import 'package:perle/features/expenses/presentation/expenses_screen.dart';
import 'package:perle/features/items/data/item.dart';
import 'package:perle/features/items/presentation/item_detail_screen.dart';
import 'package:perle/features/items/presentation/item_form_screen.dart';
import 'package:perle/features/items/presentation/items_screen.dart';
import 'package:perle/features/loans/presentation/loan_history_screen.dart';
import 'package:perle/features/loans/presentation/loan_sheet.dart';
import 'package:perle/features/packing/presentation/packing_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/app_harness.dart';

/// Gulungan halaman (bukan gulungan di dalam kolom teks).
final pageScroll = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  group('Barang', () {
    testWidgets('daftar menampilkan barang per kategori dengan status', (
      tester,
    ) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ItemsScreen());

      expect(find.text('Kompor portable'), findsOneWidget);
      expect(find.text('Dapur'), findsOneWidget);
      expect(find.text('Semua (4)'), findsOneWidget);
      expect(find.text('Harus beli (1)'), findsOneWidget);
      expect(find.textContaining('2 sedang dipinjam'), findsOneWidget);
      expect(find.text('Barang'), findsNWidgets(2), reason: 'judul + tombol +');

      // Deretan filter bisa digeser mendatar di layar sempit.
      await tester.ensureVisible(find.text('Harus beli (1)'));
      await tester.pump();
      await tester.tap(find.text('Harus beli (1)'));
      await app.settle(tester);
      expect(find.text('Tabung gas 3 kg'), findsOneWidget);
      expect(find.text('Kompor portable'), findsNothing);
    });

    testWidgets('anggota tidak melihat tombol tambah barang', (tester) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ItemsScreen(), userId: memberId);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Kompor portable'), findsOneWidget);
    });

    testWidgets('formulir menyimpan barang baru dan menautkan pembawa', (
      tester,
    ) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ItemFormScreen());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama barang'),
        'Terpal',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tidur'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tambah'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Simpan'),
        200,
        scrollable: pageScroll,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rina'));
      await tester.pump();
      await tester.tap(find.text('Simpan'));
      await app.settle(tester);

      expect(
        find.text('ROOT'),
        findsOneWidget,
        reason: 'kembali setelah simpan',
      );
      final saved = (await tester.runAsync(app.items.all))!
          .singleWhere((i) => i.name == 'Terpal');
      expect(saved.category, 'Tidur');
      expect(saved.quantity, 2);
      expect(saved.status, ItemStatus.ada);
      expect(saved.carrierId, memberId);
      expect(saved.createdBy, adminId);
    });

    testWidgets('detail menampilkan QR, peminjam, dan riwayat', (tester) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ItemDetailScreen(itemId: 'i-tikar'));

      expect(find.text('Tikar'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byTooltip('Ubah'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Riwayat'),
        300,
        scrollable: pageScroll,
      );
      expect(find.text('Pak RT'), findsOneWidget);
      expect(find.text('Pinjam 2 · Pak RT'), findsOneWidget);
    });
  });

  group('Pinjam/kembali', () {
    testWidgets('mencatat pengembalian dari lembar pinjam', (tester) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      final tikar = (await tester.runAsync(() => app.items.byId('i-tikar')))!;
      await app.pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLoanSheet(context, tikar),
                child: const Text('BUKA'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('BUKA'));
      await app.settle(tester);
      expect(
        find.text('Tersedia 3 dari 5 buah · 2 sedang dipinjam'),
        findsOneWidget,
      );

      await tester.tap(find.text('Kembali'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pak RT'));
      await tester.pump();
      // Paling banyak 2 (yang dipegang Pak RT): tombol + mati di angka 2.
      await tester.tap(find.byTooltip('Tambah'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tambah'));
      await tester.pump();
      await tester.tap(find.text('Catat kembali'));
      await app.settle(tester);

      expect(find.textContaining('tercatat'), findsOneWidget);
      expect(await tester.runAsync(app.loans.outstandingByItem), isEmpty);
    });

    testWidgets('riwayat menampilkan siapa memegang apa', (tester) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const LoanHistoryScreen(), userId: memberId);

      expect(find.text('Sedang dipinjam (1)'), findsOneWidget);
      expect(find.text('Pak RT · 2 unit'), findsOneWidget);
      expect(find.byTooltip('Hapus catatan'), findsOneWidget);
    });
  });

  group('Packing', () {
    testWidgets('mencentang barang memperbarui progres dan tersimpan', (
      tester,
    ) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const PackingScreen(), userId: memberId);

      expect(find.text('0 dari 4 barang sudah dikemas'), findsOneWidget);
      expect(find.textContaining('BELUM DIBELI'), findsOneWidget);
      expect(
        find.byTooltip('Kosongkan semua centang'),
        findsNothing,
        reason: 'hanya admin',
      );

      await tester.tap(find.textContaining('Kompor portable'));
      await app.settle(tester);
      expect(find.text('1 dari 4 barang sudah dikemas'), findsOneWidget);

      final rows = (await tester.runAsync(
        () => app.db.query('packing_checks'),
      ))!;
      expect(rows.single['item_id'], 'i-kompor');
      expect(rows.single['is_packed'], 1);
      expect(rows.single['packed_by'], memberId);
      expect(rows.single['dirty'], 1);

      await tester.tap(find.text('Punya saya'));
      await app.settle(tester);
      expect(find.text('0 dari 1 barang sudah dikemas'), findsOneWidget);
      expect(find.textContaining('Tabung gas 3 kg'), findsOneWidget);
    });
  });

  group('Pengeluaran', () {
    testWidgets('total dan rincian per kategori dihitung otomatis', (
      tester,
    ) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ExpensesScreen());

      expect(find.text('Total pengeluaran · 2 transaksi'), findsOneWidget);
      expect(find.text('Rp 135.000'), findsOneWidget);
      expect(find.text('Selang & regulator'), findsOneWidget);
      expect(
        find.text('Rp 85.000'),
        findsNWidgets(2),
        reason: 'kategori + baris',
      );
    });

    testWidgets('formulir menyimpan pengeluaran baru', (tester) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(tester, const ExpenseFormScreen(), userId: memberId);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Keterangan'),
        'Gas 3 kg',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nominal'),
        '22000',
      );
      expect(find.text('22.000'), findsOneWidget, reason: 'pemisah ribuan');
      await tester.scrollUntilVisible(
        find.text('Simpan'),
        200,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('Simpan'));
      await app.settle(tester);

      final saved = (await tester.runAsync(app.expenses.all))!
          .singleWhere((e) => e.description == 'Gas 3 kg');
      expect(saved.amount, 22000);
      expect(saved.paidByName, 'Rina', reason: 'bawaan: pencatat');
      expect(saved.createdBy, memberId);
    });

    testWidgets('anggota hanya bisa melihat pengeluaran milik orang lain', (
      tester,
    ) async {
      final app = await AppHarness.create(tester);
      await app.seed(tester);
      await app.pump(
        tester,
        const ExpenseFormScreen(expenseId: 'e-2'),
        userId: memberId,
      );

      expect(find.text('Detail pengeluaran'), findsOneWidget);
      expect(find.text('Simpan'), findsNothing);
      expect(find.byTooltip('Hapus'), findsNothing);
    });
  });
}
