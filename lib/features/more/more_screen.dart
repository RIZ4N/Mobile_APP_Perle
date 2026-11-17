import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/db/db_providers.dart';
import '../../core/sync/sync_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_providers.dart';
import '../auth/data/auth_repository.dart';
import '../data_providers.dart';
import '../qr/qr_labels.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final sync = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Text(
                (profile?.fullName.isNotEmpty ?? false)
                    ? profile!.fullName[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(profile?.fullName ?? 'Memuat profil…'),
            subtitle: Text(
              profile == null
                  ? 'Menunggu sinkronisasi pertama'
                  : profile.isAdmin
                  ? 'Admin (koordinator)'
                  : 'Anggota',
            ),
            trailing: profile == null
                ? null
                : IconButton(
                    tooltip: 'Ubah nama',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editName(context, ref, profile.fullName),
                  ),
          ),
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sinkronisasi', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(switch (sync.phase) {
                    SyncPhase.syncing => 'Sedang menyinkronkan…',
                    SyncPhase.offline =>
                      'Offline. Perubahan tersimpan di HP dan dikirim otomatis '
                          'saat ada internet.',
                    SyncPhase.error => sync.message ?? 'Gagal sinkron.',
                    SyncPhase.idle when sync.pending > 0 =>
                      '${sync.pending} perubahan menunggu dikirim.',
                    SyncPhase.idle => 'Semua data tersinkron.',
                  }),
                  if (sync.lastSyncedAt != null)
                    Text(
                      'Terakhir: ${formatDateTime(sync.lastSyncedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: sync.phase == SyncPhase.syncing
                        ? null
                        : ref.read(syncControllerProvider.notifier).syncNow,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sinkronkan sekarang'),
                  ),
                  if (sync.failed > 0)
                    TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Buang perubahan yang ditolak?',
                          message:
                              '${sync.failed} perubahan di HP ini ditolak '
                              'server (biasanya karena tidak punya hak ubah). '
                              'Perubahan itu akan dibuang dan data server '
                              'dipakai kembali.',
                          confirmLabel: 'Buang',
                        );
                        if (ok) {
                          await ref
                              .read(syncControllerProvider.notifier)
                              .discardFailed();
                        }
                      },
                      child: const Text('Buang perubahan yang ditolak'),
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Anggota kelompok'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/more/members'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Pinjam & kembali'),
            subtitle: const Text('Siapa memegang apa, dan riwayatnya'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/more/loans'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Cetak label QR semua barang'),
            subtitle: const Text('Lembar A4 untuk dicetak dan ditempel'),
            onTap: () async {
              final items = await ref.read(itemsProvider.future);
              if (!context.mounted) return;
              if (items.isEmpty) {
                showSnack(context, 'Belum ada barang untuk dicetak.');
                return;
              }
              await printQrLabels(items);
            },
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Keluar',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah nama'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama lengkap'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current) return;
    try {
      await ref.read(authRepositoryProvider).updateOwnName(name);
      await ref.read(syncControllerProvider.notifier).syncNow();
    } on AuthFailure catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Coba kirim dulu perubahan yang tertunda sebelum data lokal dihapus.
    final controller = ref.read(syncControllerProvider.notifier);
    await controller.syncNow();
    final pending = await ref.read(syncEngineProvider).pendingCount();
    if (!context.mounted) return;

    final ok = await confirmDialog(
      context,
      title: 'Keluar dari akun?',
      message: pending > 0
          ? '$pending perubahan di HP ini BELUM terkirim ke server dan akan '
                'hilang bila Anda keluar sekarang. Sambungkan internet dan '
                'sinkronkan dulu bila ingin menyimpannya.'
          : 'Data di HP ini akan dihapus. Data di server tetap aman.',
      confirmLabel: pending > 0 ? 'Keluar & buang' : 'Keluar',
    );
    if (!ok) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.read(dbRevisionProvider.notifier).bump();
  }
}
