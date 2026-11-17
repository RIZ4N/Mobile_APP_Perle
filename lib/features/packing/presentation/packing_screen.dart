import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/sync_indicator.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../../items/data/item.dart';

enum _Filter { all, mine, unpacked }

/// Checklist packing sebelum berangkat: centang barang yang sudah dikemas.
class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key});

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(itemsProvider);
    final packed = ref.watch(packedProvider).value ?? const {};
    final me = ref.watch(currentProfileProvider).value;
    final isAdmin = ref.watch(isAdminProvider);

    bool isMine(Item i) =>
        me != null &&
        (i.carrierId == me.id ||
            i.carrierName?.toLowerCase() == me.fullName.toLowerCase());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist packing'),
        actions: [
          const SyncIndicator(),
          if (isAdmin)
            IconButton(
              tooltip: 'Kosongkan semua centang',
              icon: const Icon(Icons.restart_alt),
              onPressed: packed.isEmpty
                  ? null
                  : () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Kosongkan semua centang?',
                        message:
                            'Checklist semua anggota kembali kosong, mis. '
                            'untuk packing pulang.',
                        confirmLabel: 'Kosongkan',
                      );
                      if (ok) {
                        await ref.read(packingRepositoryProvider).resetAll();
                      }
                    },
            ),
        ],
      ),
      body: AsyncView(
        value: items,
        builder: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.checklist,
              title: 'Belum ada barang untuk dikemas',
              subtitle: 'Checklist terisi otomatis dari daftar barang.',
            );
          }
          final scope = _filter == _Filter.mine
              ? all.where(isMine).toList()
              : all;
          final done = scope.where((i) => packed.containsKey(i.id)).length;
          final shown = _filter == _Filter.unpacked
              ? scope.where((i) => !packed.containsKey(i.id)).toList()
              : scope;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$done dari ${scope.length} barang sudah dikemas',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: scope.isEmpty ? 0 : done / scope.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<_Filter>(
                      segments: const [
                        ButtonSegment(value: _Filter.all, label: Text('Semua')),
                        ButtonSegment(
                          value: _Filter.mine,
                          label: Text('Punya saya'),
                        ),
                        ButtonSegment(
                          value: _Filter.unpacked,
                          label: Text('Belum'),
                        ),
                      ],
                      selected: {_filter},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _filter = s.first),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: _filter == _Filter.unpacked
                            ? Icons.task_alt
                            : Icons.person_search_outlined,
                        title: switch (_filter) {
                          _Filter.unpacked => 'Semua sudah dikemas',
                          _Filter.mine => 'Tidak ada barang atas nama Anda',
                          _Filter.all => 'Tidak ada barang',
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final item = shown[index];
                          final isPacked = packed.containsKey(item.id);
                          final notBought = item.status == ItemStatus.harusBeli;
                          return CheckboxListTile(
                            value: isPacked,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              '${item.name} · ${item.quantity} ${item.unit}',
                              style: isPacked
                                  ? TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: theme.colorScheme.outline,
                                    )
                                  : null,
                            ),
                            subtitle: Text(
                              [
                                item.category,
                                if (item.carrierName != null)
                                  'Pembawa: ${item.carrierName}',
                                if (notBought) 'BELUM DIBELI',
                              ].join(' · '),
                              style: notBought && !isPacked
                                  ? TextStyle(color: theme.colorScheme.error)
                                  : null,
                            ),
                            onChanged: (v) => ref
                                .read(packingRepositoryProvider)
                                .setPacked(
                                  item.id,
                                  packed: v ?? false,
                                  userId: me?.id,
                                ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
