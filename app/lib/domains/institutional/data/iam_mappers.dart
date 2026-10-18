import '../domain/iam_entities.dart';

List<IamContext> iamContextsFromRows(List<Map<String, dynamic>> rows) {
  final groups =
      <
        (String organizationId, String membershipId),
        List<Map<String, dynamic>>
      >{};
  for (final row in rows) {
    final key = (
      row['organization_id'] as String,
      row['membership_id'] as String,
    );
    (groups[key] ??= []).add(row);
  }
  final memberships = <String, Set<String>>{};
  for (final (organizationId, membershipId) in groups.keys) {
    (memberships[organizationId] ??= {}).add(membershipId);
  }
  if (memberships.values.any((value) => value.length != 1)) {
    throw const FormatException(
      'Multiple active memberships in one organization',
    );
  }
  return [
    for (final rows in groups.values) _iamContextFromMembershipRows(rows),
  ];
}

IamContext _iamContextFromMembershipRows(List<Map<String, dynamic>> rows) {
  final first = rows.first;
  for (final row in rows.skip(1)) {
    for (final key in const [
      'organization_name',
      'profile_id',
      'display_name',
      'profile_status',
      'membership_status',
    ]) {
      if (row[key] != first[key]) {
        throw const FormatException('Inconsistent IAM membership context');
      }
    }
  }
  return IamContext(
    organizationId: first['organization_id'] as String,
    organizationName: first['organization_name'] as String,
    profileId: first['profile_id'] as String,
    displayName: first['display_name'] as String,
    profileStatus: first['profile_status'] as String,
    membershipId: first['membership_id'] as String,
    membershipStatus: first['membership_status'] as String,
    permissions: rows
        .map((row) => row['permission_code'] as String?)
        .whereType<String>()
        .toSet(),
  );
}

IamMember iamMemberFromJson(Map<String, dynamic> row) => IamMember(
  membershipId: row['membership_id'] as String,
  profileId: row['profile_id'] as String,
  displayName: row['display_name'] as String,
  profileStatus: row['profile_status'] as String,
  membershipStatus: row['membership_status'] as String,
  validFrom: DateTime.parse(row['valid_from'] as String),
  validUntil: row['valid_until'] == null
      ? null
      : DateTime.parse(row['valid_until'] as String),
);
IamRole iamRoleFromJson(Map<String, dynamic> row) => IamRole(
  id: row['role_id'] as String,
  name: row['role_name'] as String,
  description: row['description'] as String,
  protected: row['protected_kind'] != null,
  permissions: {if (row['permission_code'] case final String code) code},
);
IamPermission iamPermissionFromJson(Map<String, dynamic> row) {
  final code = row['code'];
  final family = row['family'];
  final description = row['description'];
  if (code is! String ||
      !RegExp(r'^[a-z]+(\.[a-z_]+)+$').hasMatch(code) ||
      family is! String ||
      family.trim().isEmpty ||
      description is! String ||
      description.trim().isEmpty) {
    throw const FormatException('Invalid IAM permission catalog row');
  }
  return IamPermission(code: code, family: family, description: description);
}

CareAssignmentRecord careAssignmentRecordFromJson(Map<String, dynamic> row) =>
    CareAssignmentRecord(
      hospitalizationId: row['hospitalization_id'] as String,
      status: row['hospitalization_status'] as String,
      admittedAt: DateTime.parse(row['admitted_at'] as String),
      assignmentId: row['assignment_id'] as String?,
      membershipId: row['membership_id'] as String?,
      validFrom: row['assignment_valid_from'] == null
          ? null
          : DateTime.parse(row['assignment_valid_from'] as String),
      validUntil: row['assignment_valid_until'] == null
          ? null
          : DateTime.parse(row['assignment_valid_until'] as String),
      revokedAt: row['revoked_at'] == null
          ? null
          : DateTime.parse(row['revoked_at'] as String),
      assigneeDisplayName: row['assignee_display_name'] as String?,
      assigneeMembershipStatus: row['assignee_membership_status'] as String?,
    );
EligibleMember eligibleMemberFromJson(Map<String, dynamic> row) =>
    EligibleMember(
      membershipId: row['membership_id'] as String,
      displayName: row['display_name'] as String,
    );
IamRoleAssignment iamRoleAssignmentFromJson(Map<String, dynamic> row) =>
    IamRoleAssignment(
      assignmentId: row['assignment_id'] as String,
      membershipId: row['membership_id'] as String,
      roleId: row['role_id'] as String,
      roleName: row['role_name'] as String,
      protected: row['protected_kind'] != null,
      validFrom: DateTime.parse(row['valid_from'] as String),
      validUntil: row['valid_until'] == null
          ? null
          : DateTime.parse(row['valid_until'] as String),
      revokedAt: row['revoked_at'] == null
          ? null
          : DateTime.parse(row['revoked_at'] as String),
    );
AdminOperationResult adminOperationResultFromJson(Map<String, dynamic> row) =>
    AdminOperationResult(
      success: row['result'] as bool,
      code: row['result_code'] as String,
      targetId: row['target_id'] as String? ?? row['assignment_id'] as String?,
      replayed: row['replayed'] as bool,
    );
