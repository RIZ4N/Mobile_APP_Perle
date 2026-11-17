import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../data_providers.dart';
import 'loan_log_tile.dart';

/// Ringkasan "siapa memegang apa" dan riwayat pinjam/kembali semua barang.
class LoanHistoryScreen extends ConsumerWidget {
  const LoanHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final holders = ref.watch(outstandingProvider(null)).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Pinjam & kembali')),
      body: AsyncView(
        value: ref.watch(loanLogsProvider(null)),
        builder: (logs) {
          if (logs.isEmpty) {
            return const EmptyState(
              icon: Icons.qr_code_scanner,
              title: 'Belum ada catatan',
              subtitle:
                  'Scan label QR barang untuk mencatat pinjam atau kembali.',
            );
          }
          return ListView(
            children: [
              _SectionTitle('Sedang dipinjam (${holders.length})'),
              if (holders.isEmpty)
                const ListTile(title: Text('Semua barang sudah kembali.')),
              for (final h in holders)
                ListTile(
                  leading: Icon(
                    Icons.pending_actions,
                    color: theme.colorScheme.tertiary,
                  ),
                  title: Text(h.itemName ?? 'Barang terhapus'),
                  subtitle: Text('${h.personName} · ${h.quantity} unit'),
                  onTap: () => context.push('/items/${h.itemId}'),
                ),
              const Divider(),
              const _SectionTitle('Riwayat'),
              for (final log in logs) LoanLogTile(log: log, showItemName: true),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
