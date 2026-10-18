import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/clinical_design_system.dart';
import 'core/design_system/clinical_toast.dart';
import 'core/network/supabase_client.dart';
import 'app/router/app_router.dart';
import 'app/session/authorization_lifecycle_boundary.dart';
import 'core/session/session_artifact_cleanup.dart';
import 'core/session/authorization_refresh.dart';
import 'app/session/authorization_refresh_coordinator.dart';
import 'core/time/clinical_time.dart';
import 'domains/context_note/data/draft_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeClinicalTimeZones();
  await initializeSupabase(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  final vault = DraftVault();
  runApp(
    ProviderScope(
      overrides: [
        sessionArtifactCleanupProvider.overrideWith((ref) => vault.purgeAll),
        authorizationRefreshProvider.overrideWith(authorizationRefreshFor),
      ],
      child: const CarerRecordApp(),
    ),
  );
}

class CarerRecordApp extends ConsumerWidget {
  const CarerRecordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AuthorizationLifecycleBoundary(
        child: MaterialApp.router(
          builder: (context, child) => ClinicalToastHost(child: child!),
          title: 'Carer Record',
          theme: ClinicalTheme.build(),
          routerConfig: ref.watch(appRouterProvider),
        ),
      );
}
