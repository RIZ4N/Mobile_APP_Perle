import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/local_db.dart';

/// Galat dengan pesan yang layak ditampilkan langsung ke pengguna.
class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._client, this._db);

  final SupabaseClient _client;
  final Database _db;

  Future<void> signIn({required String email, required String password}) async {
    await _guard(
      () => _client.auth.signInWithPassword(email: email, password: password),
    );
  }

  /// Mengembalikan true bila langsung masuk, false bila akun harus
  /// dikonfirmasi lewat email dulu.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String joinCode,
  }) async {
    final codeOk = await _guard(
      () =>
          _client.rpc<dynamic>('check_join_code', params: {'p_code': joinCode}),
    );
    if (codeOk != true) {
      throw AuthFailure(
        joinCode.trim().isEmpty
            ? 'Masukkan kode kelompok dari koordinator.'
            : 'Kode kelompok salah.',
      );
    }
    final res = await _guard(
      () => _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'join_code': joinCode},
      ),
    );
    return res.session != null;
  }

  /// Keluar dan mengosongkan data lokal supaya akun berikutnya di HP yang
  /// sama tidak mewarisi antrean perubahan milik akun ini.
  Future<void> signOut() async {
    await wipeLocalDb(_db);
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on AuthException {
      // Sesi lokal tetap dihapus walau server tidak terjangkau.
    }
  }

  Future<void> updateOwnName(String fullName) async {
    final uid = _client.auth.currentUser!.id;
    await _guard(
      () => _client
          .from('profiles')
          .update({'full_name': fullName})
          .eq('id', uid),
    );
  }

  // ------------------------------------------------- khusus admin (online)

  Future<String?> fetchJoinCode() async {
    final row = await _guard(
      () => _client.from('app_config').select('join_code').maybeSingle(),
    );
    return row?['join_code'] as String?;
  }

  Future<String> regenerateJoinCode() async {
    final code = await _guard(
      () => _client.rpc<dynamic>('regenerate_join_code'),
    );
    return code as String;
  }

  Future<void> setMemberRole(String userId, String role) async {
    await _guard(
      () => _client.rpc<dynamic>(
        'set_member_role',
        params: {'p_user_id': userId, 'p_role': role},
      ),
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw AuthFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      throw AuthFailure(e.message);
    } on Object {
      throw AuthFailure(
        'Tidak bisa terhubung ke server. Periksa koneksi internet.',
      );
    }
  }

  String _authMessage(AuthException e) {
    return switch (e.code) {
      'invalid_credentials' => 'Email atau kata sandi salah.',
      'email_not_confirmed' =>
        'Email belum dikonfirmasi. Buka tautan di email Anda dulu.',
      'user_already_exists' ||
      'email_exists' => 'Email ini sudah terdaftar. Silakan masuk.',
      'weak_password' => 'Kata sandi terlalu lemah (minimal 6 karakter).',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => 'Terlalu banyak percobaan. Coba lagi nanti.',
      _ =>
        e is AuthRetryableFetchException
            ? 'Tidak bisa terhubung ke server. Periksa koneksi internet.'
            : e.message,
    };
  }
}
