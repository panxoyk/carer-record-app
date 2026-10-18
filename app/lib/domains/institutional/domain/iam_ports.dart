import 'iam_entities.dart';

abstract interface class IamContextReader {
  Future<List<IamContext>> currentContexts();
}

abstract interface class IamAdministration {
  Future<List<IamPermission>> delegablePermissions();
  Future<List<IamMember>> members(String organizationId);
  Future<List<IamRole>> roles(String organizationId);
  Future<Map<String, List<IamRoleAssignment>>> roleAssignments(
    String organizationId,
  );
  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  });
  Future<void> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
    required String idempotencyKey,
  });
  Future<AdminOperationResult> updateMembership({
    required String organizationId,
    required String membershipId,
    required String status,
    required AdminOperationAttempt attempt,
  });
  Future<AdminOperationResult> grantRole({
    required String organizationId,
    required String membershipId,
    required String roleId,
    required AdminOperationAttempt attempt,
  });
  Future<AdminOperationResult> revokeRole({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  });
}

abstract interface class CareAssignmentAdministration {
  Future<List<CareAssignmentRecord>> assignments(String organizationId);
  Future<List<EligibleMember>> eligibleMembers(String organizationId);
  Future<AdminOperationResult> grantCareAssignment({
    required String organizationId,
    required String hospitalizationId,
    required String membershipId,
    required AdminOperationAttempt attempt,
  });
  Future<AdminOperationResult> revokeCareAssignment({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  });
}

abstract interface class AuthorizedPatientNamesReader {
  Future<Map<String, String>> censusPatientNames(String organizationId);
}
