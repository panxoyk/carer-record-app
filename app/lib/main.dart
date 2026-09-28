import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/clinical_design_system.dart';
import 'core/network/supabase_client.dart';
import 'core/router/app_router.dart';
import 'core/time/clinical_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeClinicalTimeZones();
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
    theme: ClinicalTheme.build(),
    routerConfig: ref.watch(appRouterProvider),
  );
}
