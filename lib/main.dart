import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/db/db_providers.dart';
import 'core/db/local_db.dart';
import 'core/utils/formatters.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(appLocale);

  if (!Env.isConfigured) {
    runApp(const ConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseKey,
  );
  final db = await openLocalDb();

  runApp(
    ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const PerleApp(),
    ),
  );
}
