import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'IAM context combines permission rows without transport identity fields',
    () {
      final context = IamContext.fromRows([
        _contextRow('iam.membership.read'),
        _contextRow('clinical.assignment.manage'),
      ]).single;
      expect(context.organizationId, 'org-1');
      expect(context.membershipStatus, 'active');
      expect(context.allows('iam.membership.read'), isTrue);
      expect(context.allows('iam.role.assign'), isFalse);
    },
  );

  test(
    'IAM context without rows is not accepted as an authenticated context',
    () {
      expect(IamContext.fromRows([]), isEmpty);
    },
  );

  test('contexts group permissions by organization and membership', () {
    final contexts = IamContext.fromRows([
      _contextRow('iam.membership.read'),
      {
        ..._contextRow('clinical.patient.read'),
        'organization_id': 'org-2',
        'organization_name': 'Otra',
      },
    ]);
    expect(contexts, hasLength(2));
    expect(contexts.first.allows('clinical.patient.read'), isFalse);
    expect(contexts.last.allows('clinical.patient.read'), isTrue);
    expect(IamContext.select(contexts, null), isNull);
    expect(IamContext.select(contexts, 'org-2')?.organizationId, 'org-2');
    expect(IamContext.select([contexts.first], null), same(contexts.first));
    expect(
      IamContext.selectForSession(
        contexts,
        const OrganizationSelection(
          userId: 'old-user',
          organizationId: 'org-2',
        ),
        'current-user',
      ),
      isNull,
    );
    expect(
      () => IamContext.fromRows([
        _contextRow('iam.membership.read'),
        {
          ..._contextRow('clinical.patient.read'),
          'membership_id': 'membership-2',
        },
      ]),
      throwsFormatException,
    );
  });

  test('membership and assignment transport models parse typed fields', () {
    final member = IamMember.fromJson({
      'membership_id': 'membership-1',
      'profile_id': 'profile-1',
      'display_name': 'Persona sintética',
      'profile_status': 'active',
      'membership_status': 'suspended',
      'valid_from': '2026-10-11T10:00:00Z',
      'valid_until': null,
    });
    expect(member.membershipStatus, 'suspended');
    expect(member.validFrom, DateTime.utc(2026, 10, 11, 10));
    final assignment = CareAssignmentRecord.fromJson({
      'hospitalization_id': 'episode-1',
      'hospitalization_status': 'admitted',
      'admitted_at': '2026-10-11T10:00:00Z',
      'assignment_id': 'assignment-1',
      'membership_id': 'membership-1',
      'assignment_valid_from': '2026-10-11T10:00:00Z',
      'assignment_valid_until': null,
      'revoked_at': null,
      'assignee_display_name': 'Profesional histórico',
      'assignee_membership_status': 'suspended',
    });
    expect(assignment.validUntil, isNull);
    expect(assignment.admittedAt.isUtc, isTrue);
    expect(assignment.assigneeDisplayName, 'Profesional histórico');
    expect(assignment.assigneeMembershipStatus, 'suspended');
  });

  test(
    'new assignment eligibility requires active status and current interval',
    () {
      final now = DateTime.utc(2026, 10, 12);
      IamMember member({
        String profile = 'active',
        String membership = 'active',
        DateTime? from,
        DateTime? until,
      }) => IamMember(
        membershipId: 'membership',
        profileId: 'profile',
        displayName: 'Persona',
        profileStatus: profile,
        membershipStatus: membership,
        validFrom: from,
        validUntil: until,
      );

      expect(isEligibleForNewAssignment(member(), now: now), isTrue);
      expect(
        isEligibleForNewAssignment(member(profile: 'suspended'), now: now),
        isFalse,
      );
      expect(
        isEligibleForNewAssignment(member(membership: 'suspended'), now: now),
        isFalse,
      );
      expect(
        isEligibleForNewAssignment(
          member(from: now.add(const Duration(seconds: 1))),
          now: now,
        ),
        isFalse,
      );
      expect(isEligibleForNewAssignment(member(until: now), now: now), isFalse);
    },
  );

  test('directory visibility requires an active profile and active or suspended membership', () {
    IamMember member(String profile, String membership) => IamMember(
      membershipId: 'membership',
      profileId: 'profile',
      displayName: 'Persona',
      profileStatus: profile,
      membershipStatus: membership,
    );

    expect(isVisibleInMemberDirectory(member('active', 'active')), isTrue);
    expect(isVisibleInMemberDirectory(member('active', 'suspended')), isTrue);
    expect(isVisibleInMemberDirectory(member('active', 'invited')), isFalse);
    expect(isVisibleInMemberDirectory(member('active', 'ended')), isFalse);
    expect(isVisibleInMemberDirectory(member('suspended', 'active')), isFalse);
    expect(
      isVisibleInMemberDirectory(member('suspended', 'suspended')),
      isFalse,
    );
  });

  test('role assignment parses its role ID for grant eligibility', () {
    final assignment = IamRoleAssignment.fromJson({
      'assignment_id': 'assignment-1',
      'membership_id': 'membership-1',
      'role_id': 'role-1',
      'role_name': 'Personal',
      'protected_kind': null,
      'valid_from': '2026-10-11T10:00:00Z',
      'valid_until': null,
      'revoked_at': null,
    });
    expect(assignment.roleId, 'role-1');
  });

  test(
    'grant eligibility excludes overlapping grants by membership and role ID',
    () {
      final now = DateTime.utc(2026, 10, 12);
      const sameNameDifferentRole = IamRole(
        id: 'role-2',
        name: 'Personal',
        protected: false,
        permissions: {},
      );
      const roles = [
        IamRole(
          id: 'role-1',
          name: 'Renamed',
          protected: false,
          permissions: {},
        ),
        sameNameDifferentRole,
      ];
      IamRoleAssignment assignment({
        required String roleId,
        String membershipId = 'member-1',
        DateTime? validFrom,
        DateTime? validUntil,
        DateTime? revokedAt,
      }) => IamRoleAssignment(
        assignmentId: 'assignment',
        membershipId: membershipId,
        roleId: roleId,
        roleName: 'Historical name',
        protected: false,
        validFrom: validFrom ?? now,
        validUntil: validUntil,
        revokedAt: revokedAt,
      );

      expect(
        eligibleRolesForGrant(
          roles: roles,
          assignments: [assignment(roleId: 'role-1')],
          membershipId: 'member-1',
          now: now,
        ).map((role) => role.id),
        ['role-2'],
      );
      expect(
        eligibleRolesForGrant(
          roles: roles,
          assignments: [
            assignment(
              roleId: 'role-1',
              validFrom: now.add(const Duration(days: 1)),
            ),
          ],
          membershipId: 'member-1',
          now: now,
        ).map((role) => role.id),
        ['role-2'],
      );
      for (final historical in [
        assignment(roleId: 'role-1', revokedAt: now),
        assignment(roleId: 'role-1', validUntil: now),
        assignment(roleId: 'role-1', membershipId: 'other-member'),
      ]) {
        expect(
          eligibleRolesForGrant(
            roles: roles,
            assignments: [historical],
            membershipId: 'member-1',
            now: now,
          ).map((role) => role.id),
          ['role-1', 'role-2'],
        );
      }
    },
  );

  test('idempotency keys are RFC 4122 version 4 UUIDs', () {
    final key = newIdempotencyKey();
    expect(
      key,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test(
    'a new gesture creates a distinct UUIDv4 attempt with UTC validFrom',
    () {
      final first = newAdminOperationAttempt(usesValidFrom: true);
      final second = newAdminOperationAttempt(usesValidFrom: true);
      expect(first.idempotencyKey, isNot(second.idempotencyKey));
      expect(first.validFrom!.isUtc, isTrue);
      expect(second.validFrom!.isUtc, isTrue);
    },
  );

  test(
    'grant RPCs reject an attempt without validFrom before network access',
    () {
      final repository = IamRepository(
        SupabaseClient('http://127.0.0.1:54321', 'synthetic-test-key'),
      );
      final attempt = AdminOperationAttempt(
        idempotencyKey: newIdempotencyKey(),
      );
      expect(
        () => repository.grantRole(
          organizationId: 'org',
          membershipId: 'membership',
          roleId: 'role',
          attempt: attempt,
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.grantCareAssignment(
          organizationId: 'org',
          hospitalizationId: 'hospitalization',
          membershipId: 'membership',
          attempt: attempt,
        ),
        throwsArgumentError,
      );
    },
  );
}

Map<String, dynamic> _contextRow(String? permission) => {
  'organization_id': 'org-1',
  'organization_name': 'Hospital sintético',
  'profile_id': 'profile-1',
  'display_name': 'Admin sintético',
  'profile_status': 'active',
  'membership_id': 'membership-1',
  'membership_status': 'active',
  'permission_code': permission,
};
