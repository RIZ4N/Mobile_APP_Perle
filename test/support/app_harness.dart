import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perle/core/db/db_providers.dart';
import 'package:perle/core/db/local_db.dart';
import 'package:perle/core/sync/sync_controller.dart';
import 'package:perle/core/theme/app_theme.dart';
import 'package:perle/core/utils/formatters.dart';
import 'package:perle/features/auth/auth_providers.dart';
import 'package:perle/features/expenses/data/expense.dart';
import 'package:perle/features/expenses/data/expense_repository.dart';
import 'package:perle/features/items/data/item.dart';
import 'package:perle/features/items/data/item_repository.dart';
import 'package:perle/features/loans/data/loan_log.dart';
import 'package:perle/features/loans/data/loan_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const adminId = 'u-admin';
const memberId = 'u-rina';

/// Pengendali sinkron tiruan: tidak menyentuh jaringan maupun plugin.
class FakeSyncController extends SyncController {
  int scheduled = 0;

  @override
  SyncState build() => const SyncState();

  @override
  void schedule() => scheduled++;

  @override
  Future<void> syncNow() async {}
}

/// Lingkungan uji layar: SQLite di memori berisi data contoh, tanpa Supabase.
class AppHarness {
  AppHarness._(this.db);

  final Database db;
  late final items = ItemRepository(db, () {});
  late final loans = LoanRepository(db, () {});
  late final expenses = ExpenseRepository(db, () {});

  static Future<AppHarness> create(WidgetTester tester) async {
    await initializeDateFormatting(appLocale);
    // Layar HP kecil (360 × 740 dp) — ukuran yang paling rawan overflow.
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Tanpa isolate agar kueri selesai di dalam zona waktu-palsu uji widget.
    final db = (await tester.runAsync(
      () => databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: localDbVersion,
          onCreate: createLocalSchema,
          singleInstance: false,
        ),
      ),
    ))!;
    addTearDown(db.close);
    return AppHarness._(db);
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final now = DateTime.utc(2027).toIso8601String();
      for (final (id, name, role) in [
        (adminId, 'Budi Koordinator', 'admin'),
        (memberId, 'Rina', 'anggota'),
      ]) {
        await db.insert('profiles', {
          'id': id,
          'full_name': name,
          'role': role,
          'created_at': now,
          'updated_at': now,
        });
      }

      Item item(
        String id,
        String name,
        String category,
        int qty,
        ItemStatus status, {
        String? source,
        String? carrierId,
        String? carrierName,
      }) => Item(
        id: id,
        name: name,
        category: category,
        quantity: qty,
        unit: 'buah',
        status: status,
        source: source,
        carrierId: carrierId,
        carrierName: carrierName,
        createdBy: adminId,
        createdAt: now,
      );

      await items.save(
        item(
          'i-kompor',
          'Kompor portable',
          'Dapur',
          2,
          ItemStatus.ada,
          source: 'Milik Budi',
          carrierId: adminId,
          carrierName: 'Budi Koordinator',
        ),
      );
      await items.save(
        item(
          'i-gas',
          'Tabung gas 3 kg',
          'Dapur',
          1,
          ItemStatus.harusBeli,
          carrierId: memberId,
          carrierName: 'Rina',
        ),
      );
      await items.save(
        item(
          'i-sound',
          'Sound system',
          'Elektronik',
          1,
          ItemStatus.pinjam,
          source: 'Sekretariat BEM',
          carrierName: 'Dimas',
        ),
      );
      await items.save(
        item('i-tikar', 'Tikar', 'Tidur', 5, ItemStatus.ada, source: 'Posko'),
      );

      await loans.record(
        itemId: 'i-tikar',
        action: LoanAction.pinjam,
        quantity: 2,
        personName: 'Pak RT',
        recordedBy: memberId,
      );

      await expenses.save(
        Expense(
          id: 'e-1',
          description: 'Selang & regulator',
          amount: 85000,
          category: 'Perlengkapan',
          spentOn: DateTime(2027, 1, 4),
          paidByName: 'Rina',
          createdBy: memberId,
          createdAt: now,
        ),
      );
      await expenses.save(
        Expense(
          id: 'e-2',
          description: 'Bensin angkut barang',
          amount: 50000,
          category: 'Transportasi',
          spentOn: DateTime(2027, 1, 5),
          paidByName: 'Budi Koordinator',
          createdBy: adminId,
          createdAt: now,
        ),
      );
    });
  }

  /// Menampilkan [screen] sebagai [userId]. Layar dipasang sebagai sub-rute
  /// agar `context.pop()` punya tujuan; rute lain yang dituju `context.push`
  /// diarahkan ke halaman penanda.
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    String userId = adminId,
    Brightness brightness = Brightness.light,
  }) async {
    final router = GoRouter(
      initialLocation: '/screen',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('ROOT')),
          routes: [GoRoute(path: 'screen', builder: (_, _) => screen)],
        ),
      ],
      errorBuilder: (_, state) =>
          Scaffold(body: Text('ROUTE ${state.uri.path}')),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue(userId),
          syncControllerProvider.overrideWith(FakeSyncController.new),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(brightness),
          locale: const Locale('id'),
          supportedLocales: const [Locale('id')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
  }

  /// Memberi kesempatan kueri SQLite selesai, lalu menggambar ulang.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}
