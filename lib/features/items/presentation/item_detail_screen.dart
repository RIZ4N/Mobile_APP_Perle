import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/widgets/common.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../../loans/presentation/loan_log_tile.dart';
import '../../loans/presentation/loan_sheet.dart';
import '../../qr/qr_codec.dart';
import '../../qr/qr_labels.dart';
import '../data/item.dart';
import 'status_badge.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(itemId));
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail barang'),
        actions: [
          if (isAdmin && item.value != null) ...[
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/items/$itemId/edit'),
            ),
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Hapus barang ini?',
                  message:
                      '"${item.value!.name}" akan hilang dari daftar dan '
                      'checklist semua anggota.',
                );
                if (!ok) return;
                await ref.read(itemRepositoryProvider).delete(itemId);
                if (context.mounted) context.pop();
              },
            ),
          ],
        ],
      ),
      body: AsyncView(
        value: item,
        builder: (item) => item == null
            ? const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Barang tidak ditemukan',
                subtitle: 'Mungkin sudah dihapus.',
              )
            : _ItemBody(item: item),
      ),
    );
  }
}

class _ItemBody extends ConsumerWidget {
  const _ItemBody({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final holders = ref.watch(outstandingProvider(item.id)).value ?? const [];
    final logs = ref.watch(loanLogsProvider(item.id)).value ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(item.name, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(width: 12),
            StatusBadge(status: item.status),
          ],
        ),
        const SizedBox(height: 12),
        _InfoRow('Kategori', item.category),
        _InfoRow('Jumlah', '${item.quantity} ${item.unit}'),
        _InfoRow(switch (item.status) {
          ItemStatus.ada => 'Milik',
          ItemStatus.pinjam => 'Dipinjam dari',
          ItemStatus.harusBeli => 'Rencana beli di',
        }, item.source),
        _InfoRow('Pembawa', item.carrierName),
        _InfoRow('Catatan', item.notes),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showLoanSheet(context, item),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Catat pinjam / kembali'),
        ),
        const SizedBox(height: 24),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Latar putih agar QR tetap terbaca di tema gelap.
                QrImageView(
                  data: encodeItemQr(item.id),
                  size: 180,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'Kode QR ${item.name}',
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => printQrLabels([item]),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Cetak / simpan label QR'),
                ),
              ],
            ),
          ),
        ),
        if (holders.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Sedang dipinjam', style: theme.textTheme.titleMedium),
          for (final h in holders)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(h.personName),
              trailing: Text(
                '${h.quantity} ${item.unit}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('Riwayat', style: theme.textTheme.titleMedium),
        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Belum ada catatan pinjam/kembali.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final log in logs) LoanLogTile(log: log),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value!, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
