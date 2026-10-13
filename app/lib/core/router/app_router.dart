import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/auth/presentation/auth_screens.dart';
import '../../domains/patient/presentation/patient_screens.dart';
import '../../domains/institutional/presentation/iam_providers.dart';
import '../../domains/institutional/data/iam_models.dart';
import '../../domains/users/presentation/users_screen.dart';
import '../../domains/users/presentation/assignments_screen.dart';
import '../../domains/users/presentation/roles_permissions_screen.dart';
import '../design_system/clinical_design_system.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final gate = ref.read(authGateProvider);
  final refresh = _RouterRefresh(gate);
  ref.listen(selectedOrganizationProvider, (_, __) => refresh.refresh());
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      const publicPaths = {'/login', '/recover'};
      if (gate.session == null) {
        return publicPaths.contains(location) ? null : '/login';
      }
      if (gate.recoveringPassword) {
        return location == '/update-password' ? null : '/update-password';
      }
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
        builder: (_, __) => const ClinicalEntryRefresh(child: PatientsScreen()),
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

String? permissionRedirectForLocation(IamContext context, String location) {
  if (location == '/') {
    if (context.allows('clinical.census.read') &&
        context.allows('clinical.patient.read')) {
      return '/patients';
    }
    return '/settings';
  }
  if (location == '/users' && !context.allows('iam.membership.read')) {
    return '/settings';
  }
  if (location == '/assignments' &&
      !context.allows('clinical.assignment.manage')) {
    return '/settings';
  }
  if (location == '/roles' &&
      (!context.allows('iam.role.read') ||
          !context.allows('iam.role.manage'))) {
    return '/settings';
  }
  if (location.startsWith('/patients') &&
      (!context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read'))) {
    return '/settings';
  }
  if (location.startsWith('/hospitalizations/') &&
      (!context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read'))) {
    return '/settings';
  }
  if (location.startsWith('/hospitalizations/') &&
      !location.endsWith('/details') &&
      !context.allows('clinical.timeline.read')) {
    return '/settings';
  }
  return null;
}

IamContext? contextForOrganizationSelection(
  List<IamContext> contexts,
  OrganizationSelection? selection,
  String sessionUserId,
) => IamContext.selectForSession(contexts, selection, sessionUserId);

String? organizationSelectionRedirect(
  List<IamContext> contexts,
  OrganizationSelection? selection,
  String sessionUserId,
  String location,
) {
  final selected = contextForOrganizationSelection(
    contexts,
    selection,
    sessionUserId,
  );
  if (contexts.length > 1 && selected == null) {
    return location == '/select-organization' ? null : '/select-organization';
  }
  if (contexts.length > 1 && location == '/select-organization') return '/';
  return null;
}

class OrganizationSelectionScreen extends ConsumerWidget {
  const OrganizationSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contexts = ref.watch(iamContextsProvider);
    return Scaffold(
      appBar: clinicalAppBar(title: 'Seleccionar organización'),
      body: contexts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('No fue posible cargar tus organizaciones.'),
        ),
        data: (items) => ListView(
          children: [
            for (final item in items)
              ListTile(
                title: Text(item.organizationName),
                onTap: () {
                  ref
                      .read(selectedOrganizationProvider.notifier)
                      .select(item.organizationId);
                  invalidateAuthorizationAndData(ref);
                  context.go('/');
                },
              ),
          ],
        ),
      ),
    );
  }
}

class AdministrativeEntryRefresh extends ConsumerStatefulWidget {
  const AdministrativeEntryRefresh({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AdministrativeEntryRefresh> createState() =>
      _AdministrativeEntryRefreshState();
}

class ClinicalEntryRefresh extends ConsumerStatefulWidget {
  const ClinicalEntryRefresh({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<ClinicalEntryRefresh> createState() =>
      _ClinicalEntryRefreshState();
}

class _ClinicalEntryRefreshState extends ConsumerState<ClinicalEntryRefresh> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) invalidateAuthorizationAndData(ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget administrativeEntryForLocation(String location, Widget child) {
  if (location != '/users' &&
      location != '/assignments' &&
      location != '/roles') {
    throw ArgumentError.value(
      location,
      'location',
      'Not an administrative route',
    );
  }
  return AdministrativeEntryRefresh(child: child);
}

class _AdministrativeEntryRefreshState
    extends ConsumerState<AdministrativeEntryRefresh> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) invalidateAuthorizationAndData(ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthorizationLifecycleBoundary extends ConsumerStatefulWidget {
  const AuthorizationLifecycleBoundary({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AuthorizationLifecycleBoundary> createState() =>
      _AuthorizationLifecycleBoundaryState();
}

class _AuthorizationLifecycleBoundaryState
    extends ConsumerState<AuthorizationLifecycleBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      invalidateAuthorizationAndData(ref);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._gate) {
    _gate.addListener(notifyListeners);
  }

  final ChangeNotifier _gate;

  void refresh() => notifyListeners();

  @override
  void dispose() {
    _gate.removeListener(notifyListeners);
    super.dispose();
  }
}

class ProtectedShell extends ConsumerWidget {
  const ProtectedShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider);
    return Scaffold(
      appBar: clinicalAppBar(title: 'Carer Record'),
      body: Center(
        child: iam.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => const Text('No fue posible cargar tu perfil.'),
          data: (p) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sesión activa: ${p?.displayName ?? ''}'),
              if ((ref.read(iamContextsProvider).valueOrNull?.length ?? 0) > 1)
                TextButton(
                  onPressed: () => context.go('/select-organization'),
                  child: Text(
                    'Organización: ${p?.organizationName ?? ''} · Cambiar',
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Consulta pacientes autorizados desde tu cuenta.'),
              if (p?.allows('clinical.census.read') == true &&
                  p?.allows('clinical.patient.read') == true)
                TextButton(
                  onPressed: () => context.go('/patients'),
                  child: const Text('Ver pacientes'),
                ),
              if (p?.allows('iam.membership.read') ?? false)
                TextButton(
                  onPressed: () => context.go('/users'),
                  child: const Text('Gestionar usuarios'),
                ),
              if (p?.allows('iam.role.read') == true &&
                  p?.allows('iam.role.manage') == true)
                TextButton(
                  onPressed: () => context.go('/roles'),
                  child: const Text('Roles y permisos'),
                ),
              if (p?.allows('clinical.assignment.manage') ?? false)
                TextButton(
                  onPressed: () => context.go('/assignments'),
                  child: const Text('Gestionar asignaciones'),
                ),
              TextButton(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: clinicalAppBar(title: 'Cuenta suspendida'),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tu cuenta está suspendida. Contacta a administración.'),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    ),
  );
}
