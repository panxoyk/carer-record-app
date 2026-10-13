import 'dart:async';

import 'package:carer_record_app/core/router/app_router.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('global lifecycle invalidates from paused to resumed', (
    tester,
  ) async {
    var reads = 0;
    final refresh = Completer<List<IamContext>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
