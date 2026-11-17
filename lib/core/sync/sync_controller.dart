import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/db_providers.dart';
import 'remote_store.dart';
import 'sync_engine.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    db: ref.watch(localDbProvider),
    remote: SupabaseRemoteStore(ref.watch(supabaseProvider)),
  ),
);

enum SyncPhase { idle, syncing, offline, error }

class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.failed = 0,
    this.lastSyncedAt,
    this.message,
  });

  final SyncPhase phase;

  /// Perubahan lokal yang belum terkirim.
  final int pending;

  /// Perubahan yang ditolak server.
  final int failed;
  final DateTime? lastSyncedAt;
  final String? message;

  SyncState copyWith({
    SyncPhase? phase,
    int? pending,
    int? failed,
    DateTime? lastSyncedAt,
    String? message,
  }) {
    return SyncState(
      phase: phase ?? this.phase,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      message: message,
    );
  }
}

/// Menentukan kapan sinkronisasi dijalankan: saat masuk, setelah tiap tulis
/// lokal (ditunda sebentar agar beberapa perubahan terkirim sekaligus), saat
/// koneksi kembali, dan berkala selama aplikasi terbuka.
class SyncController extends Notifier<SyncState> {
  static const _debounce = Duration(seconds: 2);
  static const _interval = Duration(minutes: 2);

  Timer? _debounceTimer;
  bool _running = false;
  bool _rerun = false;

  @override
  SyncState build() {
    final connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (!results.contains(ConnectivityResult.none)) schedule();
    });
    final periodic = Timer.periodic(_interval, (_) => syncNow());
    ref.onDispose(() {
      connectivitySub.cancel();
      periodic.cancel();
      _debounceTimer?.cancel();
    });
    return const SyncState();
  }

  /// Minta sinkronisasi sebentar lagi (dipanggil setelah tiap tulis lokal).
  void schedule() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, syncNow);
    _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final engine = ref.read(syncEngineProvider);
    final pending = await engine.pendingCount();
    final failed = await engine.failedCount();
    if (!ref.mounted) return;
    state = state.copyWith(
      pending: pending,
      failed: failed,
      message: state.message,
    );
  }

  Future<void> syncNow() async {
    if (ref.read(supabaseProvider).auth.currentSession == null) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    final engine = ref.read(syncEngineProvider);
    state = state.copyWith(phase: SyncPhase.syncing);
    try {
      do {
        _rerun = false;
        final result = await engine.sync();
        if (!ref.mounted) return;
        if (result.pulled > 0) ref.read(dbRevisionProvider.notifier).bump();
      } while (_rerun);
      final pending = await engine.pendingCount();
      final failed = await engine.failedCount();
      if (!ref.mounted) return;
      state = SyncState(
        phase: failed > 0 ? SyncPhase.error : SyncPhase.idle,
        pending: pending,
        failed: failed,
        lastSyncedAt: DateTime.now(),
        message: failed > 0 ? '$failed perubahan ditolak server' : null,
      );
    } on Object catch (e) {
      final online = !(await Connectivity().checkConnectivity()).contains(
        ConnectivityResult.none,
      );
      final pending = await engine.pendingCount();
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: online ? SyncPhase.error : SyncPhase.offline,
        pending: pending,
        message: online ? 'Gagal sinkron: $e' : null,
      );
    } finally {
      _running = false;
    }
  }

  Future<void> discardFailed() async {
    await ref.read(syncEngineProvider).discardFailed();
    ref.read(dbRevisionProvider.notifier).bump();
    await syncNow();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Dipanggil repository setelah setiap tulis lokal: segarkan layar dan
/// jadwalkan pengiriman ke server.
final onLocalWriteProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(dbRevisionProvider.notifier).bump();
    ref.read(syncControllerProvider.notifier).schedule();
  };
});
