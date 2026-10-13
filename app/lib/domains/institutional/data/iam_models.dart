class IamContext {
  const IamContext({
    required this.organizationId,
    required this.organizationName,
    required this.profileId,
    required this.displayName,
    required this.profileStatus,
    required this.membershipId,
    required this.membershipStatus,
    required this.permissions,
  });

  final String organizationId;
  final String organizationName;
  final String profileId;
  final String displayName;
  final String profileStatus;
  final String membershipId;
  final String membershipStatus;
  final Set<String> permissions;

  bool allows(String permission) => permissions.contains(permission);

  static IamContext? select(List<IamContext> contexts, String? organizationId) {
    if (contexts.length == 1) return contexts.single;
    for (final context in contexts) {
      if (context.organizationId == organizationId) return context;
    }
    return null;
  }

  static IamContext? selectForSession(
    List<IamContext> contexts,
    OrganizationSelection? selection,
    String sessionUserId,
  ) {
    final organizationId = selection?.userId == sessionUserId
        ? selection?.organizationId
        : null;
    return select(contexts, organizationId);
  }

  static List<IamContext> fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const [];
    final grouped = <(String, String), List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final organizationId = row['organization_id'] as String;
      final membershipId = row['membership_id'] as String;
      (grouped[(organizationId, membershipId)] ??= []).add(row);
    }
    final membershipsByOrganization = <String, Set<String>>{};
    for (final (organizationId, membershipId) in grouped.keys) {
      (membershipsByOrganization[organizationId] ??= {}).add(membershipId);
    }
    if (membershipsByOrganization.values.any(
      (memberships) => memberships.length != 1,
    )) {
      throw const FormatException(
        'Multiple active memberships in one organization',
      );
    }
    return [
      for (final entry in grouped.entries) _fromMembershipRows(entry.value),
    ];
  }

  static IamContext _fromMembershipRows(List<Map<String, dynamic>> rows) {
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
}

class OrganizationSelection {
  const OrganizationSelection({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

class AdminOperationAttempt {
  AdminOperationAttempt({required this.idempotencyKey, DateTime? validFrom})
    : validFrom = validFrom?.toUtc();

  final String idempotencyKey;
  final DateTime? validFrom;
}

class IamMember {
  const IamMember({
    required this.membershipId,
    required this.profileId,
    required this.displayName,
    required this.profileStatus,
    required this.membershipStatus,
    this.validFrom,
    this.validUntil,
  });
  final String membershipId;
  final String profileId;
  final String displayName;
  final String profileStatus;
  final String membershipStatus;
  final DateTime? validFrom;
  final DateTime? validUntil;
  factory IamMember.fromJson(Map<String, dynamic> row) => IamMember(
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
}

bool isVisibleInMemberDirectory(IamMember member) =>
    member.profileStatus == 'active' &&
    (member.membershipStatus == 'active' ||
        member.membershipStatus == 'suspended');

bool isEligibleForNewAssignment(IamMember member, {required DateTime now}) {
  final instant = now.toUtc();
  return member.profileStatus == 'active' &&
      member.membershipStatus == 'active' &&
      (member.validFrom == null ||
          !member.validFrom!.toUtc().isAfter(instant)) &&
      (member.validUntil == null ||
          member.validUntil!.toUtc().isAfter(instant));
}

class IamRole {
  const IamRole({
    required this.id,
    required this.name,
    required this.protected,
    required this.permissions,
    this.description = '',
  });
  final String id;
  final String name;
  final bool protected;
  final Set<String> permissions;
  final String description;
  factory IamRole.fromJson(Map<String, dynamic> row) => IamRole(
    id: row['role_id'] as String,
    name: row['role_name'] as String,
    description: row['description'] as String,
    protected: row['protected_kind'] != null,
    permissions: <String>{
      if (row['permission_code'] case final String code) code,
    },
  );
}

class IamPermission {
  const IamPermission({
    required this.code,
    required this.family,
    required this.description,
  });

  final String code;
  final String family;
  final String description;

  factory IamPermission.fromJson(Map<String, dynamic> row) {
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
}

class CareAssignmentRecord {
  const CareAssignmentRecord({
    required this.hospitalizationId,
    required this.status,
    required this.admittedAt,
    this.assignmentId,
    this.membershipId,
    this.validFrom,
    this.validUntil,
    this.revokedAt,
    this.assigneeDisplayName,
    this.assigneeMembershipStatus,
  });
  final String hospitalizationId;
  final String status;
  final DateTime admittedAt;
  final String? assignmentId;
  final String? membershipId;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? revokedAt;
  final String? assigneeDisplayName;
  final String? assigneeMembershipStatus;
  factory CareAssignmentRecord.fromJson(Map<String, dynamic> row) =>
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
}

class EligibleMember {
  const EligibleMember({required this.membershipId, required this.displayName});
  final String membershipId;
  final String displayName;
  factory EligibleMember.fromJson(Map<String, dynamic> row) => EligibleMember(
    membershipId: row['membership_id'] as String,
    displayName: row['display_name'] as String,
  );
}

class IamRoleAssignment {
  const IamRoleAssignment({
    required this.assignmentId,
    required this.membershipId,
    required this.roleId,
    required this.roleName,
    required this.protected,
    required this.validFrom,
    this.validUntil,
    this.revokedAt,
  });
  final String assignmentId;
  final String membershipId;
  final String roleId;
  final String roleName;
  final bool protected;
  final DateTime validFrom;
  final DateTime? validUntil;
  final DateTime? revokedAt;
  factory IamRoleAssignment.fromJson(Map<String, dynamic> row) =>
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
}

/// Returns roles without an existing, non-revoked assignment overlapping
/// the prospective grant interval [now, infinity).
List<IamRole> eligibleRolesForGrant({
  required List<IamRole> roles,
  required List<IamRoleAssignment> assignments,
  required String membershipId,
  required DateTime now,
}) {
  final nowUtc = now.toUtc();
  final alreadyAssigned = assignments
      .where(
        (assignment) =>
            assignment.membershipId == membershipId &&
            assignment.revokedAt == null &&
            (assignment.validUntil == null ||
                assignment.validUntil!.toUtc().isAfter(nowUtc)),
      )
      .map((assignment) => assignment.roleId)
      .toSet();
  return roles.where((role) => !alreadyAssigned.contains(role.id)).toList();
}

class AdminOperationResult {
  const AdminOperationResult({
    required this.success,
    required this.code,
    required this.targetId,
    required this.replayed,
  });
  final bool success;
  final String code;
  final String? targetId;
  final bool replayed;
  factory AdminOperationResult.fromJson(Map<String, dynamic> row) =>
      AdminOperationResult(
        success: row['result'] as bool,
        code: row['result_code'] as String,
        targetId:
            row['target_id'] as String? ?? row['assignment_id'] as String?,
        replayed: row['replayed'] as bool,
      );
}
