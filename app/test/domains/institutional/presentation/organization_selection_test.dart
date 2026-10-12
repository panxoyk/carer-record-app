import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/core/router/app_router.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
    'selection is cleared when the session user changes or signs out',
    () async {
      final testUserIdProvider = StateProvider<String?>((ref) => 'user-a');
      final container = ProviderContainer(
        overrides: [
          currentSessionUserIdProvider.overrideWith(
            (ref) => ref.watch(testUserIdProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        selectedOrganizationProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container.read(selectedOrganizationProvider.notifier).select('org-a');
      expect(
        container.read(selectedOrganizationProvider)?.organizationId,
        'org-a',
      );

      container.read(testUserIdProvider.notifier).state = 'user-b';
      await container.pump();
      expect(container.read(selectedOrganizationProvider), isNull);

      container.read(selectedOrganizationProvider.notifier).select('org-b');
      expect(container.read(selectedOrganizationProvider)?.userId, 'user-b');
      container.read(testUserIdProvider.notifier).state = null;
      await container.pump();
      expect(container.read(selectedOrganizationProvider), isNull);
    },
  );

  testWidgets(
    'changing organization invalidates old context before rereading',
    (tester) async {
      var reads = 0;
      final contexts = [
        _context('org-a', 'Hospital A', {'iam.membership.read'}),
        _context('org-b', 'Hospital B', {'clinical.patient.read'}),
      ];
      final router = GoRouter(
        initialLocation: '/select',
        routes: [
          GoRoute(
            path: '/select',
            builder: (_, __) => const OrganizationSelectionScreen(),
          ),
          GoRoute(path: '/', builder: (_, __) => const _SelectedOrganization()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextsProvider.overrideWith((ref) async {
              reads++;
              return contexts;
            }),
            selectedOrganizationProvider.overrideWith(
              (ref) => OrganizationSelectionController('user-1'),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.tap(find.text('Hospital B'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: org-b'), findsOneWidget);
      expect(reads, 2);
    },
  );
}

IamContext _context(
  String organizationId,
  String name,
  Set<String> permissions,
) => IamContext(
  organizationId: organizationId,
  organizationName: name,
  profileId: 'profile-$organizationId',
  displayName: 'Persona sintética',
  profileStatus: 'active',
  membershipId: 'membership-$organizationId',
  membershipStatus: 'active',
  permissions: permissions,
);

class _SelectedOrganization extends ConsumerWidget {
  const _SelectedOrganization();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectedOrganizationProvider);
    ref.watch(iamContextsProvider);
    return Scaffold(body: Text('Selected: ${selection?.organizationId}'));
  }
}
