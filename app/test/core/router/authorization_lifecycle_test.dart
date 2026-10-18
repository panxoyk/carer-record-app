import 'dart:async';

import 'package:carer_record_app/app/router/route_entry_refresh.dart';
import 'package:carer_record_app/app/session/authorization_lifecycle_boundary.dart';

import '../../support/authorization_refresh_override.dart';

import 'package:carer_record_app/core/design_system/clinical_toast.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('global lifecycle invalidates from paused to resumed', (
    tester,
  ) async {
    var reads = 0;
    final refresh = Completer<List<IamContext>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          authGateProvider.overrideWith((ref) => AuthGate.forTesting()),
          iamContextsProvider.overrideWith((ref) async {
            reads++;
            if (reads > 1) return refresh.future;
            return const [];
          }),
        ],
        child: const AuthorizationLifecycleBoundary(
          child: MaterialApp(home: _ContextConsumer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('loaded'), findsNothing);
    refresh.complete(const []);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  testWidgets('administrative routes invalidate exactly once on entry', (
    tester,
  ) async {
    for (final location in ['/users', '/assignments', '/roles']) {
      var reads = 0;
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: location,
            builder: (_, __) => administrativeEntryForLocation(
              location,
              const _ContextConsumer(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextsProvider.overrideWith((ref) async {
              reads++;
              return const [];
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        reads,
        2,
        reason: '$location should query initially and once on entry',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextsProvider.overrideWith((ref) async {
              reads++;
              return const [];
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        reads,
        2,
        reason: '$location rebuild must not cause another entry refresh',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets('resuming invalidates active role and permission catalog once', (
    tester,
  ) async {
    var roleReads = 0;
    var catalogReads = 0;
    final context = IamContext(
      organizationId: 'org',
      organizationName: 'Org',
      profileId: 'p',
      displayName: 'Actor',
      profileStatus: 'active',
      membershipId: 'm',
      membershipStatus: 'active',
      permissions: {'iam.role.read', 'iam.role.manage'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          authGateProvider.overrideWith((ref) => AuthGate.forTesting()),
          iamContextProvider.overrideWith((ref) async => context),
          iamRolesProvider.overrideWith((ref) async {
            roleReads++;
            return const [];
          }),
          iamDelegablePermissionsProvider.overrideWith((ref) async {
            catalogReads++;
            return const [];
          }),
        ],
        child: const AuthorizationLifecycleBoundary(
          child: MaterialApp(home: _RoleSourcesConsumer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(roleReads, 1);
    expect(catalogReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(roleReads, 2);
    expect(catalogReads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resuming refreshes active institutional and clinical sources', (
    tester,
  ) async {
    const id = '00000000-0000-4000-8000-000000000002';
    final reads = <String, int>{};
    Future<T> tracked<T>(String source, T value) async {
      reads.update(source, (count) => count + 1, ifAbsent: () => 1);
      return value;
    }

    final context = IamContext(
      organizationId: 'org',
      organizationName: 'Org',
      profileId: 'p',
      displayName: 'Actor',
      profileStatus: 'active',
      membershipId: 'm',
      membershipStatus: 'active',
      permissions: {
        'iam.membership.read',
        'iam.role.read',
        'iam.role.manage',
        'clinical.assignment.manage',
        'clinical.census.read',
        'clinical.patient.read',
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          authGateProvider.overrideWith((ref) => AuthGate.forTesting()),
          iamContextsProvider.overrideWith(
            (ref) => tracked('contexts', const <IamContext>[]),
          ),
          iamContextProvider.overrideWith((ref) => tracked('context', context)),
          iamMembersProvider.overrideWith(
            (ref) => tracked('members', const <IamMember>[]),
          ),
          iamRolesProvider.overrideWith(
            (ref) => tracked('roles', const <IamRole>[]),
          ),
          iamDelegablePermissionsProvider.overrideWith(
            (ref) => tracked('catalog', const <IamPermission>[]),
          ),
          iamRoleAssignmentsProvider.overrideWith(
            (ref) => tracked(
              'role assignments',
              const <String, List<IamRoleAssignment>>{},
            ),
          ),
          careAssignmentsProvider.overrideWith(
            (ref) =>
                tracked('care assignments', const <CareAssignmentRecord>[]),
          ),
          careAssignmentPatientNamesProvider.overrideWith(
            (ref) => tracked('authorized names', const <String, String>{}),
          ),
          eligibleMembersProvider.overrideWith(
            (ref) => tracked('eligible members', const <EligibleMember>[]),
          ),
          patientsProvider.overrideWith((ref) => tracked('census', const [])),
          patientProvider(id).overrideWith((ref) => tracked('patient', null)),
          hospitalizationClinicalEventsProvider(id)
              .overrideWith((ref) => tracked('timeline', const [])),
        ],
        child: const AuthorizationLifecycleBoundary(
          child: MaterialApp(home: _AllAuthorizationSourcesConsumer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads.values, everyElement(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      reads.keys,
      containsAll([
        'contexts',
        'context',
        'members',
        'roles',
        'catalog',
        'role assignments',
        'care assignments',
        'authorized names',
        'eligible members',
        'census',
        'patient',
        'timeline',
      ]),
    );
    expect(reads.values, everyElement(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each clinical route invalidates active clinical sources once', (
    tester,
  ) async {
    const id = '00000000-0000-4000-8000-000000000002';
    for (final location in [
      '/patients',
      '/hospitalizations/$id',
      '/hospitalizations/$id/details',
    ]) {
      var censusReads = 0;
      var timelineReads = 0;
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/patients',
            builder: (_, __) =>
                const ClinicalEntryRefresh(child: _ClinicalConsumer()),
          ),
          GoRoute(
            path: '/hospitalizations/:id',
            builder: (_, __) =>
                const ClinicalEntryRefresh(child: _ClinicalConsumer()),
          ),
          GoRoute(
            path: '/hospitalizations/:id/details',
            builder: (_, __) =>
                const ClinicalEntryRefresh(child: _ClinicalConsumer()),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            patientsProvider.overrideWith((ref) async {
              censusReads++;
              return const [];
            }),
            hospitalizationClinicalEventsProvider(id).overrideWith((ref) async {
              timelineReads++;
              return const [];
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        censusReads,
        2,
        reason: '$location should query once and requery once on entry',
      );
      expect(
        timelineReads,
        2,
        reason: '$location invalidates active timeline source once',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets('resuming invalidates active clinical providers', (tester) async {
    const id = '00000000-0000-4000-8000-000000000002';
    var censusReads = 0;
    var timelineReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          authGateProvider.overrideWith((ref) => AuthGate.forTesting()),
          patientsProvider.overrideWith((ref) async {
            censusReads++;
            return const [];
          }),
          hospitalizationClinicalEventsProvider(id).overrideWith((ref) async {
            timelineReads++;
            return const [];
          }),
        ],
        child: const AuthorizationLifecycleBoundary(
          child: MaterialApp(home: _ClinicalConsumer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(censusReads, 1);
    expect(timelineReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(censusReads, 2);
    expect(timelineReads, 2);
  });

  testWidgets(
    'clinical toast clears only when the signed-in identity changes',
    (tester) async {
      final gate = AuthGate.forTesting();
      gate.handleAuthState(_authState(AuthChangeEvent.signedIn, 'user-a'));
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ProviderScope(
              overrides: [authGateProvider.overrideWith((ref) => gate)],
              child: AuthorizationLifecycleBoundary(
                child: MaterialApp(
                  builder: (context, child) => ClinicalToastHost(child: child!),
                  home: const _ToastTrigger(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Acción pendiente'), findsOneWidget);

        gate.handleAuthState(
          _authState(AuthChangeEvent.tokenRefreshed, 'user-a'),
        );
        await tester.pump();
        expect(find.text('Acción pendiente'), findsOneWidget);

        gate.handleAuthState(_authState(AuthChangeEvent.signedOut, null));
        await tester.pump();
        expect(find.text('Acción pendiente'), findsNothing);
      } finally {
        ClinicalToast.dismissAll();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      }
    },
  );

  testWidgets('changing selected organization clears clinical toast', (
    tester,
  ) async {
    final gate = AuthGate.forTesting();
    final organizationSelection = OrganizationSelectionController('user-a')
      ..select('org-a');
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ProviderScope(
            overrides: [
              authorizationRefreshOverride,
              authGateProvider.overrideWith((ref) => gate),
              selectedOrganizationProvider.overrideWith(
                (ref) => organizationSelection,
              ),
            ],
            child: AuthorizationLifecycleBoundary(
              child: MaterialApp(
                builder: (context, child) => ClinicalToastHost(child: child!),
                home: const _ToastTrigger(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Acción pendiente'), findsOneWidget);

      final selection = ProviderScope.containerOf(
        tester.element(find.byType(_ToastTrigger)),
      ).read(selectedOrganizationProvider.notifier);
      selection.select('org-a');
      await tester.pump();
      expect(find.text('Acción pendiente'), findsOneWidget);

      selection.select('org-b');
      await tester.pump();
      expect(find.text('Acción pendiente'), findsNothing);
    } finally {
      ClinicalToast.dismissAll();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}

AuthState _authState(AuthChangeEvent event, String? userId) => AuthState(
  event,
  userId == null
      ? null
      : Session(
          accessToken: 'synthetic-token',
          tokenType: 'bearer',
          user: User(
            id: userId,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-01-01T00:00:00Z',
          ),
        ),
);

class _ToastTrigger extends StatelessWidget {
  const _ToastTrigger();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClinicalToast.failure(context, message: 'Acción pendiente');
    });
    return const Scaffold(body: Text('Host'));
  }
}

class _ContextConsumer extends ConsumerWidget {
  const _ContextConsumer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contexts = ref.watch(iamContextsProvider);
    return Scaffold(body: Text(contexts.isLoading ? 'loading' : 'loaded'));
  }
}

class _ClinicalConsumer extends ConsumerWidget {
  const _ClinicalConsumer();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(patientsProvider);
    ref.watch(
      hospitalizationClinicalEventsProvider(
        '00000000-0000-4000-8000-000000000002',
      ),
    );
    return const Scaffold(body: Text('clinical'));
  }
}

class _RoleSourcesConsumer extends ConsumerWidget {
  const _RoleSourcesConsumer();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(iamRolesProvider);
    ref.watch(iamDelegablePermissionsProvider);
    return const Scaffold(body: Text('roles'));
  }
}

class _AllAuthorizationSourcesConsumer extends ConsumerWidget {
  const _AllAuthorizationSourcesConsumer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const id = '00000000-0000-4000-8000-000000000002';
    ref.watch(iamContextsProvider);
    ref.watch(iamContextProvider);
    ref.watch(iamMembersProvider);
    ref.watch(iamRolesProvider);
    ref.watch(iamDelegablePermissionsProvider);
    ref.watch(iamRoleAssignmentsProvider);
    ref.watch(careAssignmentsProvider);
    ref.watch(careAssignmentPatientNamesProvider);
    ref.watch(eligibleMembersProvider);
    ref.watch(patientsProvider);
    ref.watch(patientProvider(id));
    ref.watch(hospitalizationClinicalEventsProvider(id));
    return const Scaffold(body: Text('authorization sources'));
  }
}
