import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class PerleApp extends ConsumerWidget {
  const PerleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Perle KKN',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      locale: const Locale('id'),
      supportedLocales: const [Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Ditampilkan bila aplikasi dibangun tanpa URL/kunci Supabase.
class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perle KKN',
      theme: buildAppTheme(Brightness.light),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.settings_suggest_outlined, size: 48),
                SizedBox(height: 16),
                Text(
                  'Konfigurasi Supabase belum diisi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  'Salin env.example.json menjadi env.json, isi SUPABASE_URL '
                  'dan SUPABASE_KEY, lalu jalankan:\n\n'
                  'flutter run --dart-define-from-file=env.json',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
