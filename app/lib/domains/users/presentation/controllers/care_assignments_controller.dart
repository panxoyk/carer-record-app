import 'package:flutter/foundation.dart';

import '../../../../core/session/authorization_refresh.dart';
import '../../../institutional/domain/iam_entities.dart';
import '../../../institutional/domain/iam_operation_attempt_factory.dart';
import '../../../institutional/domain/iam_ports.dart';

enum CareAssignmentAction { grant, revoke }

class CareAssignmentSnapshot {
  const CareAssignmentSnapshot({
    required this.action,
    required this.organizationId,
    required this.targetId,
    required this.attempt,
    this.hospitalizationId,
    this.membershipId,
  });
  final CareAssignmentAction action;
  final String organizationId;
  final String targetId;
  final String? hospitalizationId;
  final String? membershipId;
  final AdminOperationAttempt attempt;
}

class CareAssignmentsController extends ChangeNotifier {
  CareAssignmentsController({
    required this.administration,
    required this.attemptFactory,
    required this.refreshAuthorization,
    required this.organizationId,
  });
  final CareAssignmentAdministration administration;
  final IamOperationAttemptFactory attemptFactory;
  final AuthorizationRefresh refreshAuthorization;
  final String organizationId;
  bool _busy = false;
  bool _closed = false;
  CareAssignmentSnapshot? _retrySnapshot;
  bool get busy => _busy;
  CareAssignmentSnapshot? get retrySnapshot => _retrySnapshot;

  Future<AdminOperationResult?> grant({
    required String hospitalizationId,
    required String membershipId,
  }) => _run(
    CareAssignmentSnapshot(
      action: CareAssignmentAction.grant,
      organizationId: organizationId,
      targetId: membershipId,
      hospitalizationId: hospitalizationId,
      membershipId: membershipId,
      attempt: attemptFactory.create(usesValidFrom: true),
    ),
  );
  Future<AdminOperationResult?> revoke({required String assignmentId}) => _run(
    CareAssignmentSnapshot(
      action: CareAssignmentAction.revoke,
      organizationId: organizationId,
      targetId: assignmentId,
      attempt: attemptFactory.create(),
    ),
  );
  Future<AdminOperationResult?> retry(CareAssignmentSnapshot snapshot) =>
      _closed ? Future.value(null) : _run(snapshot);

  Future<AdminOperationResult?> _run(CareAssignmentSnapshot snapshot) async {
    if (_closed || _busy) return null;
    _busy = true;
    _retrySnapshot = snapshot;
    notifyListeners();
    try {
      final result = snapshot.action == CareAssignmentAction.grant
          ? await administration.grantCareAssignment(
              organizationId: snapshot.organizationId,
              hospitalizationId: snapshot.hospitalizationId!,
              membershipId: snapshot.membershipId!,
              attempt: snapshot.attempt,
            )
          : await administration.revokeCareAssignment(
              organizationId: snapshot.organizationId,
              assignmentId: snapshot.targetId,
              attempt: snapshot.attempt,
            );
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
    _closed = true;
    _busy = false;
    super.dispose();
  }
}
