import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Server menolak permintaan (melanggar RLS/constraint, dsb.). Berbeda dari
/// galat jaringan: mengulang permintaan yang sama tidak akan berhasil.
class RemoteRejected implements Exception {
  RemoteRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lapisan tipis di atas Supabase supaya mesin sinkronisasi bisa diuji tanpa
/// jaringan.
abstract class RemoteStore {
  /// Upsert baris. Melempar [RemoteRejected] bila ditolak server; galat lain
  /// (jaringan) diteruskan apa adanya.
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    required String onConflict,
  });

  /// Baris dengan `updated_at >= since` (semua bila null), urut menaik.
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String pk,
    String? since,
    required int limit,
    required int offset,
  });

  /// Mengunggah foto struk, mengembalikan path-nya di bucket.
  Future<String> uploadReceipt({required String expenseId, required File file});
}

const receiptsBucket = 'receipts';

class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    required String onConflict,
  }) async {
    try {
      await _client.from(table).upsert(rows, onConflict: onConflict);
    } on PostgrestException catch (e) {
      throw RemoteRejected(e.message);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required String pk,
    String? since,
    required int limit,
    required int offset,
  }) async {
    var query = _client.from(table).select();
    if (since != null) {
      query = query.gte('updated_at', since);
    }
    return query
        .order('updated_at', ascending: true)
        .order(pk, ascending: true)
        .range(offset, offset + limit - 1);
  }

  @override
  Future<String> uploadReceipt({
    required String expenseId,
    required File file,
  }) async {
    // Path unik per unggahan → cukup izin INSERT, tidak perlu menimpa.
    final path = '$expenseId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _client.storage
          .from(receiptsBucket)
          .upload(
            path,
            file,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    } on StorageException catch (e) {
      // Kode 4xx = ditolak; selain itu anggap gangguan sementara.
      final code = int.tryParse(e.statusCode ?? '');
      if (code != null && code >= 400 && code < 500) {
        throw RemoteRejected(e.message);
      }
      rethrow;
    }
    return path;
  }
}
