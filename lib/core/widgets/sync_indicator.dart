import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../sync/sync_controller.dart';
import 'common.dart';

/// Ikon status sinkron di AppBar. Ketuk untuk sinkron sekarang.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color, String label) = switch (sync.phase) {
      SyncPhase.syncing => (Icons.sync, scheme.primary, 'Menyinkronkan…'),
      SyncPhase.offline => (
        Icons.cloud_off,
        scheme.outline,
        'Offline — perubahan tersimpan di HP',
      ),
      SyncPhase.error => (
        Icons.sync_problem,
        scheme.error,
        sync.message ?? 'Gagal sinkron',
      ),
      SyncPhase.idle when sync.pending > 0 => (
        Icons.cloud_upload_outlined,
        scheme.tertiary,
        '${sync.pending} perubahan menunggu dikirim',
      ),
      SyncPhase.idle => (
        Icons.cloud_done_outlined,
        scheme.primary,
        'Semua data tersinkron',
      ),
    };

    return IconButton(
      tooltip: label,
      onPressed: () async {
        showSnack(context, label);
        await ref.read(syncControllerProvider.notifier).syncNow();
      },
      icon: Badge(
        isLabelVisible: sync.pending > 0,
        label: Text('${sync.pending}'),
        child: Icon(icon, color: color),
      ),
    );
  }
}
