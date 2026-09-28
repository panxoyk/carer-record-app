import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final authGateProvider = ChangeNotifierProvider<AuthGate>((ref) {
  return AuthGate(ref.watch(authRepositoryProvider));
});

final sessionProvider = Provider<Session?>(
  (ref) => ref.watch(authGateProvider).session,
);

class AuthGate extends ChangeNotifier {
  AuthGate(AuthRepository repository) : session = repository.session {
    _subscription = repository.changes.listen(
      handleAuthState,
      onError: (_, __) {},
    );
  }

  @visibleForTesting
  AuthGate.forTesting() : session = null {
    _subscription = const Stream<AuthState>.empty().listen((_) {});
  }

  late final StreamSubscription<AuthState> _subscription;
  Session? session;
  bool recoveringPassword = false;

  @visibleForTesting
  void handleAuthState(AuthState event) {
    session = event.session;
    if (event.event == AuthChangeEvent.passwordRecovery) {
      recoveringPassword = true;
    } else if (event.event == AuthChangeEvent.signedOut) {
      recoveringPassword = false;
    }
    notifyListeners();
  }

  void finishPasswordRecovery() {
    recoveringPassword = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
