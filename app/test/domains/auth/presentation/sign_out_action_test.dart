import 'dart:async';

import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/core/design_system/clinical_toast.dart';
import 'package:carer_record_app/core/session/session_artifact_cleanup.dart';
import 'package:carer_record_app/domains/auth/data/auth_repository.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/auth/presentation/sign_out_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('failure can retry from sign-out button after toast expires', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    repository.failure = true;
    final gate = GlobalKey<_HostState>();
    await tester.pumpWidget(_app(repository, gate));
    try {
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(find.text('No fue posible cerrar sesión.'), findsOneWidget);

      repository.failure = false;
      repository.pending = Completer<void>();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('No fue posible cerrar sesión.'), findsNothing);
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pump();
      expect(repository.calls, 2);
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pump();
      expect(repository.calls, 2);
      repository.pending!.complete();
      await tester.pump();
      expect(find.text('No fue posible cerrar sesión.'), findsNothing);
    } finally {
      ClinicalToast.dismissAll();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets('successful auth remains successful when cleanup fails', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    var cleanups = 0;
    await tester.pumpWidget(
      _app(
        repository,
        GlobalKey<_HostState>(),
        cleanup: () async {
          cleanups++;
          throw StateError('cleanup failed');
        },
      ),
    );
    try {
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(cleanups, 1);
      expect(find.text('No fue posible cerrar sesión.'), findsNothing);
      expect(find.textContaining('La sesión se cerró'), findsOneWidget);
    } finally {
      ClinicalToast.dismissAll();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Widget _app(
  _FakeAuthRepository repository,
  GlobalKey<_HostState> key, {
  SessionArtifactCleanup? cleanup,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    if (cleanup != null)
      sessionArtifactCleanupProvider.overrideWithValue(cleanup),
  ],
  child: MaterialApp(
    theme: ClinicalTheme.build(),
    builder: (context, child) => ClinicalToastHost(child: child!),
    home: _Host(key: key),
  ),
);

class _Host extends ConsumerStatefulWidget {
  const _Host({super.key});
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => signOutAction(context, ref),
      child: const Text('Cerrar sesión'),
    ),
  );
}

class _FakeAuthRepository implements AuthRepository {
  int calls = 0;
  bool failure = false;
  Completer<void>? pending;
  @override
  Session? get session => null;
  @override
  Stream<AuthState> get changes => const Stream<AuthState>.empty();
  @override
  Future<void> signOut() async {
    calls++;
    await pending?.future;
    if (failure) throw Exception('synthetic');
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> sendPasswordRecovery(String email) async {}
  @override
  Future<void> updatePassword(String password) async {}
}
