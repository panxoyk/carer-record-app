// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'permission parser accepts complete typed rows and rejects malformed ones',
    () {
      final permission = IamPermission.fromJson({
        'code': 'iam.role.read',
        'family': 'iam',
        'description': 'Leer roles',
      });
      expect(permission.code, 'iam.role.read');
      expect(permission.family, 'iam');
      expect(permission.description, 'Leer roles');
      for (final row in [
        {'family': 'iam', 'description': 'Leer'},
        {'code': 4, 'family': 'iam', 'description': 'Leer'},
        {'code': 'x', 'family': null, 'description': 'Leer'},
        {'code': 'x', 'family': 'iam', 'description': false},
      ]) {
        expect(() => IamPermission.fromJson(row), throwsFormatException);
      }
    },
  );

  test('role model preserves the directory description and permission set', () {
    final role = IamRole.fromJson({
      'role_id': 'role-1',
      'role_name': 'Clínico',
      'description': 'Lectura asignada',
      'protected_kind': null,
      'permission_code': 'clinical.assigned.read',
    });
    expect(role.description, 'Lectura asignada');
    expect(role.permissions, {'clinical.assigned.read'});
  });

  test(
    'roles merge visible directory codes with tenant-scoped full composition',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = switch (request.url.pathSegments.last) {
            'iam_role_directory' => [
              {
                'organization_id': 'org-1',
                'role_id': 'role-1',
                'role_name': 'Ordinary',
                'description': 'Role description',
                'role_status': 'active',
                'protected_kind': null,
                'permission_code': 'visible.permission',
              },
              {
                'organization_id': 'org-1',
                'role_id': 'role-1',
                'role_name': 'Ordinary',
                'description': 'Role description',
                'role_status': 'active',
                'protected_kind': null,
                'permission_code': null,
              },
              {
                'organization_id': 'org-1',
                'role_id': 'role-protected',
                'role_name': 'Protected',
                'description': 'Protected role',
                'role_status': 'active',
                'protected_kind': 'demo_administrator',
                'permission_code': null,
              },
              {
                'organization_id': 'org-1',
                'role_id': 'role-inactive',
                'role_name': 'Inactive',
                'description': 'Inactive role',
                'role_status': 'inactive',
                'protected_kind': null,
                'permission_code': null,
              },
              {
                'organization_id': 'org-foreign',
                'role_id': 'role-foreign',
                'role_name': 'Foreign',
                'description': 'Foreign role',
                'role_status': 'active',
                'protected_kind': null,
                'permission_code': null,
              },
            ],
            'role_permissions' => [
              {
                'organization_id': 'org-1',
                'role_id': 'role-1',
                'permission_code': 'visible.permission',
              },
              {
                'organization_id': 'org-1',
                'role_id': 'role-1',
                'permission_code': 'deprecated.hidden',
              },
              {
                'organization_id': 'org-1',
                'role_id': 'role-protected',
                'permission_code': 'protected.permission',
              },
              {
                'organization_id': 'org-foreign',
                'role_id': 'role-1',
                'permission_code': 'foreign.permission',
              },
              {
                'organization_id': 'org-1',
                'role_id': 'not-in-directory',
                'permission_code': 'orphan.permission',
              },
            ],
            _ => throw StateError('Unexpected endpoint ${request.url.path}'),
          };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final roles = await IamRepository(client).roles('org-1');

      expect(roles, hasLength(1));
      expect(roles.single.description, 'Role description');
      expect(roles.single.permissions, {
        'visible.permission',
        'deprecated.hidden',
      });
      expect(requests, hasLength(2));
      final directory = requests.firstWhere(
        (request) => request.url.path.endsWith('/iam_role_directory'),
      );
      expect(directory.url.queryParameters, {
        'select': 'organization_id,role_id,role_name,description,role_status,protected_kind,permission_code',
        'organization_id': 'eq.org-1',
        'role_status': 'eq.active',
        'order': 'role_name.asc.nullslast',
      });
      final composition = requests.firstWhere(
        (request) => request.url.path.endsWith('/role_permissions'),
      );
      expect(composition.url.queryParameters, {
        'select': 'organization_id,role_id,permission_code',
        'organization_id': 'eq.org-1',
      });
      expect(
        composition.url.queryParameters['select'],
        isNot(contains('granted_by')),
      );
    },
  );

  test('catalog transport requests explicit active ordinary fields', () async {
    late http.Request observed;
    final client = SupabaseClient(
      'http://synthetic.test',
      'synthetic-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode([
            _permission('ordinary.permission'),
            _permission('old.permission', status: 'deprecated'),
            _permission('system.permission', policy: 'system_only'),
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final permissions = await IamRepository(client).delegablePermissions();

    expect(permissions.map((permission) => permission.code), [
      'ordinary.permission',
    ]);
    expect(observed.url.path, endsWith('/permission_catalog'));
    expect(observed.url.queryParameters, {
      'select': 'code,family,description,status,delegation_policy',
      'status': 'eq.active',
      'delegation_policy': 'eq.ordinary',
      'order': 'family.asc.nullslast,code.asc.nullslast',
    });
  });

  test(
    'catalog read excludes nondelegable rows and intersects selected context',
    () async {
      final remote = _FakeIamRemote([
        _permission('iam.role.read'),
        _permission('clinical.patient.read'),
        _permission('clinical.reserved.read', policy: 'system_only'),
        _permission('clinical.old.read', status: 'deprecated'),
      ]);
      final repository = IamRepository(_client, remote: remote);
      final queried = await repository.delegablePermissions();
      final owned = const IamContext(
        organizationId: 'org-selected',
        organizationName: 'Selected',
        profileId: 'profile',
        displayName: 'Actor',
        profileStatus: 'active',
        membershipId: 'membership',
        membershipStatus: 'active',
        permissions: {'iam.role.read', 'clinical.patient.read'},
      );
      final result = queried.where(
        (permission) => owned.allows(permission.code),
      );
      expect(result.map((permission) => permission.code), {
        'iam.role.read',
        'clinical.patient.read',
      });
      expect(remote.catalogCalls, 1);
    },
  );

  test(
    'role composition RPC canonicalizes payload and preserves retry key',
    () async {
      final remote = _FakeIamRemote([]);
      final repository = IamRepository(_client, remote: remote);
      final firstAttempt = AdminOperationAttempt(idempotencyKey: 'same-key');
      Future<void> send(AdminOperationAttempt attempt) async {
        await repository.replaceRolePermissions(
          organizationId: 'org-1',
          roleId: 'role-1',
          permissions: ['z.permission', 'a.permission', 'z.permission'],
          attempt: attempt,
        );
      }

      await send(firstAttempt);
      await send(firstAttempt);
      expect(remote.calls[0], {
        'name': 'replace_iam_role_permissions',
        'params': {
          'p_organization_id': 'org-1',
          'p_role_id': 'role-1',
          'p_permissions': ['a.permission', 'z.permission'],
          'p_idempotency_key': 'same-key',
        },
      });
      expect(remote.calls[1]['params'], remote.calls[0]['params']);
      await send(AdminOperationAttempt(idempotencyKey: 'new-key'));
      expect(
        (remote.calls.last['params'] as Map)['p_idempotency_key'],
        'new-key',
      );
      expect(firstAttempt.validFrom, isNull);
    },
  );

  test(
    'delegable provider returns empty without both effective IAM permissions',
    () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => _session),
          iamContextProvider.overrideWith(
            (ref) async => const IamContext(
              organizationId: 'org-1',
              organizationName: 'Org',
              profileId: 'p',
              displayName: 'Actor',
              profileStatus: 'active',
              membershipId: 'm',
              membershipStatus: 'active',
              permissions: {'iam.role.read'},
            ),
          ),
          iamRepositoryProvider.overrideWith(
            (ref) => IamRepository(
              _client,
              remote: _FakeIamRemote([_permission('iam.role.read')]),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(iamDelegablePermissionsProvider.future),
        isEmpty,
      );
    },
  );

  test(
    'delegable provider only emits permissions owned in selected organization',
    () async {
      final remote = _FakeIamRemote([
        _permission('iam.role.read'),
        _permission('iam.role.manage'),
        _permission('clinical.patient.read'),
      ]);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => _session),
          iamContextProvider.overrideWith(
            (ref) async => const IamContext(
              organizationId: 'org-selected',
              organizationName: 'Selected',
              profileId: 'p',
              displayName: 'Actor',
              profileStatus: 'active',
              membershipId: 'm',
              membershipStatus: 'active',
              permissions: {'iam.role.read', 'iam.role.manage'},
            ),
          ),
          iamRepositoryProvider.overrideWith(
            (ref) => IamRepository(_client, remote: remote),
          ),
        ],
      );
      addTearDown(container.dispose);
      final codes = (await container.read(
        iamDelegablePermissionsProvider.future,
      )).map((permission) => permission.code).toSet();
      expect(codes, {'iam.role.read', 'iam.role.manage'});
      expect(remote.catalogCalls, 1);
    },
  );

  testWidgets(
    'central authorization invalidation refreshes permission catalog',
    (tester) async {
      final remote = _FakeIamRemote([_permission('iam.role.read')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => _session),
            iamContextProvider.overrideWith(
              (ref) async => const IamContext(
                organizationId: 'org-selected',
                organizationName: 'Selected',
                profileId: 'p',
                displayName: 'Actor',
                profileStatus: 'active',
                membershipId: 'm',
                membershipStatus: 'active',
                permissions: {'iam.role.read', 'iam.role.manage'},
              ),
            ),
            iamRepositoryProvider.overrideWith(
              (ref) => IamRepository(_client, remote: remote),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                ref.watch(iamDelegablePermissionsProvider);
                return ElevatedButton(
                  onPressed: () => invalidateAuthorizationAndData(ref),
                  child: const Text('invalidate'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(remote.catalogCalls, 1);
      await tester.tap(find.text('invalidate'));
      await tester.pumpAndSettle();
      expect(remote.catalogCalls, 2);
    },
  );
}

Map<String, dynamic> _permission(
  String code, {
  String status = 'active',
  String policy = 'ordinary',
}) => {
  'code': code,
  'family': code.split('.').first,
  'description': 'Synthetic permission',
  'status': status,
  'delegation_policy': policy,
};

final _session = Session(
  accessToken: 'synthetic-token',
  tokenType: 'bearer',
  user: User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

SupabaseClient get _client => SupabaseClient(
  'http://127.0.0.1:54321',
  'synthetic-test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _FakeIamRemote implements IamRemote {
  _FakeIamRemote(this.rows);
  final List<Map<String, dynamic>> rows;
  int catalogCalls = 0;
  final calls = <Map<String, dynamic>>[];
  final roleQueries = <String>[];

  @override
  Future<List<Map<String, dynamic>>> delegablePermissions() async {
    catalogCalls++;
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> ordinaryRoleDirectory(
    String organizationId,
  ) async {
    roleQueries.add('iam_role_directory:$organizationId');
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> ordinaryRolePermissionCodes(
    String organizationId,
  ) async {
    roleQueries.add('role_permissions:$organizationId');
    return const [];
  }

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    calls.add({'name': name, 'params': params});
    return [
      {
        'result': true,
        'result_code': 'permissions_replaced',
        'target_id': 'role-1',
        'replayed': false,
      },
    ];
  }
}
