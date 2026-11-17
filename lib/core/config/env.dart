/// Konfigurasi yang disuntikkan saat build lewat
/// `--dart-define-from-file=env.json` (lihat env.example.json).
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable key (dulu disebut anon key). Aman ditaruh di aplikasi karena
  /// akses data dijaga Row Level Security.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
