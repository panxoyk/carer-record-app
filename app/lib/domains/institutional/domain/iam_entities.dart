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
  final String? assigneeDisplayName;
  final String? assigneeMembershipStatus;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? revokedAt;
}

class EligibleMember {
  const EligibleMember({required this.membershipId, required this.displayName});
  final String membershipId;
  final String displayName;
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
}

List<IamRole> eligibleRolesForGrant({
  required List<IamRole> roles,
  required List<IamRoleAssignment> assignments,
  required String membershipId,
  required DateTime now,
}) {
  final nowUtc = now.toUtc();
  final assigned = assignments
      .where(
        (assignment) =>
            assignment.membershipId == membershipId &&
            assignment.revokedAt == null &&
            (assignment.validUntil == null ||
                assignment.validUntil!.toUtc().isAfter(nowUtc)),
      )
      .map((assignment) => assignment.roleId)
      .toSet();
  return roles.where((role) => !assigned.contains(role.id)).toList();
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
}
