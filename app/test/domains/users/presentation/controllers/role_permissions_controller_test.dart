import 'dart:async';

import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_operation_attempt_factory.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_ports.dart';
import 'package:carer_record_app/domains/users/presentation/controllers/role_permissions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tracks immutable draft, dirty state, hidden permission and selection',
    () {
      final controller = _controller(_FakeAdministration());
      addTearDown(controller.dispose);
      controller.setCatalog([_permission]);
      controller.selectRole('one');
      expect(controller.dirty, isFalse);
      controller.setPermission('visible', false);
      expect(controller.dirty, isTrue);
      expect(controller.hasHiddenPermissions, isTrue);
      expect(() => controller.draft.add('mutate'), throwsUnsupportedError);
      controller.selectRole('two');
      expect(controller.dirty, isFalse);
      expect(controller.draft, {'visible'});
    },
  );

  test(
    'retry reuses exact snapshot while a new save creates a new attempt',
    () async {
      final admin = _FakeAdministration()
        ..pending = Completer<AdminOperationResult>();
      var refreshed = 0;
      var byte = 0;
      final controller = RolePermissionsController(
        administration: admin,
        attemptFactory: IamOperationAttemptFactory(
          nextByte: () => byte++,
          now: () => DateTime.utc(2026),
        ),
        refreshAuthorization: () => refreshed++,
        organizationId: 'org',
        roles: [_role],
      );
      addTearDown(controller.dispose);
      controller.setCatalog([_permission, _hiddenPermission]);
      controller.selectRole('one');
      controller.setPermission('visible', false);
      final save = controller.save();
      final snapshot = controller.retrySnapshot!;
      expect(controller.busy, isTrue);
      expect(snapshot.organizationId, 'org');
      expect(snapshot.roleId, 'one');
      expect(snapshot.permissions, {'hidden'});
      admin.pending!.completeError(StateError('transport failed'));
      await expectLater(save, throwsStateError);
      expect(controller.busy, isFalse);
      expect(controller.retrySnapshot, same(snapshot));

      admin.pending = Completer<AdminOperationResult>();
      final retry = controller.save(retry: snapshot);
      expect(admin.calls.last.organizationId, snapshot.organizationId);
      expect(admin.calls.last.roleId, snapshot.roleId);
      expect(admin.calls.last.permissions, snapshot.permissions);
      expect(
        admin.calls.last.attempt.idempotencyKey,
        snapshot.attempt.idempotencyKey,
      );
      admin.pending!.complete(
        const AdminOperationResult(
          success: true,
          code: 'permissions_replaced',
          targetId: null,
          replayed: false,
        ),
      );
      expect((await retry)?.success, isTrue);
      expect(controller.busy, isFalse);
      expect(refreshed, 1);
      expect(controller.selectedRoleId, isNull);

      controller.selectRole('one');
      controller.setPermission('visible', false);
      admin.pending = Completer<AdminOperationResult>();
      final next = controller.save();
      expect(
        controller.retrySnapshot!.attempt.idempotencyKey,
        isNot(snapshot.attempt.idempotencyKey),
      );
      admin.pending!.complete(
        const AdminOperationResult(
          success: true,
          code: 'permissions_replaced',
          targetId: null,
          replayed: false,
        ),
      );
      await next;
    },
  );

  test(
    'disposing during an in-flight save suppresses late notifications',
    () async {
      final admin = _FakeAdministration()
        ..pending = Completer<AdminOperationResult>();
      final controller = RolePermissionsController(
        administration: admin,
        attemptFactory: IamOperationAttemptFactory(nextByte: () => 1),
        refreshAuthorization: () {},
        organizationId: 'org',
        roles: [_role],
      );
      controller.setCatalog([_permission, _hiddenPermission]);
      controller.selectRole('one');
      controller.setPermission('visible', false);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final save = controller.save();
      final beforeDispose = notifications;
      controller.dispose();
      expect(controller.busy, isFalse);
      admin.pending!.complete(
        const AdminOperationResult(
          success: true,
          code: 'permissions_replaced',
          targetId: null,
          replayed: false,
        ),
      );
      expect(await save, isNull);
      expect(notifications, beforeDispose);
    },
  );
}

class _FakeAdministration implements IamAdministration {
  Completer<AdminOperationResult>? pending;
  final calls =
      <
        ({
          String organizationId,
          String roleId,
          Set<String> permissions,
          AdminOperationAttempt attempt,
        })
      >[];
  @override
  Future<AdminOperationResult> replaceRolePermissions({
    required String organizationId,
    required String roleId,
    required Iterable<String> permissions,
    required AdminOperationAttempt attempt,
  }) {
    calls.add((
      organizationId: organizationId,
      roleId: roleId,
      permissions: permissions.toSet(),
      attempt: attempt,
    ));
    return pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _role = IamRole(
  id: 'one',
  name: 'Role',
  protected: false,
  permissions: {'visible', 'hidden'},
);
const _permission = IamPermission(
  code: 'visible',
  family: 'general',
  description: 'Visible',
);
const _hiddenPermission = IamPermission(
  code: 'hidden',
  family: 'general',
  description: 'Hidden',
);

RolePermissionsController _controller(IamAdministration admin) =>
    RolePermissionsController(
      administration: admin,
      attemptFactory: IamOperationAttemptFactory(nextByte: () => 1),
      refreshAuthorization: () {},
      organizationId: 'org',
      roles: [
        _role,
        const IamRole(
          id: 'two',
          name: 'Other',
          protected: false,
          permissions: {'visible'},
        ),
      ],
    );
