import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/sync_indicator.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../data/item.dart';
import 'status_badge.dart';

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  String _query = '';
  ItemStatus? _status;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barang'),
        actions: const [SyncIndicator()],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/items/new'),
              icon: const Icon(Icons.add),
              label: const Text('Barang'),
            )
          : null,
      body: AsyncView(
        value: items,
        builder: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Belum ada barang',
              subtitle: isAdmin
                  ? 'Ketuk tombol + Barang untuk mulai mendata.'
                  : 'Koordinator belum mendata barang, atau data belum '
                        'tersinkron.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Cari nama, kategori, atau pembawa',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              _StatusFilter(
                items: all,
                selected: _status,
                onSelected: (s) => setState(() => _status = s),
              ),
              Expanded(child: _ItemList(items: _filter(all))),
            ],
          );
        },
      ),
    );
  }

  List<Item> _filter(List<Item> all) {
    final q = _query.trim().toLowerCase();
    return all.where((i) {
      if (_status != null && i.status != _status) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          i.category.toLowerCase().contains(q) ||
          (i.carrierName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<Item> items;
  final ItemStatus? selected;
  final ValueChanged<ItemStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    int count(ItemStatus s) => items.where((i) => i.status == s).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          FilterChip(
            label: Text('Semua (${items.length})'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final s in ItemStatus.values)
            FilterChip(
              label: Text('${s.label} (${count(s)})'),
              selected: selected == s,
              onSelected: (on) => onSelected(on ? s : null),
            ),
        ],
      ),
    );
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({required this.items});

  final List<Item> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Tidak ada barang yang cocok',
      );
    }
    final onLoan = ref.watch(outstandingByItemProvider).value ?? const {};
    final theme = Theme.of(context);

    // Daftar sudah urut per kategori; sisipkan judul tiap kategori berganti.
    final rows = <Widget>[];
    String? category;
    for (final item in items) {
      if (item.category != category) {
        category = item.category;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              category,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final details = [
        '${item.quantity} ${item.unit}',
        if (item.carrierName != null) 'Pembawa: ${item.carrierName}',
        if ((onLoan[item.id] ?? 0) > 0) '${onLoan[item.id]} sedang dipinjam',
      ];
      rows.add(
        ListTile(
          title: Text(item.name),
          subtitle: Text(details.join(' · ')),
          trailing: StatusBadge(status: item.status),
          onTap: () => context.push('/items/${item.id}'),
        ),
      );
    }
    return ListView(
      // Ruang di bawah agar baris terakhir tidak tertutup tombol tambah.
      padding: const EdgeInsets.only(bottom: 96),
      children: rows,
    );
  }
}
