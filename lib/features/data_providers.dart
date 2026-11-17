import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/db_providers.dart';
import '../core/sync/remote_store.dart';
import '../core/sync/sync_controller.dart';
import 'expenses/data/expense.dart';
import 'expenses/data/expense_repository.dart';
import 'items/data/item.dart';
import 'items/data/item_repository.dart';
import 'loans/data/loan_log.dart';
import 'loans/data/loan_repository.dart';
import 'packing/data/packing_repository.dart';

// Repository (semuanya membaca/menulis SQLite lokal).

final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepository(
    ref.watch(localDbProvider),
    ref.watch(onLocalWriteProvider),
  ),
);

final packingRepositoryProvider = Provider<PackingRepository>(
  (ref) => PackingRepository(
    ref.watch(localDbProvider),
    ref.watch(onLocalWriteProvider),
  ),
);

final loanRepositoryProvider = Provider<LoanRepository>(
  (ref) => LoanRepository(
    ref.watch(localDbProvider),
    ref.watch(onLocalWriteProvider),
  ),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(
    ref.watch(localDbProvider),
    ref.watch(onLocalWriteProvider),
  ),
);

// Data untuk layar. Semuanya `watch` dbRevisionProvider sehingga otomatis
// dimuat ulang setelah tulis lokal maupun pull dari server.

final itemsProvider = FutureProvider<List<Item>>((ref) {
  ref.watch(dbRevisionProvider);
  return ref.watch(itemRepositoryProvider).all();
});

final itemProvider = FutureProvider.family<Item?, String>((ref, id) {
  ref.watch(dbRevisionProvider);
  return ref.watch(itemRepositoryProvider).byId(id);
});

final packedProvider = FutureProvider<Map<String, PackingCheck>>((ref) {
  ref.watch(dbRevisionProvider);
  return ref.watch(packingRepositoryProvider).packed();
});

final outstandingByItemProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(dbRevisionProvider);
  return ref.watch(loanRepositoryProvider).outstandingByItem();
});

/// Siapa memegang apa; argumen null = semua barang.
final outstandingProvider = FutureProvider.family<List<Outstanding>, String?>((
  ref,
  itemId,
) {
  ref.watch(dbRevisionProvider);
  return ref.watch(loanRepositoryProvider).outstanding(itemId: itemId);
});

/// Riwayat pinjam/kembali; argumen null = semua barang.
final loanLogsProvider = FutureProvider.family<List<LoanLog>, String?>((
  ref,
  itemId,
) {
  ref.watch(dbRevisionProvider);
  return ref.watch(loanRepositoryProvider).logs(itemId: itemId);
});

final expensesProvider = FutureProvider<List<Expense>>((ref) {
  ref.watch(dbRevisionProvider);
  return ref.watch(expenseRepositoryProvider).all();
});

final expenseProvider = FutureProvider.family<Expense?, String>((ref, id) {
  ref.watch(dbRevisionProvider);
  return ref.watch(expenseRepositoryProvider).byId(id);
});

/// URL sementara untuk foto struk yang hanya ada di server.
final receiptUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref
      .watch(supabaseProvider)
      .storage
      .from(receiptsBucket)
      .createSignedUrl(path, 3600);
});
