import 'package:flutter/foundation.dart';

import '../../../../core/session/authorization_refresh.dart';
import '../../../institutional/domain/iam_entities.dart';
import '../../../institutional/domain/iam_operation_attempt_factory.dart';
import '../../../institutional/domain/iam_ports.dart';

enum MemberActionKind { updateMembership, grantRole, revokeRole }

class MemberActionSnapshot {
  const MemberActionSnapshot({
    required this.kind,
    required this.organizationId,
    required this.targetId,
    required this.attempt,
    this.status,
    this.roleId,
  });
  final MemberActionKind kind;
  final String organizationId;
  final String targetId;
  final String? status;
  final String? roleId;
  final AdminOperationAttempt attempt;
}

class MemberActionsController extends ChangeNotifier {
  MemberActionsController({
    required this.administration,
    required this.attemptFactory,
    required this.refreshAuthorization,
    required this.organizationId,
    required this.membershipId,
  });

  final IamAdministration administration;
  final IamOperationAttemptFactory attemptFactory;
  final AuthorizationRefresh refreshAuthorization;
  final String organizationId;
  final String membershipId;
  bool _busy = false;
  bool _closed = false;
  MemberActionSnapshot? _retrySnapshot;

  bool get busy => _busy;
  MemberActionSnapshot? get retrySnapshot => _retrySnapshot;

  Future<AdminOperationResult?> updateMembership(String status) => _run(
    MemberActionSnapshot(
      kind: MemberActionKind.updateMembership,
      organizationId: organizationId,
      targetId: membershipId,
      status: status,
      attempt: attemptFactory.create(),
    ),
  );

  Future<AdminOperationResult?> grantRole(String roleId) => _run(
    MemberActionSnapshot(
      kind: MemberActionKind.grantRole,
      organizationId: organizationId,
      targetId: membershipId,
      roleId: roleId,
      attempt: attemptFactory.create(usesValidFrom: true),
    ),
  );

  Future<AdminOperationResult?> revokeRole(String assignmentId) => _run(
    MemberActionSnapshot(
      kind: MemberActionKind.revokeRole,
      organizationId: organizationId,
      targetId: assignmentId,
      attempt: attemptFactory.create(),
    ),
  );

  Future<AdminOperationResult?> retry(MemberActionSnapshot snapshot) {
    if (_closed) return Future.value(null);
    return _run(snapshot);
  }

  Future<AdminOperationResult?> _run(MemberActionSnapshot snapshot) async {
    if (_closed || _busy) return null;
    _busy = true;
    _retrySnapshot = snapshot;
    notifyListeners();
    try {
      final result = switch (snapshot.kind) {
        MemberActionKind.updateMembership =>
          await administration.updateMembership(
            organizationId: snapshot.organizationId,
            membershipId: snapshot.targetId,
            status: snapshot.status!,
            attempt: snapshot.attempt,
          ),
        MemberActionKind.grantRole => await administration.grantRole(
          organizationId: snapshot.organizationId,
          membershipId: snapshot.targetId,
          roleId: snapshot.roleId!,
          attempt: snapshot.attempt,
        ),
        MemberActionKind.revokeRole => await administration.revokeRole(
          organizationId: snapshot.organizationId,
          assignmentId: snapshot.targetId,
          attempt: snapshot.attempt,
        ),
      };
      if (_closed) return null;
      if (result.success) {
        _retrySnapshot = null;
        try {
          refreshAuthorization();
        } catch (_) {}
      }
      return result;
    } catch (_) {
      if (_closed) return null;
      rethrow;
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _busy = false;
    super.dispose();
  }
}
