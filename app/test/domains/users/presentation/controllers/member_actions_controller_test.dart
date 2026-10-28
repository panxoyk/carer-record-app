import 'dart:async';

import 'package:carer_record_app/core/session/authorization_refresh.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_operation_attempt_factory.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_ports.dart';
import 'package:carer_record_app/domains/users/presentation/controllers/member_actions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success refreshes authorization', () async {
    final fake = _Administration();
    var refreshed = 0;
    final controller = _controller(fake, () => refreshed++);
    final result = await controller.updateMembership('suspended');
    expect(result?.success, isTrue);
    expect(refreshed, 1);
    expect(fake.status, 'suspended');
    controller.dispose();
  });

  test(
    'retry preserves exact inputs and attempt; a new action gets a new key',
    () async {
      final fake = _Administration()..failures = 1;
      final controller = _controller(fake, () {});
      await expectLater(
        controller.grantRole('role-original'),
        throwsStateError,
      );
      final first = fake.attempts.single;
      expect(first.validFrom?.isUtc, isTrue);
      await controller.retry(controller.retrySnapshot!);
      expect(fake.attempts.last.idempotencyKey, first.idempotencyKey);
      expect(fake.attempts.last.validFrom, first.validFrom);
      expect(fake.grantedRoleIds, ['role-original', 'role-original']);
      await controller.grantRole('role-next');
      expect(fake.attempts.last.idempotencyKey, isNot(first.idempotencyKey));
      controller.dispose();
    },
  );

  test(
    'captured retry keeps its operation and target after a newer action',
    () async {
      final fake = _Administration()..failures = 2;
      final controller = _controller(fake, () {});
      await expectLater(controller.grantRole('role-old'), throwsStateError);
      final previous = controller.retrySnapshot!;
      await expectLater(
        controller.revokeRole('assignment-new'),
        throwsStateError,
      );
      expect(controller.retrySnapshot!.kind, MemberActionKind.revokeRole);
      expect(controller.retrySnapshot!.targetId, 'assignment-new');

      await controller.retry(previous);
      expect(fake.grantedRoleIds, ['role-old', 'role-old']);
      expect(fake.revokedAssignmentIds, ['assignment-new']);
      expect(fake.attempts[0].idempotencyKey, fake.attempts[2].idempotencyKey);
      expect(previous.kind, MemberActionKind.grantRole);
      expect(previous.targetId, 'member');
      expect(previous.roleId, 'role-old');
      expect(controller.retrySnapshot, isNull);
      controller.dispose();
    },
  );

  test(
    'busy rejects concurrent calls and dispose suppresses late effects',
    () async {
      final fake = _Administration()..wait = Completer<AdminOperationResult>();
      var refreshes = 0;
      var notifications = 0;
      final controller = _controller(fake, () => refreshes++);
      controller.addListener(() => notifications++);
      final pending = controller.updateMembership('suspended');
      expect(await controller.revokeRole('assignment'), isNull);
      expect(fake.calls, 1);
      controller.dispose();
      final before = notifications;
      fake.wait!.complete(
        const AdminOperationResult(
          success: true,
          code: 'ok',
          targetId: null,
          replayed: false,
        ),
      );
      await pending;
      expect(refreshes, 0);
      expect(notifications, before);
    },
  );
}

MemberActionsController _controller(
  _Administration fake,
  AuthorizationRefresh refresh,
) => MemberActionsController(
  administration: fake,
  attemptFactory: IamOperationAttemptFactory(
    nextByte: _nextByte,
    now: () => DateTime(2026, 1, 1),
  ),
  refreshAuthorization: refresh,
  organizationId: 'org',
  membershipId: 'member',
);

int _byte = 0;
int _nextByte() => _byte++ & 255;

class _Administration implements IamAdministration {
  int failures = 0;
  int calls = 0;
  Completer<AdminOperationResult>? wait;
  final attempts = <AdminOperationAttempt>[];
  final grantedRoleIds = <String>[];
  final revokedAssignmentIds = <String>[];
  String? status;

  Future<AdminOperationResult> _result(AdminOperationAttempt attempt) async {
    calls++;
    attempts.add(attempt);
    if (failures-- > 0) throw StateError('synthetic');
    if (wait != null) return wait!.future;
    return const AdminOperationResult(
      success: true,
      code: 'ok',
      targetId: null,
      replayed: false,
    );
  }

  @override
  Future<AdminOperationResult> updateMembership({
    required String organizationId,
    required String membershipId,
    required String status,
    required AdminOperationAttempt attempt,
  }) {
    this.status = status;
    return _result(attempt);
  }

  @override
  Future<AdminOperationResult> grantRole({
    required String organizationId,
    required String membershipId,
    required String roleId,
    required AdminOperationAttempt attempt,
  }) {
    grantedRoleIds.add(roleId);
    return _result(attempt);
  }

  @override
  Future<AdminOperationResult> revokeRole({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) {
    revokedAssignmentIds.add(assignmentId);
    return _result(attempt);
  }

  @override
  Future<List<IamPermission>> delegablePermissions() async => [];
  @override
  Future<List<IamMember>> members(String organizationId) async => [];
  @override
  Future<List<IamRole>> roles(String organizationId) async => [];
  @override
  Future<Map<String, List<IamRoleAssignment>>> roleAssignments(
    String organizationId,
  ) async => {};
  @override
  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  }) => _result(attempt);
  @override
  Future<AdminOperationResult> createRole({
    required String organizationId,
    required String name,
    required String description,
    required AdminOperationAttempt attempt,
  }) => _result(attempt);
  @override
  Future<void> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
    required String idempotencyKey,
  }) async {}
}
