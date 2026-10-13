import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/users/presentation/roles_permissions_screen.dart';
import 'package:carer_record_app/core/design_system/anchored_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

void main() {
  testWidgets(
    'denies unless both role read and manage, without sensitive providers',
    (tester) async {
      for (final permissions in [
        <String>{'iam.role.read'},
        <String>{'iam.role.manage'},
        <String>{},
      ]) {
        var touched = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iamContextProvider.overrideWith(
                (ref) async => _context(permissions),
              ),
              iamRolesProvider.overrideWith((ref) async {
                touched = true;
                return [_role];
              }),
              iamDelegablePermissionsProvider.overrideWith((ref) async {
                touched = true;
                return _catalog;
              }),
            ],
            child: const MaterialApp(home: RolesPermissionsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Acceso no disponible.'), findsOneWidget);
        expect(touched, isFalse);
      }
    },
  );

  testWidgets(
    'shows grouped delegable composition and protects hidden permissions',
    (tester) async {
      final fake = _FakeRepository();
      final roleWithDeprecated = _role.copyWith(
        permissions: {'clinical.read', 'deprecated.hidden'},
      );
      await _mount(tester, fake, roles: [roleWithDeprecated]);
      expect(find.text('No hay roles ordinarios activos.'), findsNothing);
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equipo').last);
      await tester.pumpAndSettle();
      expect(find.text('clínico'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('membresías'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('membresías'), findsOneWidget);
      expect(find.text('clinical.read'), findsOneWidget);
      expect(
        find.text('No fue posible editar el rol sin revisar permisos ocultos.'),
        findsNothing,
      );
      expect(
        find.textContaining('no disponibles para esta edición'),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('00000000'), findsNothing);
      expect(roleWithDeprecated.permissions, {
        'clinical.read',
        'deprecated.hidden',
      });
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets(
    'permission search keeps family groups and matches descriptions',
    (tester) async {
      await _mount(
        tester,
        _FakeRepository(),
        roles: [_role.copyWith(permissions: {})],
      );
      await _select(tester, 'Equipo');
      expect(find.text('Gestión de roles y permisos'), findsOneWidget);
      expect(find.text('Descripción del rol'), findsNothing);
      final search = find.byKey(const ValueKey('permission-search'));
      final decoration = tester.widget<TextField>(search).decoration!;
      expect(decoration.hintText, 'Nombre o descripción');
      expect(decoration.labelText, isNull);
      expect(decoration.helperText, isNull);
      expect(
        find.text('Busca por nombre, familia o descripción.'),
        findsNothing,
      );
      expect(find.text('clínico'), findsOneWidget);
      expect(find.text('membresías'), findsOneWidget);

      await tester.enterText(search, 'escritura');
      await tester.pumpAndSettle();
      expect(find.text('clinical.write'), findsOneWidget);
      expect(find.text('clinical.read'), findsNothing);
      expect(find.text('membresías'), findsNothing);

      await tester.enterText(search, 'membresías');
      await tester.pumpAndSettle();
      expect(find.text('iam.membership.read'), findsOneWidget);
      expect(find.text('clinical.write'), findsNothing);

      await tester.enterText(search, 'nada coincide');
      await tester.pumpAndSettle();
      expect(
        find.text('Ningún permiso coincide con la búsqueda.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty roles state and ordinary selection excludes protected role',
    (tester) async {
      await _mount(tester, _FakeRepository(), roles: []);
      expect(find.text('No hay roles ordinarios activos.'), findsOneWidget);
      await _mount(
        tester,
        _FakeRepository(),
        roles: [
          _role,
          _role.copyWith(
            id: 'protected-id',
            name: 'Protegido',
            protected: true,
          ),
        ],
      );
      await tester.tap(find.byType(AnchoredSelector<String>));
      await tester.pumpAndSettle();
      expect(find.text('Protegido'), findsNothing);
      expect(find.text('00000000-0000-0000-0000-000000000001'), findsNothing);
    },
  );

  testWidgets('saving replaces full composition and success confirms', (
    tester,
  ) async {
    final fake = _FakeRepository();
    await _mount(tester, fake, roles: [_role.copyWith(permissions: {})]);
    await _select(tester, 'Equipo');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('reemplazar todos los permisos'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(fake.permissions, ['clinical.read']);
    expect(fake.attempt?.validFrom, isNull);
    expect(find.text('Permisos actualizados.'), findsOneWidget);
  });

  testWidgets('roles loading never renders a stale role', (tester) async {
    final pending = Completer<List<IamRole>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith(
            (ref) async => _context({'iam.role.read', 'iam.role.manage'}),
          ),
          iamRolesProvider.overrideWith((ref) => pending.future),
          iamDelegablePermissionsProvider.overrideWith((ref) async => _catalog),
        ],
        child: const MaterialApp(home: RolesPermissionsScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Equipo'), findsNothing);
    pending.complete([_role]);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'complete permission payload is sorted and contains only checked catalog codes',
    (tester) async {
      final fake = _FakeRepository();
      await _mount(tester, fake, roles: [_role.copyWith(permissions: {})]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.permissions, ['clinical.read', 'clinical.write']);
      expect(fake.permissions, isNot(contains('secret.hidden')));
    },
  );

  testWidgets('catalog retry invalidates and queries again', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iamContextProvider.overrideWith(
            (ref) async => _context({'iam.role.read', 'iam.role.manage'}),
          ),
          iamRolesProvider.overrideWith((ref) async => [_role]),
          iamDelegablePermissionsProvider.overrideWith((ref) async {
            reads++;
            if (reads == 1) throw StateError('private database details');
            return _catalog;
          }),
        ],
        child: const MaterialApp(home: RolesPermissionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('No fue posible cargar el catálogo.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('No fue posible cargar el catálogo.'), findsNothing);
  });

  testWidgets(
    'dirty role switch cancel preserves draft and confirm loads next composition',
    (tester) async {
      final second = _role.copyWith(
        id: '00000000-0000-0000-0000-000000000002',
        name: 'Supervisión',
        permissions: {},
      );
      await _mount(tester, _FakeRepository(), roles: [_role, second]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await _chooseRole(tester, 'Supervisión');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Equipo'), findsOneWidget);
      expect(
        tester
            .widget<AnchoredSelector<String>>(
              find.byType(AnchoredSelector<String>),
            )
            .selectedValue,
        _role.id,
      );
      expect(find.text('Descripción del rol'), findsNothing);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse,
      );
      await _chooseRole(tester, 'Supervisión');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Supervisión'), findsOneWidget);
      expect(find.text('Descripción del rol'), findsNothing);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse,
      );
    },
  );

  testWidgets(
    'organization change removes old selection immediately during reload',
    (tester) async {
      final contextState = StateProvider<IamContext>(
        (ref) => _context({'iam.role.read', 'iam.role.manage'}),
      );
      final rolesPending = Completer<List<IamRole>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contextState.overrideWith(
              (ref) => _context({'iam.role.read', 'iam.role.manage'}),
            ),
            iamContextProvider.overrideWith((ref) => ref.watch(contextState)),
            iamRolesProvider.overrideWith((ref) {
              final current = ref.watch(iamContextProvider).valueOrNull;
              return current?.organizationId == 'org-2'
                  ? rolesPending.future
                  : Future.value([_role]);
            }),
            iamDelegablePermissionsProvider.overrideWith(
              (ref) async => _catalog,
            ),
          ],
          child: const MaterialApp(home: RolesPermissionsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await _select(tester, 'Equipo');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RolesPermissionsScreen)),
      );
      container.read(contextState.notifier).state = _contextFor('org-2');
      container.invalidate(iamRolesProvider);
      await tester.pump();
      expect(find.text('Equipo'), findsNothing);
      expect(find.text('Descripción del rol'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      rolesPending.complete([_role]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'all saves require impact confirmation including explicit empty set',
    (tester) async {
      final fake = _FakeRepository();
      await _mount(tester, fake, roles: [_role.copyWith(permissions: {})]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('reemplazar todos los permisos'),
        findsOneWidget,
      );
      expect(fake.attempts, isEmpty);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.permissions, ['clinical.read']);

      final emptyFake = _FakeRepository();
      await _mount(tester, emptyFake, roles: [_role]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('quitar todos los permisos'), findsOneWidget);
      expect(emptyFake.attempts, isEmpty);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(emptyFake.permissions, isEmpty);
    },
  );

  testWidgets(
    'exception retry reuses exact snapshot; new save gesture gets new key and draft',
    (tester) async {
      final fake = _FakeRepository()..throwCount = 2;
      await _mount(tester, fake, roles: [_role.copyWith(permissions: {})]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      final first = fake.calls.first;
      expect(first.permissions, {'clinical.read'});
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(
        fake.calls[1].attempt.idempotencyKey,
        first.attempt.idempotencyKey,
      );
      expect(fake.calls[1].permissions, first.permissions);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(
        fake.calls.last.attempt.idempotencyKey,
        isNot(first.attempt.idempotencyKey),
      );
      expect(fake.calls.last.permissions, {'clinical.write'});
    },
  );

  for (final resultCode in [
    'denied',
    'permission_not_delegable',
    'protected_or_missing',
    'idempotency_conflict',
  ]) {
    testWidgets('$resultCode is sanitized and never reports success', (
      tester,
    ) async {
      final fake = _FakeRepository()..resultCode = resultCode;
      await _mount(tester, fake, roles: [_role.copyWith(permissions: {})]);
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Permisos actualizados.'), findsNothing);
      expect(find.textContaining('00000000'), findsNothing);
      expect(find.textContaining('private database details'), findsNothing);
      expect(find.textContaining('SQL'), findsNothing);
      expect(
        find.textContaining(switch (resultCode) {
          'denied' => 'No fue posible autorizar',
          'permission_not_delegable' => 'ya no está disponible',
          'protected_or_missing' => 'No fue posible actualizar',
          _ => 'no pudo confirmarse',
        }),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'success invalidates and hides previous content while requery is pending',
    (tester) async {
      final fake = _FakeRepository();
      final nextRoles = Completer<List<IamRole>>();
      var roleReads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iamContextProvider.overrideWith(
              (ref) async => _context({'iam.role.read', 'iam.role.manage'}),
            ),
            iamRolesProvider.overrideWith((ref) {
              roleReads++;
              return roleReads == 1
                  ? Future.value([_role.copyWith(permissions: {})])
                  : nextRoles.future;
            }),
            iamDelegablePermissionsProvider.overrideWith(
              (ref) async => _catalog,
            ),
            iamRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: RolesPermissionsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await _select(tester, 'Equipo');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pump();
      await tester.pump();
      expect(roleReads, lessThanOrEqualTo(3));
      expect(find.text('Equipo'), findsNothing);
      expect(find.text('Descripción del rol'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      nextRoles.complete([_role]);
      await tester.pumpAndSettle();
      expect(roleReads, lessThanOrEqualTo(3));
    },
  );
}

Future<void> _chooseRole(WidgetTester tester, String name) async {
  await tester.tap(find.byType(AnchoredSelector<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

IamContext _contextFor(String org) => IamContext(
  organizationId: org,
  organizationName: 'Hospital $org',
  profileId: 'profile-$org',
  displayName: 'Actor',
  profileStatus: 'active',
  membershipId: 'member-$org',
  membershipStatus: 'active',
  permissions: {'iam.role.read', 'iam.role.manage'},
);

Future<void> _mount(
  WidgetTester tester,
  _FakeRepository repository, {
  required List<IamRole> roles,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey(identityHashCode(repository)),
      overrides: [
        iamContextProvider.overrideWith(
          (ref) async => _context({'iam.role.read', 'iam.role.manage'}),
        ),
        iamRolesProvider.overrideWith((ref) async => roles),
        iamDelegablePermissionsProvider.overrideWith((ref) async => _catalog),
        iamRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: RolesPermissionsScreen(
          key: ValueKey(identityHashCode(repository)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String name) async {
  await tester.tap(find.byType(AnchoredSelector<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

IamContext _context(Set<String> permissions) => IamContext(
  organizationId: 'org-1',
  organizationName: 'Hospital',
  profileId: 'profile-1',
  displayName: 'Actor',
  profileStatus: 'active',
  membershipId: 'member-1',
  membershipStatus: 'active',
  permissions: permissions,
);

const _role = IamRole(
  id: '00000000-0000-0000-0000-000000000001',
  name: 'Equipo',
  description: 'Descripción del rol',
  protected: false,
  permissions: {'clinical.read'},
);
const _catalog = [
  IamPermission(
    code: 'clinical.read',
    family: 'clínico',
    description: 'Lectura clínica',
  ),
  IamPermission(
    code: 'clinical.write',
    family: 'clínico',
    description: 'Escritura clínica',
  ),
  IamPermission(
    code: 'iam.membership.read',
    family: 'membresías',
    description: 'Lectura de membresías',
  ),
];

class _FakeRepository implements IamRepository {
  AdminOperationAttempt? attempt;
  List<String>? permissions;
  int throwCount = 0;
  String? resultCode;
  final List<({AdminOperationAttempt attempt, Set<String> permissions})> calls =
      [];
  List<AdminOperationAttempt> get attempts =>
      calls.map((call) => call.attempt).toList();
  @override
  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  }) async {
    this.attempt = attempt;
    this.permissions = permissions.toList();
    calls.add((attempt: attempt, permissions: permissions.toSet()));
    if (throwCount > 0) {
      throwCount--;
      throw StateError('private database details');
    }
    return AdminOperationResult(
      success: resultCode == null,
      code: resultCode ?? 'permissions_replaced',
      targetId: null,
      replayed: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension on IamRole {
  IamRole copyWith({
    String? id,
    String? name,
    bool? protected,
    Set<String>? permissions,
  }) => IamRole(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description,
    protected: protected ?? this.protected,
    permissions: permissions ?? this.permissions,
  );
}
