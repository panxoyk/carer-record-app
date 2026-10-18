import 'package:flutter/foundation.dart';

import '../../../../core/session/authorization_refresh.dart';
import '../../../institutional/domain/iam_operation_attempt_factory.dart';
import '../../../institutional/domain/iam_ports.dart';

class CreateMemberController extends ChangeNotifier {
  CreateMemberController({
    required this.administration,
    required IamOperationAttemptFactory attemptFactory,
    required this.refreshAuthorization,
  }) : _idempotencyKey = attemptFactory.create().idempotencyKey;

  final IamAdministration administration;
  final AuthorizationRefresh refreshAuthorization;
  final String _idempotencyKey;
  bool _busy = false;
  bool _closed = false;
  String? _error;

  bool get busy => _busy;
  String? get error => _error;

  Future<bool> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
  }) async {
    if (_closed || _busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await administration.createMember(
        organizationId: organizationId,
        email: email,
        password: password,
        displayName: displayName,
        roleId: roleId,
        idempotencyKey: _idempotencyKey,
      );
      if (_closed) return false;
      try {
        refreshAuthorization();
      } catch (_) {
        // A confirmed remote creation must not be presented as retryable.
      }
      return true;
    } catch (_) {
      if (_closed) return false;
      _error = 'No fue posible agregar el usuario. Puedes reintentar.';
      return false;
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
