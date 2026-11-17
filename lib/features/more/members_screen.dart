import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/sync/sync_controller.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_providers.dart';
import '../auth/data/auth_repository.dart';
import '../auth/data/profile.dart';

/// Kode kelompok hanya bisa dibaca admin, dan hanya saat online.
final _joinCodeProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).fetchJoinCode(),
);

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final myId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Anggota kelompok')),
      body: AsyncView(
        value: ref.watch(membersProvider),
        builder: (members) => ListView(
          children: [
            if (isAdmin) const _JoinCodeCard(),
            for (final m in members)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    m.fullName.isEmpty ? '?' : m.fullName[0].toUpperCase(),
                  ),
                ),
                title: Text(m.id == myId ? '${m.fullName} (Anda)' : m.fullName),
                subtitle: Text(m.isAdmin ? 'Admin' : 'Anggota'),
                trailing: isAdmin && m.id != myId
                    ? TextButton(
                        onPressed: () => _changeRole(context, ref, m),
                        child: Text(
                          m.isAdmin ? 'Jadikan anggota' : 'Jadikan admin',
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    Profile member,
  ) async {
    final newRole = member.isAdmin ? 'anggota' : 'admin';
    final ok = await confirmDialog(
      context,
      title: member.isAdmin ? 'Jadikan anggota?' : 'Jadikan admin?',
      message: member.isAdmin
          ? '${member.fullName} tidak lagi bisa mengelola barang dan anggota.'
          : '${member.fullName} akan bisa menambah, mengubah, dan menghapus '
                'barang serta mengelola anggota.',
      confirmLabel: 'Ya, ubah',
    );
    if (!ok) return;
    try {
      await ref.read(authRepositoryProvider).setMemberRole(member.id, newRole);
      await ref.read(syncControllerProvider.notifier).syncNow();
    } on AuthFailure catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

class _JoinCodeCard extends ConsumerWidget {
  const _JoinCodeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final code = ref.watch(_joinCodeProvider);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kode kelompok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Bagikan ke anggota. Mereka memasukkannya saat mendaftar.',
            ),
            const SizedBox(height: 12),
            code.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text(
                'Kode hanya bisa ditampilkan saat ada koneksi internet.',
              ),
              data: (value) => Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      value ?? '—',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        letterSpacing: 6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Salin',
                    icon: const Icon(Icons.copy),
                    onPressed: value == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: value));
                            if (context.mounted) {
                              showSnack(context, 'Kode disalin.');
                            }
                          },
                  ),
                  IconButton(
                    tooltip: 'Ganti kode',
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Ganti kode kelompok?',
                        message:
                            'Kode lama tidak bisa dipakai mendaftar lagi. '
                            'Anggota yang sudah terdaftar tidak terpengaruh.',
                        confirmLabel: 'Ganti',
                      );
                      if (!ok) return;
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .regenerateJoinCode();
                        ref.invalidate(_joinCodeProvider);
                      } on AuthFailure catch (e) {
                        if (context.mounted) showSnack(context, e.message);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
