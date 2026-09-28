import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('keeps password recovery active until it finishes or signs out', () {
    final gate = AuthGate.forTesting();
    addTearDown(gate.dispose);

    gate.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    gate.handleAuthState(const AuthState(AuthChangeEvent.tokenRefreshed, null));

    expect(gate.recoveringPassword, isTrue);

    gate.finishPasswordRecovery();
    expect(gate.recoveringPassword, isFalse);

    gate.handleAuthState(
      const AuthState(AuthChangeEvent.passwordRecovery, null),
    );
    gate.handleAuthState(const AuthState(AuthChangeEvent.signedOut, null));

    expect(gate.recoveringPassword, isFalse);
  });
}
