import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'iam_models.dart';

abstract interface class IamRemote {
  Future<List<Map<String, dynamic>>> delegablePermissions();
  Future<List<Map<String, dynamic>>> ordinaryRoleDirectory(
    String organizationId,
  );
  Future<List<Map<String, dynamic>>> ordinaryRolePermissionCodes(
    String organizationId,
  );
  Future<dynamic> rpc(String name, Map<String, dynamic> params);
}

class SupabaseIamRemote implements IamRemote {
  SupabaseIamRemote(this.client);
  final SupabaseClient client;

  @override
  Future<List<Map<String, dynamic>>> delegablePermissions() async {
    final rows = await client
        .from('permission_catalog')
        .select('code,family,description,status,delegation_policy')
        .eq('status', 'active')
        .eq('delegation_policy', 'ordinary')
        .order('family', ascending: true)
        .order('code', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> ordinaryRoleDirectory(
    String organizationId,
  ) async {
    final rows = await client
        .from('iam_role_directory')
        .select(
          'organization_id,role_id,role_name,description,role_status,protected_kind,permission_code',
        )
        .eq('organization_id', organizationId)
        .eq('role_status', 'active')
        .order('role_name', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> ordinaryRolePermissionCodes(
    String organizationId,
  ) async {
    final rows = await client
        .from('role_permissions')
        .select('organization_id,role_id,permission_code')
        .eq('organization_id', organizationId);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) =>
      client.rpc<List<dynamic>>(name, params: params);
}

String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

AdminOperationAttempt newAdminOperationAttempt({bool usesValidFrom = false}) =>
    AdminOperationAttempt(
      idempotencyKey: newIdempotencyKey(),
      validFrom: usesValidFrom ? DateTime.now().toUtc() : null,
    );

class IamRepository {
  IamRepository(SupabaseClient client, {IamRemote? remote})
    : _client = client,
      _remote = remote ?? SupabaseIamRemote(client);
  final SupabaseClient _client;
  final IamRemote _remote;

  Future<List<IamPermission>> delegablePermissions() async =>
      (await _remote.delegablePermissions())
          .where(
            (row) =>
                row['status'] == 'active' &&
                row['delegation_policy'] == 'ordinary',
          )
          .map(IamPermission.fromJson)
          .toList();

  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  }) {
    final canonical = permissions.toSet().toList()..sort();
    return _rpc('replace_iam_role_permissions', {
      'p_organization_id': organizationId,
      'p_role_id': roleId,
      'p_permissions': canonical,
      'p_idempotency_key': attempt.idempotencyKey,
    });
  }

  Future<List<IamContext>> currentContexts() async => IamContext.fromRows(
    await _client
        .from('iam_current_context')
        .select()
        .then((rows) => List<Map<String, dynamic>>.from(rows)),
  );

  Future<List<IamMember>> members(String organizationId) async {
    final rows = await _client
        .from('iam_member_directory')
        .select()
        .eq('organization_id', organizationId)
        .order('display_name');
    return List<Map<String, dynamic>>.from(rows)
        .map(IamMember.fromJson)
        .toList();
  }

  Future<List<IamRole>> roles(String organizationId) async {
    final grouped = <String, Map<String, dynamic>>{};
    for (final row in await _remote.ordinaryRoleDirectory(organizationId)) {
      if (row['organization_id'] != organizationId ||
          row['role_status'] != 'active' ||
          row['protected_kind'] != null) {
        continue;
      }
      final item = grouped.putIfAbsent(
        row['role_id'] as String,
        () => {
          'role_id': row['role_id'],
          'role_name': row['role_name'],
          'description': row['description'],
          'protected_kind': row['protected_kind'],
          'permissions': <String>{},
        },
      );
      if (row['permission_code'] case final String code) {
        (item['permissions'] as Set<String>).add(code);
      }
    }
    if (grouped.isNotEmpty) {
      final roleIds = grouped.keys.toSet();
      for (final row in await _remote.ordinaryRolePermissionCodes(
        organizationId,
      )) {
        final roleId = row['role_id'];
        final code = row['permission_code'];
        if (row['organization_id'] != organizationId ||
            roleId is! String ||
            !roleIds.contains(roleId) ||
            code is! String) {
          continue;
        }
        (grouped[roleId]!['permissions'] as Set<String>).add(code);
      }
    }
    return grouped.values
        .map(
          (row) => IamRole(
            id: row['role_id'] as String,
            name: row['role_name'] as String,
            description: row['description'] as String,
            protected: false,
            permissions: row['permissions'] as Set<String>,
          ),
        )
        .toList();
  }

  Future<Map<String, List<IamRoleAssignment>>> roleAssignments(
    String organizationId,
  ) async {
    final rows = await _client
        .from('iam_member_role_assignments')
        .select()
        .eq('organization_id', organizationId);
    final grouped = <String, List<IamRoleAssignment>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      (grouped[row['membership_id'] as String] ??= []).add(
        IamRoleAssignment.fromJson(row),
      );
    }
    return grouped;
  }

  Future<void> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
    required String idempotencyKey,
  }) async {
    await _client.functions.invoke(
      'create-practitioner',
      body: {
        'organizationId': organizationId,
        'email': email.trim(),
        'password': password,
        'displayName': displayName.trim(),
        'roleId': roleId,
        'idempotencyKey': idempotencyKey,
      },
    );
  }

  Future<AdminOperationResult> _rpc(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await _remote.rpc(name, args) as List<dynamic>;
    return AdminOperationResult.fromJson(
      Map<String, dynamic>.from(result.first as Map),
    );
  }

  Future<AdminOperationResult> updateMembership({
    required String organizationId,
    required String membershipId,
    required String status,
    required AdminOperationAttempt attempt,
  }) => _rpc('manage_organization_membership', {
    'p_organization_id': organizationId,
    'p_membership_id': membershipId,
    'p_status': status,
    'p_valid_until': null,
    'p_idempotency_key': attempt.idempotencyKey,
  });

  Future<AdminOperationResult> grantRole({
    required String organizationId,
    required String membershipId,
    required String roleId,
    required AdminOperationAttempt attempt,
  }) {
    final validFrom = attempt.validFrom;
    if (validFrom == null) {
      throw ArgumentError.value(
        attempt,
        'attempt',
        'Role grants require validFrom',
      );
    }
    return _rpc('grant_iam_role', {
      'p_organization_id': organizationId,
      'p_membership_id': membershipId,
      'p_role_id': roleId,
      'p_valid_from': validFrom.toIso8601String(),
      'p_valid_until': null,
      'p_idempotency_key': attempt.idempotencyKey,
    });
  }

  Future<AdminOperationResult> revokeRole({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) => _rpc('revoke_iam_role', {
    'p_organization_id': organizationId,
    'p_assignment_id': assignmentId,
    'p_idempotency_key': attempt.idempotencyKey,
  });

  Future<List<CareAssignmentRecord>> assignments(String organizationId) async {
    final rows = await _client
        .from('iam_assignment_hospitalizations')
        .select(
          'hospitalization_id,hospitalization_status,admitted_at,assignment_id,membership_id,assignment_valid_from,assignment_valid_until,revoked_at,assignee_display_name,assignee_membership_status',
        )
        .eq('organization_id', organizationId)
        .order('admitted_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(CareAssignmentRecord.fromJson)
        .toList();
  }

  Future<Map<String, String>> censusPatientNames(String organizationId) async {
    final rows = await _client
        .from('clinical_census_by_hospitalization')
        .select('hospitalization_id,given_name,family_name')
        .eq('organization_id', organizationId);
    return {
      for (final row in List<Map<String, dynamic>>.from(rows))
        row['hospitalization_id'] as String:
            '${row['given_name'] ?? ''} ${row['family_name'] ?? ''}'.trim(),
    };
  }

  Future<List<EligibleMember>> eligibleMembers(String organizationId) async {
    final rows = await _client
        .from('iam_assignment_eligible_members')
        .select()
        .eq('organization_id', organizationId)
        .order('display_name');
    return List<Map<String, dynamic>>.from(rows)
        .map(EligibleMember.fromJson)
        .toList();
  }

  Future<AdminOperationResult> grantCareAssignment({
    required String organizationId,
    required String hospitalizationId,
    required String membershipId,
    required AdminOperationAttempt attempt,
  }) {
    final validFrom = attempt.validFrom;
    if (validFrom == null) {
      throw ArgumentError.value(
        attempt,
        'attempt',
        'Care grants require validFrom',
      );
    }
    return _rpc('grant_care_assignment', {
      'p_organization_id': organizationId,
      'p_hospitalization_id': hospitalizationId,
      'p_membership_id': membershipId,
      'p_valid_from': validFrom.toIso8601String(),
      'p_valid_until': null,
      'p_idempotency_key': attempt.idempotencyKey,
    });
  }

  Future<AdminOperationResult> revokeCareAssignment({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) => _rpc('revoke_care_assignment', {
    'p_organization_id': organizationId,
    'p_assignment_id': assignmentId,
    'p_idempotency_key': attempt.idempotencyKey,
  });
}
