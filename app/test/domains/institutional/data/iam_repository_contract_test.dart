// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/institutional/data/iam_repository.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'institutional reads preserve their selected columns and filters',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repository = IamRepository(client);
      await repository.currentContexts();
      await repository.members('org-1');
      await repository.roleAssignments('org-1');
      await repository.assignments('org-1');
      await repository.eligibleMembers('org-1');
      await repository.censusPatientNames('org-1');

      expect(requests.map((request) => request.url.pathSegments.last), [
        'iam_current_context',
        'iam_member_directory',
        'iam_member_role_assignments',
        'iam_assignment_hospitalizations',
        'iam_assignment_eligible_members',
        'clinical_census_by_hospitalization',
      ]);
      expect(requests[0].url.queryParameters['select'], '*');
      expect(requests[1].url.queryParameters, {
        'select': '*',
        'organization_id': 'eq.org-1',
        'order': 'display_name.desc.nullslast',
      });
      expect(requests[2].url.queryParameters, {
        'select': '*',
        'organization_id': 'eq.org-1',
      });
      expect(requests[3].url.queryParameters, {
        'select': 'hospitalization_id,hospitalization_status,admitted_at,assignment_id,membership_id,assignment_valid_from,assignment_valid_until,revoked_at,assignee_display_name,assignee_membership_status',
        'organization_id': 'eq.org-1',
        'order': 'admitted_at.desc.nullslast',
      });
      expect(requests[4].url.queryParameters, {
        'select': '*',
        'organization_id': 'eq.org-1',
        'order': 'display_name.desc.nullslast',
      });
      expect(requests[5].url.queryParameters, {
        'select': 'hospitalization_id,given_name,family_name',
        'organization_id': 'eq.org-1',
      });
    },
  );

  test(
    'member mutation and creation preserve RPC and Edge payload contracts',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final body =
              request.url.path.endsWith('/rpc/manage_organization_membership')
              ? jsonEncode([
                  {
                    'result': true,
                    'result_code': 'applied',
                    'target_id': 'membership-1',
                    'replayed': false,
                  },
                ])
              : jsonEncode({'ok': true});
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repository = IamRepository(client);
      await repository.updateMembership(
        organizationId: 'org-1',
        membershipId: 'membership-1',
        status: 'suspended',
        attempt: AdminOperationAttempt(idempotencyKey: 'attempt-key'),
      );
      await repository.createMember(
        organizationId: 'org-1',
        email: '  user@example.test  ',
        password: 'synthetic-password',
        displayName: '  Example User  ',
        roleId: 'role-1',
        idempotencyKey: 'create-key',
      );

      expect(
        requests[0].url.path,
        '/rest/v1/rpc/manage_organization_membership',
      );
      expect(jsonDecode(requests[0].body), {
        'p_organization_id': 'org-1',
        'p_membership_id': 'membership-1',
        'p_status': 'suspended',
        'p_valid_until': null,
        'p_idempotency_key': 'attempt-key',
      });
      expect(requests[1].url.path, '/functions/v1/create-practitioner');
      expect(jsonDecode(requests[1].body), {
        'organizationId': 'org-1',
        'email': 'user@example.test',
        'password': 'synthetic-password',
        'displayName': 'Example User',
        'roleId': 'role-1',
        'idempotencyKey': 'create-key',
      });
    },
  );

  test(
    'role and care RPCs preserve validFrom and idempotency payloads',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode([
              {
                'result': true,
                'result_code': 'applied',
                'target_id': 'target-1',
                'replayed': false,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      final repository = IamRepository(client);
      final attempt = AdminOperationAttempt(
        idempotencyKey: 'retry-key',
        validFrom: DateTime.utc(2026, 10, 18, 12, 30),
      );
      await repository.grantRole(
        organizationId: 'org-1',
        membershipId: 'member-1',
        roleId: 'role-1',
        attempt: attempt,
      );
      await repository.revokeRole(
        organizationId: 'org-1',
        assignmentId: 'role-assignment-1',
        attempt: attempt,
      );
      await repository.grantCareAssignment(
        organizationId: 'org-1',
        hospitalizationId: 'hospitalization-1',
        membershipId: 'member-1',
        attempt: attempt,
      );
      await repository.revokeCareAssignment(
        organizationId: 'org-1',
        assignmentId: 'care-assignment-1',
        attempt: attempt,
      );

      expect(requests.map((request) => request.url.path), [
        '/rest/v1/rpc/grant_iam_role',
        '/rest/v1/rpc/revoke_iam_role',
        '/rest/v1/rpc/grant_care_assignment',
        '/rest/v1/rpc/revoke_care_assignment',
      ]);
      expect(jsonDecode(requests[0].body), {
        'p_organization_id': 'org-1',
        'p_membership_id': 'member-1',
        'p_role_id': 'role-1',
        'p_valid_from': '2026-10-18T12:30:00.000Z',
        'p_valid_until': null,
        'p_idempotency_key': 'retry-key',
      });
      expect(jsonDecode(requests[1].body), {
        'p_organization_id': 'org-1',
        'p_assignment_id': 'role-assignment-1',
        'p_idempotency_key': 'retry-key',
      });
      expect(jsonDecode(requests[2].body), {
        'p_organization_id': 'org-1',
        'p_hospitalization_id': 'hospitalization-1',
        'p_membership_id': 'member-1',
        'p_valid_from': '2026-10-18T12:30:00.000Z',
        'p_valid_until': null,
        'p_idempotency_key': 'retry-key',
      });
      expect(jsonDecode(requests[3].body), {
        'p_organization_id': 'org-1',
        'p_assignment_id': 'care-assignment-1',
        'p_idempotency_key': 'retry-key',
      });
    },
  );
}
