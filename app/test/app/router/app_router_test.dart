import 'package:carer_record_app/app/router/app_router.dart';
import 'package:carer_record_app/app/presentation/settings_screen.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_ports.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/on_device_ai/presentation/model_setup_providers.dart';
import 'package:carer_record_app/domains/users/presentation/roles_permissions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/authorization_refresh_override.dart';

void main() {
  testWidgets('router refresh preserves identity and permitted pushed stack', (
    tester,
  ) async {
    var modelsReady = false;
    var contextReads = 0;
    final gate = _TrackingAuthGate()
      ..session = Session(
        accessToken: 'synthetic-token',
        tokenType: 'bearer',
        user: User(
          id: 'user-a',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
    const context = IamContext(
      organizationId: 'org-a',
      organizationName: 'Synthetic org',
      profileId: 'profile-a',
      displayName: 'Synthetic user',
      profileStatus: 'active',
      membershipId: 'membership-a',
      membershipStatus: 'active',
      permissions: {'iam.membership.read', 'iam.role.read', 'iam.role.manage'},
    );
    final container = ProviderContainer(
      overrides: [
        authGateProvider.overrideWith((ref) => gate),
        modelReadinessProvider.overrideWith((ref) async => modelsReady),
        modelSetupSkippedProvider.overrideWith((ref) => true),
        setupAwaitingContinueProvider.overrideWith((ref) => false),
        selectedOrganizationProvider.overrideWith((ref) {
          return OrganizationSelectionController('user-a')..select('org-a');
        }),
        iamContextsProvider.overrideWith((ref) async {
          contextReads++;
          return const [context];
        }),
        iamContextProvider.overrideWith((ref) async => context),
        iamRolesProvider.overrideWith((ref) async => const []),
        iamDelegablePermissionsProvider.overrideWith((ref) async => const []),
        iamAdministrationProvider.overrideWithValue(_FakeIamAdministration()),
        authorizationRefreshOverride,
      ],
    );
    var containerDisposed = false;
    addTearDown(() {
      if (!containerDisposed) container.dispose();
    });

    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    router.go('/settings');
    await tester.pumpAndSettle();
    router.push<void>('/roles');
    await tester.pumpAndSettle();
    expect(find.byType(RolesPermissionsScreen), findsOneWidget);
    expect(find.text('Gestión de roles y permisos'), findsOneWidget);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
    expect(router.canPop(), isTrue);

    modelsReady = true;
    container.invalidate(modelReadinessProvider);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider), same(router));
    expect(find.byType(RolesPermissionsScreen), findsOneWidget);
    expect(find.text('Gestión de roles y permisos'), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(contextReads, greaterThan(0));

    router.pop();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    containerDisposed = true;
    expect(gate.activeListeners, isEmpty);
  });
}

class _TrackingAuthGate extends AuthGate {
  _TrackingAuthGate() : super.forTesting();

  final Set<VoidCallback> activeListeners = {};

  @override
  void addListener(VoidCallback listener) {
    activeListeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    activeListeners.remove(listener);
    super.removeListener(listener);
  }
}

class _FakeIamAdministration implements IamAdministration {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
