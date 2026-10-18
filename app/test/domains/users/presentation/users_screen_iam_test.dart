import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';

import '../../../support/authorization_refresh_override.dart';

import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/users/presentation/users_screen.dart';
import 'package:carer_record_app/domains/users/presentation/assignments_screen.dart';
import 'package:carer_record_app/core/design_system/anchored_selector.dart';
import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/core/design_system/clinical_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ClinicalToast.dismissAll);
  _toastTestWidgets(
    'assignment permission denial keeps the administrative title without clinical help',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith((ref) async => _context(const {})),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profesionales por hospitalización'), findsOneWidget);
      expect(find.textContaining('La asignación es necesaria'), findsNothing);
    },
  );

  _toastTestWidgets(
    'permission denial does not render member directory or create action',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith((ref) async => _context(const {})),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byTooltip('Volver a Ajustes'), findsOneWidget);
      expect(
        find.text('No tienes permiso para administrar miembros.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Agregar usuario'), findsNothing);
    },
  );

  _toastTestWidgets(
    'lists tenant members and never offers the current membership as a target',
    (tester) async {
      final fake = _FakeIamRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Otra persona'), findsOneWidget);
      expect(find.text('Yo'), findsNothing);
      expect(find.byTooltip('Agregar usuario'), findsOneWidget);
    },
  );

  _toastTestWidgets(
    'aligns heading and search with always-visible member cards',
    (tester) async {
      final fake = _FakeIamRepository();
      const second = IamMember(
        membershipId: 'membership-second',
        profileId: 'profile-second',
        displayName: 'Segunda persona',
        profileStatus: 'active',
        membershipStatus: 'active',
      );
      fake.assignmentsByMember = {
        _other.membershipId: [
          IamRoleAssignment(
            assignmentId: 'geometry-role',
            membershipId: _other.membershipId,
            roleId: _role.id,
            roleName: _role.name,
            protected: false,
            validFrom: DateTime.utc(2026),
          ),
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith(
              (ref) async =>
                  _context({'iam.membership.read', 'iam.membership.manage'}),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRepositoryProvider.overrideWithValue(fake),
            iamMembersProvider.overrideWith((ref) async => [_other, second]),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gestión de usuarios'), findsOneWidget);
      expect(find.byType(ClinicalCard), findsNWidgets(2));
      final appBarTitle = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Gestión de usuarios'),
      );
      final titleRect = tester.getRect(appBarTitle);
      final backRect = tester.getRect(find.byTooltip('Volver a Ajustes'));
      final searchRect = tester.getRect(find.byType(TextField));
      final cardRects = tester
          .widgetList<ClinicalCard>(find.byType(ClinicalCard))
          .toList();
      expect(cardRects, hasLength(2));
      final firstCardRect = tester.getRect(find.byType(ClinicalCard).first);
      expect(titleRect.center.dy, closeTo(backRect.center.dy, 0.1));
      expect(searchRect.left, closeTo(firstCardRect.left, 0.1));
      expect(
        searchRect.top - tester.getRect(find.byType(AppBar)).bottom,
        greaterThan(0),
      );
      expect(find.text('Gestión de usuarios'), findsOneWidget);
      expect(find.text('Otra persona'), findsOneWidget);
      expect(find.text('Segunda persona'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('ROLES ASIGNADOS'), findsOneWidget);
      expect(find.text('Suspender membresía'), findsAtLeastNWidgets(1));
      final sectionRect = tester.getRect(find.text('ROLES ASIGNADOS'));
      expect(sectionRect.left, greaterThan(firstCardRect.left));
      expect(
        tester
            .widgetList<Material>(find.byType(Material))
            .any((material) => material.color == Colors.white),
        isTrue,
      );
    },
  );

  _toastTestWidgets(
    'role selector excludes a role already assigned to the active member',
    (tester) async {
      final fake = _FakeIamRepository();
      fake.assignmentsByMember = {
        _other.membershipId: [
          IamRoleAssignment(
            assignmentId: 'active-role-assignment',
            membershipId: _other.membershipId,
            roleId: _role.id,
            roleName: _role.name,
            protected: false,
            validFrom: DateTime.utc(2026),
          ),
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.role.assign',
                'iam.role.read',
              }),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final selector = tester.widget<AnchoredSelector<String>>(
        find.byKey(ValueKey('role-${_other.membershipId}')),
      );
      final offeredRoleIds = selector.options
          .map((option) => option.value)
          .toSet();
      expect(offeredRoleIds, contains(_otherRole.id));
      expect(offeredRoleIds, isNot(contains(_role.id)));
    },
  );

  _toastTestWidgets(
    'new member uses institutional Edge payload with UUID v4 and no legacy enum',
    (tester) async {
      final fake = _FakeIamRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role]),
            iamRoleAssignmentsProvider.overrideWith((ref) async => {}),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        'Nuevo sintético',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'),
        'new@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña inicial'),
        'password-synthetic',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
      await tester.pumpAndSettle();
      expect(fake.created, isNotNull);
      expect(fake.created!['organizationId'], 'org-1');
      expect(fake.created!['roleId'], 'role-ordinary');
      expect(fake.created!['email'], 'new@example.test');
      expect(fake.created!.keys, contains('idempotencyKey'));
      expect(fake.created!.keys, isNot(contains('role')));
      expect(
        fake.created!['idempotencyKey'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );

  _toastTestWidgets(
    'created user joins the directory with the selected initial role',
    (tester) async {
      final fake = _FakeIamRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nueva incorporada'), findsNothing);

      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        'Nueva incorporada',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'),
        'nueva@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña inicial'),
        'password-synthetic',
      );
      await tester.tap(find.byType(AnchoredSelector<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal adicional').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
      await tester.pumpAndSettle();

      expect(fake.created!['roleId'], _otherRole.id);
      expect(fake.created!['displayName'], 'Nueva incorporada');
      expect(find.text('Usuario agregado.'), findsOneWidget);

      expect(find.text('Suspender membresía'), findsAtLeastNWidgets(1));
    },
  );

  _toastTestWidgets('incomplete user data never reaches the server', (
    tester,
  ) async {
    final fake = _FakeIamRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          iamContextProvider.overrideWith(
            (ref) async => _context({
              'iam.membership.read',
              'iam.membership.manage',
              'iam.role.assign',
            }),
          ),
          iamRolesProvider.overrideWith((ref) async => [_role]),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: _toastApp(home: const UsersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar usuario'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'no-es-un-correo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña inicial'),
      'corta',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
    await tester.pumpAndSettle();

    expect(fake.createAttempts, isEmpty);
    expect(find.text('Ingresa el nombre visible.'), findsOneWidget);
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(
      find.text('La contraseña debe tener al menos 12 caracteres.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Agregar usuario'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre visible'),
      'Persona válida',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'valida@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña inicial'),
      'password-synthetic',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
    await tester.pumpAndSettle();
    expect(fake.createAttempts, hasLength(1));
    expect(find.text('Ingresa el nombre visible.'), findsNothing);
  });

  _toastTestWidgets(
    'a failed creation is retried with the same idempotency key',
    (tester) async {
      final fake = _FakeIamRepository()..createFailures = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role]),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        'Reintento sintético',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'),
        'reintento@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña inicial'),
        'password-synthetic',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Agregar usuario'),
        findsOneWidget,
      );
      expect(
        find.text('No fue posible agregar el usuario. Puedes reintentar.'),
        findsOneWidget,
      );
      expect(fake.memberRows, hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, 'Agregar usuario'));
      await tester.pumpAndSettle();
      expect(fake.createAttempts, hasLength(2));
      expect(fake.createAttempts.first, fake.createAttempts.last);
      expect(find.text('Usuario agregado.'), findsOneWidget);

      expect(find.text('Suspender membresía'), findsAtLeastNWidgets(1));
    },
  );

  _toastTestWidgets(
    'a granted role stops being offered and leaves no stale selection',
    (tester) async {
      final fake = _FakeIamRepository()
        ..grantsAppearInAssignments = true
        ..failNextOperations.remove('grantRole');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_otherRole.name).last);
      await tester.pumpAndSettle();

      expect(fake.lastGrantedRoleId, _otherRole.id);
      expect(tester.takeException(), isNull);

      final selector = tester.widget<AnchoredSelector<String>>(
        find.byKey(ValueKey('role-${_other.membershipId}')),
      );
      expect(selector.selectedValue, isNull);
      expect(
        selector.options.map((option) => option.value),
        isNot(contains(_otherRole.id)),
      );
      expect(find.text(_otherRole.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets(
    'a panel with written data is never discarded without consent',
    (tester) async {
      final fake = _FakeIamRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role]),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo usuario'), findsNothing);
      expect(find.text('Descartar los datos'), findsNothing);

      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        'Escrito a medias',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar los datos'), findsOneWidget);

      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo usuario'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Nombre visible'),
        findsOneWidget,
      );
      expect(fake.createAttempts, isEmpty);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo usuario'), findsNothing);
      expect(fake.createAttempts, isEmpty);
    },
  );

  _toastTestWidgets(
    'create-user fields have spacing and fit a small viewport',
    (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = _FakeIamRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role]),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar usuario'));
      await tester.pumpAndSettle();

      Rect field(String label) =>
          tester.getRect(find.widgetWithText(TextFormField, label));
      expect(find.text('Mínimo 12 caracteres'), findsOneWidget);
      final name = field('Nombre visible');
      final email = field('Correo');
      final password = tester.getRect(
        find.widgetWithText(TextFormField, 'Contraseña inicial'),
      );
      final role = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<String> &&
              (widget.label as Text?)?.data == 'Rol inicial',
        ),
      );
      expect(
        email.top - name.bottom,
        greaterThanOrEqualTo(ClinicalSpacing.item),
      );
      expect(
        password.top - email.bottom,
        greaterThanOrEqualTo(ClinicalSpacing.item),
      );
      expect(
        role.top - password.bottom,
        greaterThanOrEqualTo(ClinicalSpacing.section),
      );
      expect(role.top, greaterThan(password.bottom));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Agregar usuario').last);
      await tester.tap(find.text('Agregar usuario').last);
      await tester.pumpAndSettle();
      expect(find.text('Ingresa el nombre visible.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets(
    'suspended membership remains visible and can be reactivated',
    (tester) async {
      final fake = _FakeIamRepository()
        ..failNextOperations.remove('updateMembership');
      const suspended = IamMember(
        membershipId: 'membership-suspended',
        profileId: 'profile-suspended',
        displayName: 'Persona suspendida',
        profileStatus: 'active',
        membershipStatus: 'suspended',
      );
      fake.assignmentsByMember = {
        suspended.membershipId: [
          IamRoleAssignment(
            assignmentId: 'historical-role-assignment',
            membershipId: suspended.membershipId,
            roleId: _role.id,
            roleName: 'Personal histórico',
            protected: false,
            validFrom: DateTime.utc(2026),
          ),
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamMembersProvider.overrideWith((ref) async => [suspended]),
            iamRolesProvider.overrideWith((ref) async => []),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Persona suspendida'), findsOneWidget);
      expect(find.text('Membresía suspendida'), findsOneWidget);
      expect(find.textContaining('Perfil GLOBAL'), findsNothing);
      expect(find.text('Organización seleccionada'), findsNothing);
      expect(find.text('Activos'), findsNothing);
      expect(find.text('Otros estados'), findsNothing);
      expect(find.text('Personal histórico'), findsOneWidget);
      expect(find.byTooltip('Revocar rol'), findsOneWidget);
      expect(find.text('Seleccionar rol'), findsNothing);
      expect(find.text('Activar membresía'), findsOneWidget);
      await tester.tap(find.text('Activar membresía'));
      await tester.pumpAndSettle();
      expect(fake.lastMembershipStatus, 'active');
      expect(fake.attempts['updateMembership'], hasLength(1));
    },
  );

  _toastTestWidgets(
    'role picker precedes assigned-role history with separate dates',
    (tester) async {
      final fake = _FakeIamRepository();
      fake.assignmentsByMember = {
        _other.membershipId: [
          IamRoleAssignment(
            assignmentId: 'revoked-role',
            membershipId: _other.membershipId,
            roleId: _role.id,
            roleName: 'Personal histórico',
            protected: false,
            validFrom: DateTime.utc(2026, 10, 1, 12),
            revokedAt: DateTime.utc(2026, 10, 2, 12),
          ),
          IamRoleAssignment(
            assignmentId: 'ended-role',
            membershipId: _other.membershipId,
            roleId: 'ended-role',
            roleName: 'Rol finalizado',
            protected: false,
            validFrom: DateTime.utc(2026, 10, 1, 12),
            validUntil: DateTime.utc(2026, 10, 2, 12),
          ),
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith(
              (ref) async =>
                  _context({'iam.membership.read', 'iam.role.assign'}),
            ),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final picker = tester.getRect(find.text('Seleccionar rol'));
      final heading = tester.getRect(find.text('ROLES ASIGNADOS'));
      expect(picker.bottom, lessThan(heading.top));
      expect(
        find.text(
          'Asignado el 01-10-2026 · 09:00\nRevocado el 02-10-2026 · 09:00',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Asignado el 01-10-2026 · 09:00\nFinalizada el 02-10-2026 · 09:00',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('→'), findsNothing);
    },
  );

  _toastTestWidgets('member search filters the directory by display name', (
    tester,
  ) async {
    final fake = _FakeIamRepository();
    const suspended = IamMember(
      membershipId: 'membership-search-suspended',
      profileId: 'profile-search-suspended',
      displayName: 'Persona suspendida',
      profileStatus: 'active',
      membershipStatus: 'suspended',
    );
    const active = IamMember(
      membershipId: 'membership-search-active',
      profileId: 'profile-search-active',
      displayName: 'Persona activa',
      profileStatus: 'active',
      membershipStatus: 'active',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          iamContextProvider.overrideWith(
            (ref) async => _context({'iam.membership.read'}),
          ),
          iamMembersProvider.overrideWith((ref) async => [active, suspended]),
          iamRolesProvider.overrideWith((ref) async => []),
          iamRoleAssignmentsProvider.overrideWith(
            (ref) async => const <String, List<IamRoleAssignment>>{},
          ),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: _toastApp(home: const UsersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gestión de usuarios'), findsOneWidget);
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Persona suspendida'), findsOneWidget);
    expect(find.text('Persona activa'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Persona suspen');
    await tester.pumpAndSettle();
    expect(find.text('Persona suspendida'), findsOneWidget);
    expect(find.text('Persona activa'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nadie');
    await tester.pumpAndSettle();
    expect(
      find.text('Ningún miembro coincide con la búsqueda.'),
      findsOneWidget,
    );
  });

  _toastTestWidgets(
    'search keeps every typed character and survives an authorization reload',
    (tester) async {
      const other = IamMember(
        membershipId: 'membership-keeps-typing',
        profileId: 'profile-keeps-typing',
        displayName: 'Otra persona',
        profileStatus: 'active',
        membershipStatus: 'active',
      );
      const second = IamMember(
        membershipId: 'membership-not-matching',
        profileId: 'profile-not-matching',
        displayName: 'Alba Ruiz',
        profileStatus: 'active',
        membershipStatus: 'active',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'iam.membership.read'}),
            ),
            iamMembersProvider.overrideWith((ref) async => [other, second]),
            iamRolesProvider.overrideWith((ref) async => []),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => const <String, List<IamRoleAssignment>>{},
            ),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();

      // Pulsación a pulsación, no el texto completo de una vez: reproduce el
      // defecto reportado, donde tras la primera letra el campo dejaba de
      // aceptar más escritura.
      var typed = '';
      for (final character in 'Otra'.split('')) {
        typed += character;
        tester.testTextInput.enterText(typed);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field).controller?.text,
          typed,
          reason: 'La pulsación de "$character" debe conservarse',
        );
        expect(find.text('Alba Ruiz'), findsNothing);
      }
      expect(find.text('Otra persona'), findsOneWidget);

      // La app invalida los permisos al entrar y tras cada acción administrada.
      // Ese refresco remonta la lista, pero no debe tocar el campo de búsqueda.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(UsersScreen)),
      );
      container.invalidate(iamContextProvider);
      container.invalidate(iamMembersProvider);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field).controller?.text, typed);
      expect(find.text('Otra persona'), findsOneWidget);
      expect(
        tester.testTextInput.hasAnyClients,
        isTrue,
        reason: 'El campo debe conservar el foco tras la recarga de permisos',
      );
    },
  );

  _toastTestWidgets(
    'membership and ordinary role actions call audited operation boundaries',
    (tester) async {
      final fake = _FakeIamRepository();
      fake.assignmentsByMember = {
        _other.membershipId: [
          IamRoleAssignment(
            assignmentId: 'role-assignment-1',
            membershipId: _other.membershipId,
            roleId: _role.id,
            roleName: _role.name,
            protected: false,
            validFrom: DateTime.utc(2026),
          ),
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'iam.membership.read',
                'iam.membership.manage',
                'iam.role.assign',
              }),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspender membresía'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar operación'), findsOneWidget);
      expect(
        find.text('No se pudo confirmar la suspensión de la membresía.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text('No se pudo confirmar la suspensión de la membresía.'),
        findsNothing,
      );
      expect(
        find.textContaining('El resultado podría haberse aplicado'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['updateMembership']!);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final firstKey = fake.attempts['updateMembership']!.first.idempotencyKey;
      await tester.tap(find.text('Suspender membresía'));
      await tester.pumpAndSettle();
      expect(
        fake.attempts['updateMembership']!.last.idempotencyKey,
        isNot(firstKey),
      );
      expect(fake.lastMembershipStatus, 'suspended');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Revocar rol'));
      await tester.pumpAndSettle();
      expect(fake.attempts['revokeRole'], hasLength(1));
      expect(find.text('Reintentar operación'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['revokeRole']!);
      expect(fake.lastRevokedRoleId, 'role-assignment-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final revokeRoleKey = fake.attempts['revokeRole']!.first.idempotencyKey;
      await tester.tap(find.byTooltip('Revocar rol'));
      await tester.pumpAndSettle();
      expect(
        fake.attempts['revokeRole']!.last.idempotencyKey,
        isNot(revokeRoleKey),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal adicional').last);
      await tester.pumpAndSettle();
      expect(find.text('Reintentar operación'), findsOneWidget);
      expect(
        find.text('No se pudo confirmar la asignación del rol.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text('No se pudo confirmar la asignación del rol.'),
        findsNothing,
      );
      expect(
        find.textContaining('El resultado podría haberse aplicado'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['grantRole']!, hasValidFrom: true);
      expect(fake.lastGrantedRoleId, 'role-additional');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final grantRoleKey = fake.attempts['grantRole']!.first.idempotencyKey;
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal adicional').last);
      await tester.pumpAndSettle();
      expect(
        fake.attempts['grantRole']!.last.idempotencyKey,
        isNot(grantRoleKey),
      );
    },
  );

  _toastTestWidgets(
    'assignment screen grants only eligible membership and revokes by assignment id',
    (tester) async {
      final fake = _FakeIamRepository();
      fake.careRows = [
        CareAssignmentRecord(
          hospitalizationId: 'episode-1000',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
        ),
        CareAssignmentRecord(
          hospitalizationId: 'episode-2000',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
        ),
      ];
      final overrides = [
        authorizationRefreshOverride,
        iamContextProvider.overrideWith(
          (ref) async => _context({'clinical.assignment.manage'}),
        ),
        careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
        eligibleMembersProvider.overrideWith(
          (ref) async => const [
            EligibleMember(
              membershipId: 'eligible-1',
              displayName: 'Profesional elegible',
            ),
          ],
        ),
        iamRepositoryProvider.overrideWithValue(fake),
      ];
      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('revocation-case'),
          overrides: overrides,
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Profesionales por hospitalización'),
      );
      expect(title, findsOneWidget);
      expect(find.text('Profesionales por hospitalización'), findsOneWidget);
      expect(find.textContaining('La asignación es necesaria'), findsNothing);
      final titleRect = tester.getRect(title);
      final backRect = tester.getRect(find.byTooltip('Volver a Ajustes'));
      expect(titleRect.center.dy, closeTo(backRect.center.dy, 0.1));
      final searchRect = tester.getRect(find.byType(TextField));
      final appBarRect = tester.getRect(find.byType(AppBar));
      expect(searchRect.top, greaterThan(appBarRect.bottom));
      final firstCardRect = tester.getRect(find.byType(ClinicalCard).first);
      expect(searchRect.left, closeTo(firstCardRect.left, 0.1));
      expect(find.textContaining('episode-1000'), findsOneWidget);
      expect(find.textContaining('episode-2000'), findsOneWidget);
      final copyButtons = find.byTooltip('Copiar identificador del episodio');
      expect(copyButtons, findsNWidgets(2));
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      try {
        await tester.tap(copyButtons.first);
        await tester.pump();
        expect(copiedText, 'episode-1000');
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      }
      await tester.tap(find.text('Asignar profesional').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar operación'), findsOneWidget);
      expect(
        find.text(
          'No se pudo confirmar la asignación del profesional a la hospitalización.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text(
          'No se pudo confirmar la asignación del profesional a la hospitalización.',
        ),
        findsNothing,
      );
      expect(
        find.textContaining('El resultado podría haberse aplicado'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      _expectSameAttempt(
        fake.attempts['grantCareAssignment']!,
        hasValidFrom: true,
      );
      expect(fake.lastCareGrantMembership, 'eligible-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final grantCareKey =
          fake.attempts['grantCareAssignment']!.first.idempotencyKey;
      await tester.tap(find.text('Asignar profesional').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar'));
      await tester.pumpAndSettle();
      expect(
        fake.attempts['grantCareAssignment']!.last.idempotencyKey,
        isNot(grantCareKey),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      fake.careRows = [
        CareAssignmentRecord(
          hospitalizationId: 'episode-1000',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
          assignmentId: 'care-1',
          membershipId: 'eligible-1',
          validFrom: DateTime.utc(2026, 10, 1),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('revocation-case-updated'),
          overrides: overrides,
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quitar acceso'));
      await tester.pumpAndSettle();
      expect(fake.attempts['revokeCareAssignment'], isNull);
      expect(
        find.textContaining('se quitará el acceso a la información'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.attempts['revokeCareAssignment'], isNull);
      await tester.tap(find.byTooltip('Quitar acceso'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Quitar acceso'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar operación'), findsOneWidget);
      expect(
        find.text(
          'No se pudo confirmar la revocación del acceso a la hospitalización.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text(
          'No se pudo confirmar la revocación del acceso a la hospitalización.',
        ),
        findsNothing,
      );
      expect(
        find.textContaining('El resultado podría haberse aplicado'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['revokeCareAssignment']!);
      expect(fake.lastCareRevokeId, 'care-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final revokeCareKey =
          fake.attempts['revokeCareAssignment']!.first.idempotencyKey;
      await tester.tap(find.byTooltip('Quitar acceso'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Quitar acceso'));
      await tester.pumpAndSettle();
      expect(
        fake.attempts['revokeCareAssignment']!.last.idempotencyKey,
        isNot(revokeCareKey),
      );
    },
  );

  _toastTestWidgets(
    'inactive targets are absent from care-assignment choices',
    (tester) async {
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-synthetic',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'clinical.assignment.manage'}),
            ),
            careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Asignar profesional'), findsOneWidget);
      await tester.tap(find.text('Asignar profesional'));
      await tester.pumpAndSettle();
      expect(find.text('Asignar profesional'), findsOneWidget);
      expect(find.text('Persona suspendida'), findsNothing);
      expect(find.text('No hay profesionales elegibles.'), findsOneWidget);
      expect(fake.attempts['grantCareAssignment'], isNull);
    },
  );

  _toastTestWidgets('care cards distinguish admitted and discharged status', (
    tester,
  ) async {
    final fake = _FakeIamRepository()
      ..careRows = [
        CareAssignmentRecord(
          hospitalizationId: 'episode-admitted',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
        ),
        CareAssignmentRecord(
          hospitalizationId: 'episode-discharged',
          status: 'discharged',
          admittedAt: DateTime.utc(2026, 10, 1),
        ),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith(
            (ref) async => _context({'clinical.assignment.manage'}),
          ),
          careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
          eligibleMembersProvider.overrideWith((ref) async => const []),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: _toastApp(home: const AssignmentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hospitalización vigente'), findsOneWidget);
    expect(find.text('Hospitalización egresada'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _toastTestWidgets(
    'long care status fits a narrow viewport without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-long-status',
            status: 'temporarily_absent',
            admittedAt: DateTime.utc(2026, 10, 1),
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'clinical.assignment.manage'}),
            ),
            careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Hospitalización con ausencia temporal'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets(
    'episode groups assignments and keeps add/revoke scoped by episode',
    (tester) async {
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-a',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
            assignmentId: 'care-one',
            membershipId: 'member-one',
            validFrom: DateTime.utc(2026, 10, 1),
          ),
          CareAssignmentRecord(
            hospitalizationId: 'episode-b',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
          ),
        ];
      final members = const [
        EligibleMember(
          membershipId: 'member-one',
          displayName: 'Profesional uno',
        ),
        EligibleMember(
          membershipId: 'member-two',
          displayName: 'Profesional dos',
        ),
      ];
      Future<void> pump() async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authorizationRefreshOverride,
              iamContextProvider.overrideWith(
                (ref) async => _context({'clinical.assignment.manage'}),
              ),
              careAssignmentsProvider.overrideWith(
                (ref) async => fake.careRows,
              ),
              eligibleMembersProvider.overrideWith((ref) async => members),
              iamRepositoryProvider.overrideWithValue(fake),
            ],
            child: _toastApp(home: const AssignmentsScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump();
      expect(find.textContaining('episode-a'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('episode-b'), findsOneWidget);
      expect(find.text('Asignar profesional'), findsNWidgets(2));
      expect(find.text('Profesional uno'), findsOneWidget);

      await tester.tap(find.text('Asignar profesional').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profesional dos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      expect(fake.lastCareGrantHospitalization, 'episode-a');
      expect(fake.lastCareGrantMembership, 'member-two');

      fake.careRows = [
        ...fake.careRows,
        CareAssignmentRecord(
          hospitalizationId: 'episode-a',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
          assignmentId: 'care-two',
          membershipId: 'member-two',
          validFrom: DateTime.utc(2026, 10, 2),
        ),
      ];
      await pump();
      expect(find.text('Profesional uno'), findsOneWidget);
      expect(find.text('Profesional dos'), findsOneWidget);
      expect(find.text('Asignar profesional'), findsAtLeastNWidgets(1));
      await tester.tap(find.byTooltip('Quitar acceso').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Quitar acceso'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      expect(fake.lastCareRevokeId, 'care-two');
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('episode-b'), findsOneWidget);
      expect(
        fake.careRows.where((row) => row.assignmentId == 'care-one'),
        hasLength(1),
      );
    },
  );

  _toastTestWidgets(
    'patient name requires both effective clinical read permissions',
    (tester) async {
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-1000',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
          ),
        ]
        ..patientNames = {'episode-1000': 'Ada Lovelace'};
      var reads = 0;
      var scopeKey = 0;
      fake.onCensusRead = () => reads++;
      Future<void> pumpFor(Set<String> permissions) async {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('clinical-read-${scopeKey++}'),
            overrides: [
              authorizationRefreshOverride,
              iamContextProvider.overrideWith(
                (ref) async => _context(permissions),
              ),
              careAssignmentsProvider.overrideWith(
                (ref) async => fake.careRows,
              ),
              eligibleMembersProvider.overrideWith((ref) async => const []),
              iamRepositoryProvider.overrideWithValue(fake),
            ],
            child: _toastApp(home: const AssignmentsScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpFor({'clinical.assignment.manage'});
      expect(reads, 0);
      expect(find.textContaining('Ada Lovelace'), findsNothing);
      await pumpFor({
        'clinical.assignment.manage',
        'clinical.census.read',
        'clinical.patient.read',
      });
      expect(reads, 1);
      expect(find.textContaining('Ada Lovelace'), findsOneWidget);
    },
  );

  _toastTestWidgets(
    'assignment title, search and episode cards share page gutter',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = _FakeIamRepository()
        ..careRows = [
          for (final id in ['episode-one-${'a' * 48}', 'episode-two'])
            CareAssignmentRecord(
              hospitalizationId: id,
              status: 'admitted',
              admittedAt: DateTime.utc(2026, 10, 1),
            ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'clinical.assignment.manage'}),
            ),
            careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final titleFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Profesionales por hospitalización'),
      );
      expect(titleFinder, findsOneWidget);
      expect(find.text('Profesionales por hospitalización'), findsOneWidget);
      final titleRect = tester.getRect(titleFinder);
      final backRect = tester.getRect(find.byTooltip('Volver a Ajustes'));
      final searchRect = tester.getRect(find.byType(TextField));
      expect(find.textContaining('Sin acceso a nombres'), findsNothing);
      expect(titleRect.center.dy, closeTo(backRect.center.dy, 0.1));
      expect(
        searchRect.top,
        greaterThan(tester.getRect(find.byType(AppBar)).bottom),
      );
      final cards = find.byType(ClinicalCard);
      expect(cards, findsNWidgets(2));
      final firstRect = tester.getRect(cards.first);
      final secondRect = tester.getRect(cards.last);
      expect(firstRect.left, searchRect.left);
      expect(secondRect.left, searchRect.left);
      expect(find.textContaining('episode-one-${'a' * 48}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets(
    'care card uses spacing instead of badges, leading person icons and dividers',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [
        CareAssignmentRecord(
          hospitalizationId: 'episode-synthetic',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1, 12),
          assignmentId: 'care-active',
          membershipId: 'member-active',
          assigneeDisplayName: 'Profesional vigente',
          validFrom: DateTime.utc(2026, 10, 1, 12),
        ),
        CareAssignmentRecord(
          hospitalizationId: 'episode-synthetic',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1, 12),
          assignmentId: 'care-revoked',
          membershipId: 'member-revoked',
          assigneeDisplayName: 'Profesional histórico',
          validFrom: DateTime.utc(2026, 10, 1, 12),
          revokedAt: DateTime.utc(2026, 10, 2, 12),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'clinical.assignment.manage'}),
            ),
            careAssignmentsProvider.overrideWith((ref) async => rows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('admitted'), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(find.text('Admisión 01-10-2026 · 09:00'), findsOneWidget);
      expect(find.text('PROFESIONALES ASIGNADOS'), findsOneWidget);
      final admission = tester.getRect(
        find.text('Admisión 01-10-2026 · 09:00'),
      );
      final episodeId = tester.getRect(
        find.textContaining('episode-synthetic'),
      );
      final professionals = tester.getRect(
        find.text('PROFESIONALES ASIGNADOS'),
      );
      expect(episodeId.top - admission.bottom, lessThan(40));
      expect(professionals.top - episodeId.bottom, lessThan(40));
      expect(find.text('Profesional vigente'), findsOneWidget);
      expect(find.text('Profesional histórico'), findsOneWidget);
      expect(find.text('Asignado el 01-10-2026 · 09:00'), findsNWidgets(2));
      expect(find.text('Revocado el 02-10-2026 · 09:00'), findsOneWidget);
      final activeName = tester.getRect(find.text('Profesional vigente'));
      final activeAssignment = tester.getRect(
        find.text('Asignado el 01-10-2026 · 09:00').first,
      );
      final nextName = tester.getRect(find.text('Profesional histórico'));
      expect(activeAssignment.top - activeName.bottom, lessThan(16));
      expect(nextName.top - activeAssignment.bottom, lessThan(28));
      expect(find.textContaining('→'), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.byType(Divider), findsNothing);
      expect(
        find.byTooltip('Copiar identificador del episodio'),
        findsOneWidget,
      );
      final revoke = find.byTooltip('Quitar acceso');
      expect(revoke, findsOneWidget);
      expect(find.byIcon(Icons.person_remove_outlined), findsOneWidget);
      final revokeRect = tester.getRect(revoke);
      expect((revokeRect.center.dy - activeName.center.dy).abs(), lessThan(16));
      expect(find.text('Asignar profesional'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets(
    'reassigned user shows chronological periods under one name',
    (tester) async {
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-reassignment',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
            assignmentId: 'care-current',
            membershipId: 'same-member',
            assigneeDisplayName: 'Profesional recurrente',
            validFrom: DateTime.utc(2026, 10, 3, 12),
          ),
          CareAssignmentRecord(
            hospitalizationId: 'episode-reassignment',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1),
            assignmentId: 'care-old',
            membershipId: 'same-member',
            assigneeDisplayName: 'Profesional recurrente',
            validFrom: DateTime.utc(2026, 10, 1, 12),
            revokedAt: DateTime.utc(2026, 10, 2, 12),
          ),
        ];
      fake.failNextOperations.remove('revokeCareAssignment');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({'clinical.assignment.manage'}),
            ),
            careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profesional recurrente'), findsOneWidget);
      final assignedBefore = tester.getTopLeft(
        find.text('Asignado el 01-10-2026 · 09:00'),
      );
      final revoked = tester.getTopLeft(
        find.text('Revocado el 02-10-2026 · 09:00'),
      );
      final assignedAgain = tester.getTopLeft(
        find.text('Asignado el 03-10-2026 · 09:00'),
      );
      expect(assignedBefore.dy, lessThan(revoked.dy));
      expect(revoked.dy, lessThan(assignedAgain.dy));
      expect(find.byTooltip('Quitar acceso'), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar acceso'));
      await tester.pumpAndSettle();
      expect(fake.attempts['revokeCareAssignment'], isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Quitar acceso'));
      await tester.pumpAndSettle();
      expect(fake.lastCareRevokeId, 'care-current');
      expect(tester.takeException(), isNull);
    },
  );

  _toastTestWidgets('one user action can revoke an older unrevoked period', (
    tester,
  ) async {
    final fake = _FakeIamRepository()
      ..careRows = [
        CareAssignmentRecord(
          hospitalizationId: 'episode-history',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
          assignmentId: 'care-current',
          membershipId: 'same-member',
          assigneeDisplayName: 'Usuario con historial',
          validFrom: DateTime.utc(2026, 10, 3, 12),
        ),
        CareAssignmentRecord(
          hospitalizationId: 'episode-history',
          status: 'admitted',
          admittedAt: DateTime.utc(2026, 10, 1),
          assignmentId: 'care-older',
          membershipId: 'same-member',
          assigneeDisplayName: 'Usuario con historial',
          validFrom: DateTime.utc(2026, 10, 1, 12),
          validUntil: DateTime.utc(2026, 10, 2, 12),
        ),
      ];
    fake.failNextOperations.remove('revokeCareAssignment');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authorizationRefreshOverride,
          iamContextProvider.overrideWith(
            (ref) async => _context({'clinical.assignment.manage'}),
          ),
          careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
          eligibleMembersProvider.overrideWith((ref) async => const []),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: _toastApp(home: const AssignmentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Quitar acceso'), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar acceso'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar asignación'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(fake.attempts['revokeCareAssignment'], isNull);

    await tester.tap(find.byTooltip('Quitar acceso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asignado el 01-10-2026 · 09:00').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('iniciada el 01-10-2026 · 09:00'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Quitar acceso'));
    await tester.pumpAndSettle();
    expect(fake.lastCareRevokeId, 'care-older');
    expect(tester.takeException(), isNull);
  });

  _toastTestWidgets(
    'care history preserves the assignee name and filters displayed episodes locally',
    (tester) async {
      final fake = _FakeIamRepository()
        ..careRows = [
          CareAssignmentRecord(
            hospitalizationId: 'episode-with-name',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 1, 12),
            assignmentId: 'care-suspended',
            membershipId: 'membership-suspended',
            validFrom: DateTime.utc(2026, 10, 1, 12),
            assigneeDisplayName: 'Profesional histórico',
            assigneeMembershipStatus: 'suspended',
          ),
          CareAssignmentRecord(
            hospitalizationId: 'episode-without-name',
            status: 'admitted',
            admittedAt: DateTime.utc(2026, 10, 2, 12),
          ),
        ]
        ..patientNames = {'episode-with-name': 'Ada Lovelace'};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async => _context({
                'clinical.assignment.manage',
                'clinical.census.read',
                'clinical.patient.read',
              }),
            ),
            careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
            eligibleMembersProvider.overrideWith((ref) async => const []),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profesional histórico'), findsOneWidget);
      expect(
        find.textContaining('Sin acceso · Membresía suspendida'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Asignado el 01-10-2026 · 09:00'),
        findsOneWidget,
      );
      expect(find.textContaining('Admisión'), findsNWidgets(2));
      expect(find.textContaining('Ingreso'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre o UUID de hospitalización'),
        'ada',
      );
      await tester.pump();
      expect(find.textContaining('episode-with-name'), findsOneWidget);
      expect(find.textContaining('episode-without-name'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre o UUID de hospitalización'),
        'without-name',
      );
      await tester.pump();
      expect(find.textContaining('episode-with-name'), findsNothing);
      expect(find.textContaining('episode-without-name'), findsOneWidget);
    },
  );

  _toastTestWidgets(
    'transient membership failure persists a retry after toast expiry',
    (tester) async {
      final fake = _FakeIamRepository()
        ..failNextOperations.add('updateMembership');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authorizationRefreshOverride,
            iamContextProvider.overrideWith(
              (ref) async =>
                  _context({'iam.membership.read', 'iam.membership.manage'}),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: _toastApp(home: const UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspender membresía'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar operación'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Reintentar operación'));
      await tester.pumpAndSettle();
      expect(fake.attempts['updateMembership'], hasLength(2));
      _expectSameAttempt(fake.attempts['updateMembership']!);
    },
  );
}

void _toastTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester) test,
) {
  testWidgets(description, (tester) async {
    ClinicalToast.dismissAll();
    try {
      await test(tester);
    } finally {
      ClinicalToast.dismissAll();
      await tester.pump(const Duration(milliseconds: 300));
      ClinicalToast.dismissAll();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    }
  });
}

Widget _toastApp({required Widget home}) => MaterialApp(
  builder: (context, child) => ClinicalToastHost(child: child!),
  home: home,
);

void _expectSameAttempt(
  List<AdminOperationAttempt> attempts, {
  bool hasValidFrom = false,
}) {
  expect(attempts.length, greaterThanOrEqualTo(2));
  expect(attempts[0].idempotencyKey, attempts[1].idempotencyKey);
  expect(attempts[0].validFrom, attempts[1].validFrom);
  if (hasValidFrom) {
    expect(attempts.first.validFrom, isNotNull);
    expect(attempts.first.validFrom!.isUtc, isTrue);
  } else {
    expect(attempts.first.validFrom, isNull);
  }
}

IamContext _context(Set<String> permissions) => IamContext(
  organizationId: 'org-1',
  organizationName: 'Hospital sintético',
  profileId: 'profile-self',
  displayName: 'Yo',
  profileStatus: 'active',
  membershipId: 'membership-self',
  membershipStatus: 'active',
  permissions: permissions,
);

const _other = IamMember(
  membershipId: 'membership-other',
  profileId: 'profile-other',
  displayName: 'Otra persona',
  profileStatus: 'active',
  membershipStatus: 'active',
);
const _role = IamRole(
  id: 'role-ordinary',
  name: 'Personal',
  protected: false,
  permissions: {'clinical.assigned.read'},
);
const _otherRole = IamRole(
  id: 'role-additional',
  name: 'Personal adicional',
  protected: false,
  permissions: {'clinical.timeline.read'},
);

class _FakeIamRepository implements IamRepository {
  Map<String, dynamic>? created;
  List<String> createAttempts = [];
  int createFailures = 0;
  List<IamMember> memberRows = [_other];
  List<IamRole> roleCatalog = [_role, _otherRole];
  bool grantsAppearInAssignments = false;
  Map<String, List<IamRoleAssignment>> assignmentsByMember = {};
  String? lastMembershipStatus;
  String? lastGrantedRoleId;
  String? lastRevokedRoleId;
  String? lastCareGrantMembership;
  String? lastCareGrantHospitalization;
  String? lastCareRevokeId;
  List<CareAssignmentRecord> careRows = [];
  Map<String, String> patientNames = {};
  void Function()? onCensusRead;
  final Set<String> failNextOperations = {
    'updateMembership',
    'grantRole',
    'revokeRole',
    'grantCareAssignment',
    'revokeCareAssignment',
  };
  final Map<String, List<AdminOperationAttempt>> attempts = {};

  @override
  Future<List<IamPermission>> delegablePermissions() async => const [];

  @override
  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  }) async => const AdminOperationResult(
    success: true,
    code: 'permissions_replaced',
    targetId: null,
    replayed: false,
  );

  void _recordAttempt(String operation, AdminOperationAttempt attempt) {
    (attempts[operation] ??= []).add(attempt);
    if (failNextOperations.remove(operation)) {
      throw StateError('synthetic transient failure: $operation');
    }
  }

  @override
  Future<List<IamContext>> currentContexts() async => [
    _context({'iam.membership.read'}),
  ];
  @override
  Future<List<IamMember>> members(String organizationId) async => memberRows;
  @override
  Future<List<IamRole>> roles(String organizationId) async => [_role];
  @override
  Future<Map<String, List<IamRoleAssignment>>> roleAssignments(
    String organizationId,
  ) async => assignmentsByMember;
  @override
  Future<void> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
    required String idempotencyKey,
  }) async {
    created = {
      'organizationId': organizationId,
      'email': email,
      'password': password,
      'displayName': displayName,
      'roleId': roleId,
      'idempotencyKey': idempotencyKey,
    };
    createAttempts.add(idempotencyKey);
    if (createFailures > 0) {
      createFailures--;
      throw StateError('synthetic transient create failure');
    }
    memberRows = [
      ...memberRows,
      IamMember(
        membershipId: 'membership-created-$idempotencyKey',
        profileId: 'profile-created-$idempotencyKey',
        displayName: displayName,
        profileStatus: 'active',
        membershipStatus: 'active',
      ),
    ];
  }

  @override
  Future<AdminOperationResult> updateMembership({
    required String organizationId,
    required String membershipId,
    required String status,
    required AdminOperationAttempt attempt,
  }) async {
    _recordAttempt('updateMembership', attempt);
    lastMembershipStatus = status;
    return const AdminOperationResult(
      success: true,
      code: 'updated',
      targetId: 'membership-other',
      replayed: false,
    );
  }

  @override
  Future<AdminOperationResult> grantRole({
    required String organizationId,
    required String membershipId,
    required String roleId,
    required AdminOperationAttempt attempt,
  }) async {
    _recordAttempt('grantRole', attempt);
    lastGrantedRoleId = roleId;
    if (grantsAppearInAssignments) {
      final granted = roleCatalog.firstWhere((role) => role.id == roleId);
      assignmentsByMember[membershipId] = [
        ...?assignmentsByMember[membershipId],
        IamRoleAssignment(
          assignmentId: 'assignment-role',
          membershipId: membershipId,
          roleId: roleId,
          roleName: granted.name,
          protected: false,
          validFrom: attempt.validFrom ?? DateTime.utc(2026),
        ),
      ];
    }
    return const AdminOperationResult(
      success: true,
      code: 'granted',
      targetId: 'assignment-role',
      replayed: false,
    );
  }

  @override
  Future<AdminOperationResult> revokeRole({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) async {
    _recordAttempt('revokeRole', attempt);
    lastRevokedRoleId = assignmentId;
    return const AdminOperationResult(
      success: true,
      code: 'revoked',
      targetId: 'assignment-role',
      replayed: false,
    );
  }

  @override
  Future<List<CareAssignmentRecord>> assignments(String organizationId) async =>
      careRows;
  @override
  Future<Map<String, String>> censusPatientNames(String organizationId) async {
    onCensusRead?.call();
    return patientNames;
  }

  @override
  Future<List<EligibleMember>> eligibleMembers(String organizationId) async =>
      [];
  @override
  Future<AdminOperationResult> grantCareAssignment({
    required String organizationId,
    required String hospitalizationId,
    required String membershipId,
    required AdminOperationAttempt attempt,
  }) async {
    _recordAttempt('grantCareAssignment', attempt);
    lastCareGrantMembership = membershipId;
    lastCareGrantHospitalization = hospitalizationId;
    return const AdminOperationResult(
      success: true,
      code: 'granted',
      targetId: 'assignment-care',
      replayed: false,
    );
  }

  @override
  Future<AdminOperationResult> revokeCareAssignment({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) async {
    _recordAttempt('revokeCareAssignment', attempt);
    lastCareRevokeId = assignmentId;
    return const AdminOperationResult(
      success: true,
      code: 'revoked',
      targetId: 'assignment-care',
      replayed: false,
    );
  }
}
