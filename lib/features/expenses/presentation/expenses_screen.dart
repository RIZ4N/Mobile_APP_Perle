import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sync_indicator.dart';
import '../../data_providers.dart';
import '../data/expense.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengeluaran'),
        actions: const [SyncIndicator()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Pengeluaran'),
      ),
      body: AsyncView(
        value: ref.watch(expensesProvider),
        builder: (expenses) {
          if (expenses.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Belum ada pengeluaran',
              subtitle: 'Catat belanja perlengkapan beserta foto struknya.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _TotalCard(expenses: expenses),
              for (final e in expenses) _ExpenseTile(expense: e),
            ],
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = expenses.fold<int>(0, (sum, e) => sum + e.amount);

    // Subtotal per kategori, terbesar dulu.
    final byCategory = <String, int>{};
    for (final e in expenses) {
      final key = e.category ?? 'Lainnya';
      byCategory[key] = (byCategory[key] ?? 0) + e.amount;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.all(16),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total pengeluaran · ${expenses.length} transaksi',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatRupiah(total),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (categories.length > 1) ...[
              const SizedBox(height: 12),
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.key,
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ),
                      Text(
                        formatRupiah(c.value),
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        expense.hasReceipt ? Icons.receipt_long : Icons.receipt_long_outlined,
        color: expense.hasReceipt
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        semanticLabel: expense.hasReceipt ? 'Ada foto struk' : 'Tanpa struk',
      ),
      title: Text(expense.description),
      subtitle: Text(
        [
          formatDate(expense.spentOn),
          ?expense.category,
          if (expense.paidByName != null) 'oleh ${expense.paidByName}',
        ].join(' · '),
      ),
      trailing: Text(
        formatRupiah(expense.amount),
        style: theme.textTheme.titleSmall,
      ),
      onTap: () => context.push('/expenses/${expense.id}'),
    );
  }
}
