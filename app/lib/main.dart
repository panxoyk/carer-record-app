import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/supabase_client.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabase(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  runApp(const ProviderScope(child: CarerRecordApp()));
}

class CarerRecordApp extends ConsumerWidget {
  const CarerRecordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Carer Record',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    routerConfig: ref.watch(appRouterProvider),
  );
}
