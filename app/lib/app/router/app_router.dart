import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domains/fhir_record/presentation/fhir_record_screens.dart';
import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/auth/presentation/auth_screens.dart';
import '../../domains/on_device_ai/presentation/model_setup_screen.dart';
import '../../domains/on_device_ai/presentation/model_management_screen.dart';
import '../../domains/on_device_ai/presentation/model_setup_providers.dart';
import '../../domains/patient/presentation/patient_screens.dart';
import '../presentation/settings_screen.dart';
import '../presentation/protected_shell.dart';
import '../../domains/institutional/presentation/organization_selection_screen.dart';
import '../../domains/auth/presentation/suspended_screen.dart';
import '../../domains/institutional/presentation/iam_providers.dart';
import '../../domains/institutional/domain/iam_entities.dart';
import '../../domains/users/presentation/users_screen.dart';
import '../../domains/users/presentation/assignments_screen.dart';
import '../../domains/users/presentation/roles_permissions_screen.dart';
import 'navigation_policy.dart';
import 'route_entry_refresh.dart';
import 'router_refresh.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final gate = ref.read(authGateProvider);
  final refresh = RouterRefresh(gate);
  ref.listen(modelReadinessProvider, (_, __) => refresh.refresh());
  ref.listen(modelSetupSkippedProvider, (_, __) => refresh.refresh());
  ref.listen(setupAwaitingContinueProvider, (_, __) => refresh.refresh());
  ref.listen(selectedOrganizationProvider, (previous, next) {
    if (previous != next) refresh.refresh();
  });
  final router = GoRouter(
    initialLocation: '/setup',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      const publicPaths = {'/login', '/recover', '/setup'};
      final modelsReady = await ref
          .read(modelReadinessProvider.future)
          .catchError((_) => false);
      final setupRedirect = modelSetupRedirect(
        location: location,
        modelsReady: modelsReady,
        skipped: ref.read(modelSetupSkippedProvider),
        setupAwaitingContinue: ref.read(setupAwaitingContinueProvider),
        hasSession: gate.session != null,
        recoveringPassword: gate.recoveringPassword,
      );
      if (setupRedirect != null) return setupRedirect;
      if (gate.session == null) {
        return publicPaths.contains(location) ? null : '/login';
      }
      if (gate.recoveringPassword) {
        return location == '/update-password' ? null : '/update-password';
      }
      // Keep the authenticated first-run route available until the user
      // installs the optional models or explicitly skips setup.
      if (location == '/setup') return null;
      if (location == '/update-password') {
        return '/';
      }
      final contexts = await ref
          .read(iamContextsProvider.future)
          .catchError((_) => <IamContext>[]);
      final iam = contextForOrganizationSelection(
        contexts,
        ref.read(selectedOrganizationProvider),
        gate.session!.user.id,
      );
      final selectionRedirect = organizationSelectionRedirect(
        contexts,
        ref.read(selectedOrganizationProvider),
        gate.session!.user.id,
        location,
      );
      if (selectionRedirect != null) return selectionRedirect;
      if (iam == null ||
          iam.profileStatus != 'active' ||
          iam.membershipStatus != 'active') {
        return location == '/suspended' ? null : '/suspended';
      }
      if (publicPaths.contains(location) ||
          location == '/suspended' ||
          location == '/select-organization') {
        return '/';
      }
      return permissionRedirectForLocation(iam, location);
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const ProtectedShell()),
      GoRoute(path: '/setup', builder: (_, __) => const ModelSetupScreen()),
      GoRoute(
        path: '/models',
        builder: (_, __) => const ModelManagementScreen(),
      ),
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: '/recover',
        builder: (_, __) => const RecoverPasswordScreen(),
      ),
      GoRoute(
        path: '/update-password',
        builder: (_, __) => const UpdatePasswordScreen(),
      ),
      GoRoute(path: '/suspended', builder: (_, __) => const SuspendedScreen()),
      GoRoute(
        path: '/select-organization',
        builder: (_, __) => const OrganizationSelectionScreen(),
      ),
      GoRoute(
        path: '/users',
        builder: (_, __) =>
            administrativeEntryForLocation('/users', const UsersScreen()),
      ),
      GoRoute(
        path: '/assignments',
        builder: (_, __) => administrativeEntryForLocation(
          '/assignments',
          const AssignmentsScreen(),
        ),
      ),
      GoRoute(
        path: '/roles',
        builder: (_, __) => administrativeEntryForLocation(
          '/roles',
          const RolesPermissionsScreen(),
        ),
      ),
      GoRoute(
        path: '/patients',

        ///                builder: (_, __) => const ClinicalEntryRefresh(child: PatientsScreen()), ///descomentar estas 3 lineas para ver los que estaban antes de la integracion de fhir
        ///      ),
        ///      GoRoute(
        ///        path: '/fhir/patients',
        builder: (_, __) =>
            const ClinicalEntryRefresh(child: FhirPatientListScreen()),
      ),
      GoRoute(
        path: '/fhir/patients/:patientId',
        builder: (_, state) => ClinicalEntryRefresh(
          child: FhirClinicalRecordScreen(
            patientId: state.pathParameters['patientId']!,
          ),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/hospitalizations/:hospitalizationId',
        builder: (_, state) => ClinicalEntryRefresh(
          child: PatientDetailScreen(
            hospitalizationId: state.pathParameters['hospitalizationId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/hospitalizations/:hospitalizationId/details',
        builder: (_, state) => ClinicalEntryRefresh(
          child: PatientInformationScreen(
            hospitalizationId: state.pathParameters['hospitalizationId']!,
          ),
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
