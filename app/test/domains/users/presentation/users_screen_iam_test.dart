import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/users/presentation/users_screen.dart';
import 'package:carer_record_app/domains/users/presentation/assignments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'permission denial does not render member directory or create action',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith((ref) async => _context(const {})),
          ],
          child: const MaterialApp(home: UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byTooltip('Volver a Ajustes'), findsOneWidget);
      expect(
        find.text('No tienes permiso para administrar miembros.'),
        findsOneWidget,
      );
      expect(find.text('Agregar miembro'), findsNothing);
    },
  );

  testWidgets(
    'lists tenant members and never offers the current membership as a target',
    (tester) async {
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
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Otra persona'), findsOneWidget);
      expect(find.text('Yo'), findsNothing);
      expect(find.text('Agregar miembro'), findsOneWidget);
    },
  );

  testWidgets(
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
            iamContextProvider.overrideWith(
              (ref) async =>
                  _context({'iam.membership.read', 'iam.role.assign'}),
            ),
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role, _otherRole]),
            iamRoleAssignmentsProvider.overrideWith(
              (ref) async => fake.assignmentsByMember,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(_other.membershipId)));
      await tester.pumpAndSettle();

      final selector = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(ValueKey('role-${_other.membershipId}')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      final offeredRoleIds = selector.items!.map((item) => item.value).toSet();
      expect(offeredRoleIds, contains(_otherRole.id));
      expect(offeredRoleIds, isNot(contains(_role.id)));
    },
  );

  testWidgets(
    'new member uses institutional Edge payload with UUID v4 and no legacy enum',
    (tester) async {
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
            iamMembersProvider.overrideWith((ref) async => [_other]),
            iamRolesProvider.overrideWith((ref) async => [_role]),
            iamRoleAssignmentsProvider.overrideWith((ref) async => {}),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar miembro'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre visible'),
        'Nuevo sintético',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Correo'),
        'new@example.test',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Contraseña inicial (mínimo 12 caracteres)',
        ),
        'password-synthetic',
      );
      await tester.tap(find.text('Crear'));
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

  testWidgets('suspended membership remains visible and can be reactivated', (
    tester,
  ) async {
    final fake =
        _FakeIamRepository()..failNextOperations.remove('updateMembership');
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
        child: const MaterialApp(home: UsersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Persona suspendida'), findsOneWidget);
    expect(find.text('Membresía suspendida'), findsOneWidget);
    expect(find.textContaining('Perfil GLOBAL'), findsNothing);
    expect(find.text('Organización seleccionada'), findsNothing);
    expect(find.text('Activos'), findsNothing);
    expect(find.text('Otros estados'), findsNothing);
    await tester.tap(find.text('Persona suspendida'));
    await tester.pumpAndSettle();
    expect(find.text('Personal histórico'), findsOneWidget);
    expect(find.byTooltip('Revocar rol'), findsOneWidget);
    expect(find.text('Asignar rol ordinario'), findsNothing);
    expect(find.text('Activar membresía'), findsOneWidget);
    await tester.tap(find.text('Activar membresía'));
    await tester.pumpAndSettle();
    expect(fake.lastMembershipStatus, 'active');
    expect(fake.attempts['updateMembership'], hasLength(1));
  });

  testWidgets('member search filters the directory by display name', (
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
        child: const MaterialApp(home: UsersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gestión de usuarios'), findsOneWidget);
    expect(find.text('Buscar por nombre'), findsOneWidget);
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

  testWidgets(
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
          child: const MaterialApp(home: UsersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otra persona'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspender membresía'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['updateMembership']!);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otra persona'));
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
      await tester.tap(find.text('Otra persona'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Revocar rol'));
      await tester.pumpAndSettle();
      expect(fake.attempts['revokeRole'], hasLength(1));
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['revokeRole']!);
      expect(fake.lastRevokedRoleId, 'role-assignment-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otra persona'));
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
      await tester.tap(find.text('Otra persona'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal adicional').last);
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['grantRole']!, hasValidFrom: true);
      expect(fake.lastGrantedRoleId, 'role-additional');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otra persona'));
      await tester.pumpAndSettle();
      final grantRoleKey = fake.attempts['grantRole']!.first.idempotencyKey;
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal adicional').last);
      await tester.pumpAndSettle();
      expect(
        fake.attempts['grantRole']!.last.idempotencyKey,
        isNot(grantRoleKey),
      );
    },
  );

  testWidgets(
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
          child: const MaterialApp(home: AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
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
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
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
          child: const MaterialApp(home: AssignmentsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Revocar asignación'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      _expectSameAttempt(fake.attempts['revokeCareAssignment']!);
      expect(fake.lastCareRevokeId, 'care-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final revokeCareKey =
          fake.attempts['revokeCareAssignment']!.first.idempotencyKey;
      await tester.tap(find.byTooltip('Revocar asignación'));
      await tester.pumpAndSettle();
      expect(
        fake.attempts['revokeCareAssignment']!.last.idempotencyKey,
        isNot(revokeCareKey),
      );
    },
  );

  testWidgets('inactive targets are absent from care-assignment choices', (
    tester,
  ) async {
    final fake =
        _FakeIamRepository()
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
          iamContextProvider.overrideWith(
            (ref) async => _context({'clinical.assignment.manage'}),
          ),
          careAssignmentsProvider.overrideWith((ref) async => fake.careRows),
          eligibleMembersProvider.overrideWith((ref) async => const []),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: AssignmentsScreen()),
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
  });

  testWidgets(
    'episode groups assignments and keeps add/revoke scoped by episode',
    (tester) async {
      final fake =
          _FakeIamRepository()
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
              iamContextProvider.overrideWith(
                (ref) async => _context({'clinical.assignment.manage'}),
              ),
              careAssignmentsProvider.overrideWith(
                (ref) async => fake.careRows,
              ),
              eligibleMembersProvider.overrideWith((ref) async => members),
              iamRepositoryProvider.overrideWithValue(fake),
            ],
            child: const MaterialApp(home: AssignmentsScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump();
      expect(find.textContaining('episode-a'), findsOneWidget);
      expect(find.textContaining('episode-b'), findsOneWidget);
      expect(find.text('Asignar profesional'), findsNWidgets(2));
      expect(find.text('Profesional uno'), findsOneWidget);

      await tester.tap(find.text('Asignar profesional').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
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
      expect(find.text('Asignar profesional'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Revocar asignación').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(fake.lastCareRevokeId, 'care-two');
      expect(find.textContaining('episode-b'), findsOneWidget);
      expect(
        fake.careRows.where((row) => row.assignmentId == 'care-one'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'patient name requires both effective clinical read permissions',
    (tester) async {
      final fake =
          _FakeIamRepository()
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
              iamContextProvider.overrideWith(
                (ref) async => _context(permissions),
              ),
              careAssignmentsProvider.overrideWith(
                (ref) async => fake.careRows,
              ),
              eligibleMembersProvider.overrideWith((ref) async => const []),
              iamRepositoryProvider.overrideWithValue(fake),
            ],
            child: const MaterialApp(home: AssignmentsScreen()),
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

  testWidgets(
    'care history preserves the assignee name and filters displayed episodes locally',
    (tester) async {
      final fake =
          _FakeIamRepository()
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
          child: const MaterialApp(home: AssignmentsScreen()),
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
      expect(find.textContaining('Ingreso'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar por nombre del paciente'),
        'ada',
      );
      await tester.pump();
      expect(find.textContaining('episode-with-name'), findsOneWidget);
      expect(find.textContaining('episode-without-name'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar por nombre del paciente'),
        'without-name',
      );
      await tester.pump();
      expect(find.textContaining('episode-with-name'), findsNothing);
      expect(find.textContaining('episode-without-name'), findsOneWidget);
    },
  );

  testWidgets('transient membership failure exposes a retry action', (
    tester,
  ) async {
    final fake =
        _FakeIamRepository()..failNextOperations.add('updateMembership');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith(
            (ref) async =>
                _context({'iam.membership.read', 'iam.membership.manage'}),
          ),
          iamMembersProvider.overrideWith((ref) async => [_other]),
          iamRepositoryProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: UsersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otra persona'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspender membresía'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(fake.attempts['updateMembership'], hasLength(2));
    _expectSameAttempt(fake.attempts['updateMembership']!);
  });
}

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
  Future<List<IamMember>> members(String organizationId) async => [_other];
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
