import 'package:carer_record_app/core/router/app_router.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/users/presentation/roles_permissions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'ProtectedShell exposes roles only with both permissions and tap navigates',
    (tester) async {
      for (final permissions in [
        {'iam.membership.read', 'iam.role.read', 'iam.role.manage'},
        {'iam.membership.read', 'iam.role.read'},
        {'iam.membership.read', 'iam.role.manage'},
      ]) {
        final context = _iam('org-a', permissions);
        final router = _router(
          initialLocation: '/',
          contextForLocation: (_) => context,
        );
        await tester.pumpWidget(_scope(context, router));
        await tester.pumpAndSettle();
        final button = find.text('Roles y permisos');
        if (permissions.contains('iam.role.read') &&
            permissions.contains('iam.role.manage')) {
          expect(button, findsOneWidget);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/roles');
          expect(find.byType(RolesPermissionsScreen), findsOneWidget);
          expect(find.text('Gestión de roles y permisos'), findsOneWidget);
        } else {
          expect(button, findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );

  testWidgets(
    'manual /roles route redirects before sensitive builder for each missing permission',
    (tester) async {
      for (final permissions in [
        {'iam.role.manage'},
        {'iam.role.read'},
      ]) {
        var sensitiveBuilds = 0;
        var roleReads = 0;
        var catalogReads = 0;
        final context = _iam('org-a', permissions);
        final router = _router(
          initialLocation: '/roles',
          contextForLocation: (_) => context,
          onSensitiveBuild: () => sensitiveBuilds++,
        );
        await tester.pumpWidget(
          _scope(
            context,
            router,
            roleRead: () => roleReads++,
            catalogRead: () => catalogReads++,
          ),
        );
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(sensitiveBuilds, 0);
        expect(roleReads, 0);
        expect(catalogReads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      }
    },
  );

  testWidgets(
    'organization switch refreshes real router and removes prior roles screen',
    (tester) async {
      final contexts = [
        _iam('org-a', {'iam.role.read', 'iam.role.manage'}),
        _iam('org-b', {'iam.role.read'}),
      ];
      final refresh = _RouterRefreshForTest();
      final container = ProviderContainer(
        overrides: [
          selectedOrganizationProvider.overrideWith(
            (ref) => OrganizationSelectionController('user-1'),
          ),
        ],
      );
      container.read(selectedOrganizationProvider.notifier).select('org-a');
      final selectionSubscription = container.listen(
        selectedOrganizationProvider,
        (_, __) => refresh.refresh(),
      );
      final router = GoRouter(
        initialLocation: '/roles',
        refreshListenable: refresh,
        redirect: (context, state) {
          final selected = contextForOrganizationSelection(
            contexts,
            container.read(selectedOrganizationProvider),
            'user-1',
          );
          return selected == null
              ? '/settings'
              : permissionRedirectForLocation(selected, state.matchedLocation);
        },
        routes: [
          GoRoute(
            path: '/roles',
            builder: (_, __) => const Scaffold(body: Text('Roles de A')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('Settings')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/roles');
      expect(find.text('Roles de A'), findsOneWidget);

      container.read(selectedOrganizationProvider.notifier).select('org-b');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Roles de A'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      selectionSubscription.close();
      container.dispose();
      refresh.dispose();
    },
  );
}

GoRouter _router({
  required String initialLocation,
  required IamContext? Function(String location) contextForLocation,
  VoidCallback? onSensitiveBuild,
}) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) => state.matchedLocation == '/'
      ? null
      : permissionRedirectForLocation(
          contextForLocation(state.matchedLocation)!,
          state.matchedLocation,
        ),
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ProtectedShell()),
    GoRoute(
      path: '/users',
      builder: (_, __) => const Scaffold(body: Text('Users')),
    ),
    GoRoute(
      path: '/roles',
      builder: (_, __) {
        onSensitiveBuild?.call();
        return const RolesPermissionsScreen();
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const Scaffold(body: Text('Settings')),
    ),
  ],
);

Widget _scope(
  IamContext context,
  GoRouter router, {
  VoidCallback? roleRead,
  VoidCallback? catalogRead,
}) => ProviderScope(
  overrides: [
    iamContextProvider.overrideWith((ref) async => context),
    iamContextsProvider.overrideWith((ref) async => [context]),
    iamRolesProvider.overrideWith((ref) async {
      roleRead?.call();
      return const [];
    }),
    iamDelegablePermissionsProvider.overrideWith((ref) async {
      catalogRead?.call();
      return const [];
    }),
  ],
  child: MaterialApp.router(routerConfig: router),
);

IamContext _iam(String organizationId, Set<String> permissions) => IamContext(
  organizationId: organizationId,
  organizationName: 'Hospital $organizationId',
  profileId: 'profile-$organizationId',
  displayName: 'Persona sintética',
  profileStatus: 'active',
  membershipId: 'membership-$organizationId',
  membershipStatus: 'active',
  permissions: permissions,
);

class _RouterRefreshForTest extends ChangeNotifier {
  void refresh() => notifyListeners();
}
