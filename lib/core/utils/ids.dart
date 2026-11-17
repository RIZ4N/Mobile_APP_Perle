import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// ID dibuat di HP supaya baris bisa dibuat saat offline.
String newId() => _uuid.v4();

/// Waktu sekarang dalam UTC ISO-8601 — format seluruh kolom waktu di SQLite.
String nowIso() => DateTime.now().toUtc().toIso8601String();
