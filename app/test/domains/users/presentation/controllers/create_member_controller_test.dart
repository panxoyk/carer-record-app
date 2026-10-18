import 'dart:async';

import 'package:carer_record_app/core/session/authorization_refresh.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_operation_attempt_factory.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_ports.dart';
import 'package:carer_record_app/domains/users/presentation/controllers/create_member_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('busy prevents duplicate submits and success refreshes', () async {
    final fake = _Administration()..wait = Completer<void>();
    var refreshes = 0;
    final controller = _controller(fake, () => refreshes++);
    final first = controller.createMember(
      organizationId: 'org',
      email: 'a',
      password: 'secret',
      displayName: 'A',
      roleId: 'role',
    );
    expect(controller.busy, isTrue);
    expect(
      await controller.createMember(
        organizationId: 'org',
        email: 'b',
        password: 'secret2',
        displayName: 'B',
        roleId: 'role2',
      ),
      isFalse,
    );
    expect(fake.calls, 1);
    fake.wait!.complete();
    expect(await first, isTrue);
    expect(refreshes, 1);
    controller.dispose();
  });

  test('retry uses the stable form key and current edited fields', () async {
    final fake = _Administration()..failures = 1;
    final controller = _controller(fake, () {});
    Future<bool> submit(String email, String password) =>
        controller.createMember(
          organizationId: 'org',
          email: email,
          password: password,
          displayName: email,
          roleId: 'role',
        );
    expect(await submit('original', 'secret-original'), isFalse);
    expect(await submit('edited', 'secret-edited'), isTrue);
    expect(fake.calls, 2);
    expect(fake.idempotencyKeys.toSet().length, 1);
    expect(fake.inputs.map((input) => input.$1), ['original', 'edited']);
    expect(fake.inputs.map((input) => input.$2), [
      'secret-original',
      'secret-edited',
    ]);
    controller.dispose();
  });

  test('dispose suppresses late result and notifications', () async {
    final fake = _Administration()..wait = Completer<void>();
    var refreshes = 0;
    var notifications = 0;
    final controller = _controller(fake, () => refreshes++);
    controller.addListener(() => notifications++);
    final pending = controller.createMember(
      organizationId: 'org',
      email: 'a',
      password: 'secret',
      displayName: 'A',
      roleId: 'role',
    );
    final before = notifications;
    controller.dispose();
    fake.wait!.complete();
    expect(await pending, isFalse);
    expect(refreshes, 0);
    expect(notifications, before);
  });
}

CreateMemberController _controller(
  _Administration fake,
  AuthorizationRefresh refresh,
) => CreateMemberController(
  administration: fake,
  attemptFactory: IamOperationAttemptFactory(nextByte: () => 1),
  refreshAuthorization: refresh,
);

class _Administration implements IamAdministration {
  int failures = 0;
  int calls = 0;
  Completer<void>? wait;
  final idempotencyKeys = <String>[];
  final inputs = <(String, String)>[];

  @override
  Future<void> createMember({
    required String organizationId,
    required String email,
    required String password,
    required String displayName,
    required String roleId,
    required String idempotencyKey,
  }) async {
    calls++;
    idempotencyKeys.add(idempotencyKey);
    inputs.add((email, password));
    if (failures-- > 0) throw StateError('synthetic');
    if (wait != null) await wait!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
