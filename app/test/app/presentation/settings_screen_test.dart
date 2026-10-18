import 'dart:ui' as ui;

import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/app/presentation/settings_screen.dart';
import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('settings shows identity once, membership and AI before logout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith((ref) async => _context()),
          iamContextsProvider.overrideWith((ref) async => [_context()]),
          sessionProvider.overrideWith((ref) => _session),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Actor'), findsOneWidget);
    expect(find.text('actor@example.test'), findsOneWidget);
    expect(find.text('PERFIL INSTITUCIONAL'), findsNothing);
    expect(find.text('SEGURIDAD'), findsNothing);
    expect(find.text('Hospital'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    expect(find.text('Administración institucional'), findsNothing);
    expect(find.text('HERRAMIENTAS'), findsOneWidget);
    expect(find.text('Dictado y redacción'), findsOneWidget);
    expect(find.byTooltip('Membresía activa'), findsOneWidget);
    final membership = tester.getSemantics(find.byTooltip('Membresía activa'));
    expect(membership.label, contains('Membresía activa'));
    expect(
      membership.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    expect(membership.getSemanticsData().flagsCollection.isButton, isFalse);
    final organizationCard = find.ancestor(
      of: find.text('Hospital'),
      matching: find.byType(ClinicalCard),
    );
    expect(organizationCard, findsOneWidget);
    expect(tester.getSize(organizationCard).height, greaterThanOrEqualTo(48));
    expect(
      tester.getCenter(find.text('HERRAMIENTAS')).dy,
      lessThan(tester.getCenter(find.text('Dictado y redacción')).dy),
    );
    expect(
      tester.getCenter(find.text('Dictado y redacción')).dy,
      lessThan(tester.getCenter(find.text('Cerrar sesión')).dy),
    );
    final header = tester.getRect(find.text('Actor'));
    final org = tester.getRect(find.text('Hospital'));
    expect(org.top - header.bottom, greaterThanOrEqualTo(18));
  });
  testWidgets(
    'settings falls back to profile when eligible contexts are empty',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith((ref) async => _context()),
            iamContextsProvider.overrideWith((ref) async => <IamContext>[]),
            sessionProvider.overrideWith((ref) => null),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hospital'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byTooltip('Membresía activa'), findsOneWidget);
    },
  );

  testWidgets('settings selects another active organization context', (
    tester,
  ) async {
    final first = _context();
    final second = const IamContext(
      organizationId: 'org-2',
      organizationName: 'Clínica',
      profileId: 'profile-1',
      displayName: 'Actor',
      profileStatus: 'active',
      membershipId: 'member-2',
      membershipStatus: 'active',
      permissions: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith((ref) async => first),
          iamContextsProvider.overrideWith((ref) async => [first, second]),
          currentSessionUserIdProvider.overrideWith((ref) => 'user-1'),
          sessionProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica').last);
    await tester.pumpAndSettle();
    expect(find.text('Clínica'), findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)))
          .read(selectedOrganizationProvider)
          ?.organizationId,
      'org-2',
    );
  });

  testWidgets(
    'settings excludes inactive organizations and shows membership status',
    (tester) async {
      final active = _context();
      final inactive = IamContext(
        organizationId: 'org-inactive',
        organizationName: 'Hospital inactivo',
        profileId: 'profile-1',
        displayName: 'Actor',
        profileStatus: 'active',
        membershipId: 'member-inactive',
        membershipStatus: 'inactive',
        permissions: const {},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith((ref) async => active),
            iamContextsProvider.overrideWith((ref) async => [active, inactive]),
            sessionProvider.overrideWith((ref) => null),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hospital inactivo'), findsNothing);
      final membership = tester.getSemantics(
        find.byTooltip('Membresía activa'),
      );
      expect(membership.label, contains('Membresía activa'));
      expect(
        membership.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
    },
  );
}

IamContext _context() => const IamContext(
  organizationId: 'org-1',
  organizationName: 'Hospital',
  profileId: 'profile-1',
  displayName: 'Actor',
  profileStatus: 'active',
  membershipId: 'member-1',
  membershipStatus: 'active',
  permissions: {},
);

final _session = Session.fromJson({
  'access_token': 'synthetic-token',
  'token_type': 'bearer',
  'user': {
    'id': 'user-1',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'actor@example.test',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
  },
});
