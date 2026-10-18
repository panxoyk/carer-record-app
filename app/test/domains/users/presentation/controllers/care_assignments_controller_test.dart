import 'dart:async';

import 'package:carer_record_app/core/session/authorization_refresh.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_operation_attempt_factory.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_ports.dart';
import 'package:carer_record_app/domains/users/presentation/controllers/care_assignments_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry preserves grant snapshot; a new action gets a new key', () async {
    final fake = _FakeAdministration()..failNext = true;
    var refreshes = 0;
    final controller = _controller(fake, refresh: () => refreshes++);
    await expectLater(
      controller.grant(
        hospitalizationId: 'episode-a',
        membershipId: 'member-a',
      ),
      throwsStateError,
    );
    final snapshot = controller.retrySnapshot!;
    expect(snapshot.organizationId, 'org-a');
    expect(snapshot.hospitalizationId, 'episode-a');
    expect(snapshot.membershipId, 'member-a');
    expect(snapshot.attempt.validFrom, DateTime.utc(2026, 1, 2));
    await controller.retry(snapshot);
    expect(fake.grants[1].attempt, same(fake.grants[0].attempt));
    expect(
      fake.grants[1].attempt.idempotencyKey,
      snapshot.attempt.idempotencyKey,
    );
    await controller.grant(
      hospitalizationId: 'episode-b',
      membershipId: 'member-b',
    );
    expect(fake.grants[2].hospitalizationId, 'episode-b');
    expect(
      fake.grants[2].attempt.idempotencyKey,
      isNot(snapshot.attempt.idempotencyKey),
    );
    await controller.retry(snapshot);
    expect(fake.grants.last.hospitalizationId, 'episode-a');
    expect(fake.grants.last.membershipId, 'member-a');
    expect(fake.grants.last.attempt, same(snapshot.attempt));
    expect(refreshes, 3);
    controller.dispose();
  });

  test(
    'revoke retry retains assignment target and success refreshes',
    () async {
      final fake = _FakeAdministration()..failNext = true;
      var refreshes = 0;
      final controller = _controller(fake, refresh: () => refreshes++);
      await expectLater(
        controller.revoke(assignmentId: 'assignment-a'),
        throwsStateError,
      );
      final snapshot = controller.retrySnapshot!;
      expect(snapshot.targetId, 'assignment-a');
      await controller.retry(snapshot);
      expect(fake.revokes.last, ('org-a', 'assignment-a'));
      expect(refreshes, 1);
      controller.dispose();
    },
  );

  test(
    'busy rejects concurrent action and dispose suppresses late completion',
    () async {
      final fake = _FakeAdministration()
        ..pending = Completer<AdminOperationResult>();
      final controller = _controller(fake);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final operation = controller.grant(
        hospitalizationId: 'episode-a',
        membershipId: 'member-a',
      );
      expect(controller.busy, isTrue);
      expect(
        await controller.grant(
          hospitalizationId: 'episode-b',
          membershipId: 'member-b',
        ),
        isNull,
      );
      controller.dispose();
      fake.pending!.complete(_success);
      expect(await operation, isNull);
      expect(notifications, 1);
    },
  );
}

final _success = AdminOperationResult(
  success: true,
  code: 'ok',
  targetId: 'target',
  replayed: false,
);

CareAssignmentsController _controller(
  _FakeAdministration fake, {
  AuthorizationRefresh refresh = _noop,
}) {
  var next = 0;
  return CareAssignmentsController(
    administration: fake,
    attemptFactory: IamOperationAttemptFactory(
      nextByte: () => next++,
      now: () => DateTime.utc(2026, 1, 2),
    ),
    refreshAuthorization: refresh,
    organizationId: 'org-a',
  );
}

void _noop() {}

class _FakeAdministration implements CareAssignmentAdministration {
  bool failNext = false;
  Completer<AdminOperationResult>? pending;
  final grants =
      <
        ({
          String organizationId,
          String hospitalizationId,
          String membershipId,
          AdminOperationAttempt attempt,
        })
      >[];
  final revokes = <(String, String)>[];

  Future<AdminOperationResult> _result() async {
    if (pending != null) return pending!.future;
    if (failNext) {
      failNext = false;
      throw StateError('remote failure');
    }
    return _success;
  }

  @override
  Future<AdminOperationResult> grantCareAssignment({
    required String organizationId,
    required String hospitalizationId,
    required String membershipId,
    required AdminOperationAttempt attempt,
  }) async {
    grants.add((
      organizationId: organizationId,
      hospitalizationId: hospitalizationId,
      membershipId: membershipId,
      attempt: attempt,
    ));
    return _result();
  }

  @override
  Future<AdminOperationResult> revokeCareAssignment({
    required String organizationId,
    required String assignmentId,
    required AdminOperationAttempt attempt,
  }) async {
    revokes.add((organizationId, assignmentId));
    return _result();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
