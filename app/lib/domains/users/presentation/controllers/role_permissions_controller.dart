import 'package:flutter/foundation.dart';

import '../../../../core/session/authorization_refresh.dart';
import '../../../institutional/domain/iam_entities.dart';
import '../../../institutional/domain/iam_operation_attempt_factory.dart';
import '../../../institutional/domain/iam_ports.dart';

class RolePermissionsSaveSnapshot {
  RolePermissionsSaveSnapshot({
    required this.organizationId,
    required this.roleId,
    required Set<String> permissions,
    required this.attempt,
  }) : permissions = Set.unmodifiable(permissions);

  final String organizationId;
  final String roleId;
  final Set<String> permissions;
  final AdminOperationAttempt attempt;
}

class RolePermissionsController extends ChangeNotifier {
  RolePermissionsController({
    required this.administration,
    required this.attemptFactory,
    required this.refreshAuthorization,
    required this.organizationId,
    required List<IamRole> roles,
  }) : _roles = List.unmodifiable(roles);

  final IamAdministration administration;
  final IamOperationAttemptFactory attemptFactory;
  final AuthorizationRefresh refreshAuthorization;
  final String organizationId;
  final List<IamRole> _roles;
  String? _selectedRoleId;
  Set<String> _initial = const {};
  Set<String> _draft = const {};
  bool _busy = false;
  int _generation = 0;
  bool _closed = false;
  RolePermissionsSaveSnapshot? _retrySnapshot;

  String? get selectedRoleId => _selectedRoleId;
  Set<String> get initial => Set.unmodifiable(_initial);
  Set<String> get draft => Set.unmodifiable(_draft);
  bool get dirty => !setEquals(_initial, _draft);
  bool get busy => _busy;
  RolePermissionsSaveSnapshot? get retrySnapshot => _retrySnapshot;
  bool get hasHiddenPermissions {
    final role = _selectedRole;
    return role != null && !_rolesCatalogCodes().containsAll(role.permissions);
  }

  IamRole? get _selectedRole =>
      _roles.where((role) => role.id == _selectedRoleId).firstOrNull;

  Set<String> _rolesCatalogCodes() => _catalogCodes ?? const <String>{};
  Set<String>? _catalogCodes;

  void setCatalog(Iterable<IamPermission> catalog) {
    if (_closed) return;
    _catalogCodes = catalog.map((item) => item.code).toSet();
    notifyListeners();
  }

  void selectRole(String? id) {
    if (_closed || _busy || id == _selectedRoleId) return;
    final role = _roles.where((item) => item.id == id).firstOrNull;
    if (role == null) return;
    _generation++;
    _selectedRoleId = id;
    _initial = Set.unmodifiable(role.permissions);
    _draft = Set.unmodifiable(role.permissions);
    _retrySnapshot = null;
    notifyListeners();
  }

  void setPermission(String code, bool enabled) {
    if (_closed || _busy || _selectedRole == null) return;
    final next = Set<String>.of(_draft);
    enabled ? next.add(code) : next.remove(code);
    _draft = Set.unmodifiable(next);
    _retrySnapshot = null;
    notifyListeners();
  }

  Future<AdminOperationResult?> save({
    RolePermissionsSaveSnapshot? retry,
  }) async {
    if (_closed || _busy || _selectedRoleId == null || hasHiddenPermissions) {
      return null;
    }
    final snapshot =
        retry ??
        RolePermissionsSaveSnapshot(
          organizationId: organizationId,
          roleId: _selectedRoleId!,
          permissions: _draft,
          attempt: attemptFactory.create(),
        );
    _retrySnapshot = snapshot;
    _busy = true;
    final generation = _generation;
    notifyListeners();
    try {
      final result = await administration.replaceRolePermissions(
        organizationId: snapshot.organizationId,
        roleId: snapshot.roleId,
        permissions: snapshot.permissions.toList()..sort(),
        attempt: snapshot.attempt,
      );
      if (_closed || generation != _generation) return null;
      if (result.success) {
        _retrySnapshot = null;
        _selectedRoleId = null;
        _initial = const {};
        _draft = const {};
        // The server mutation is confirmed. A refresh failure cannot safely
        // be represented as a failed mutation because the UI would offer retry.
        try {
          refreshAuthorization();
        } catch (_) {}
      }
      return result;
    } catch (_) {
      if (!_closed && generation == _generation) rethrow;
      return null;
    } finally {
      if (!_closed && generation == _generation) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _busy = false;
    super.dispose();
  }
}
