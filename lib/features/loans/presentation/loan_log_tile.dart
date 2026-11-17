import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_providers.dart';
import '../../data_providers.dart';
import '../data/loan_log.dart';

/// Satu baris riwayat pinjam/kembali. Pencatatnya (atau admin) bisa
/// menghapus catatan yang keliru.
class LoanLogTile extends ConsumerWidget {
  const LoanLogTile({super.key, required this.log, this.showItemName = false});

  final LoanLog log;
  final bool showItemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isLoan = log.action == LoanAction.pinjam;
    final canDelete =
        ref.watch(isAdminProvider) ||
        log.recordedBy == ref.watch(currentUserIdProvider);

    final headline = '${log.action.label} ${log.quantity} · ${log.personName}';
    return ListTile(
      leading: Icon(
        isLoan ? Icons.north_east : Icons.south_west,
        color: isLoan ? scheme.tertiary : scheme.primary,
      ),
      title: Text(
        showItemName ? (log.itemName ?? 'Barang terhapus') : headline,
      ),
      subtitle: Text(
        [
          if (showItemName) headline,
          formatDateTime(log.occurredAt),
          if (log.note != null) log.note!,
        ].join('\n'),
      ),
      isThreeLine: showItemName,
      trailing: canDelete
          ? IconButton(
              tooltip: 'Hapus catatan',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Hapus catatan ini?',
                  message:
                      'Jumlah yang sedang dipinjam akan dihitung ulang tanpa '
                      'catatan ini.',
                );
                if (ok) await ref.read(loanRepositoryProvider).delete(log.id);
              },
            )
          : null,
    );
  }
}
