import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/db_providers.dart';
import '../../core/sync/sync_controller.dart';
import 'data/auth_repository.dart';
import 'data/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(supabaseProvider), ref.watch(localDbProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// ID user yang sedang masuk (null bila belum masuk). Sesi tersimpan di HP,
/// jadi tetap terisi saat aplikasi dibuka tanpa internet.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

/// Semua anggota kelompok (dari cache lokal).
final membersProvider = FutureProvider<List<Profile>>((ref) async {
  ref.watch(dbRevisionProvider);
  final rows = await ref
      .watch(localDbProvider)
      .query('profiles', orderBy: 'full_name COLLATE NOCASE');
  return rows.map(Profile.fromMap).toList();
});

/// Profil user yang sedang masuk; null sampai sinkronisasi pertama selesai.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final members = await ref.watch(membersProvider.future);
  return members.where((m) => m.id == uid).firstOrNull;
});

final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentProfileProvider).value?.isAdmin ?? false,
);
