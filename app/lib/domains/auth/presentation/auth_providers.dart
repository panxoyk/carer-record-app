import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../../practitioner/data/models/practitioner_model.dart';
import '../../practitioner/domain/entities/practitioner.dart';
import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((_) => supabaseClient);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final authGateProvider = ChangeNotifierProvider<AuthGate>((ref) {
  final gate = AuthGate(ref.watch(authRepositoryProvider));
  ref.onDispose(gate.dispose);
  return gate;
});

final sessionProvider = Provider<Session?>(
  (ref) => ref.watch(authGateProvider).session,
);

final currentPractitionerProvider = FutureProvider<Practitioner?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final client = ref.watch(supabaseClientProvider);
  final row =
      await client
          .from('practitioners')
          .select()
          .eq('id', session.user.id)
          .maybeSingle();
  return row == null ? null : PractitionerModel.fromJson(row);
});

final currentRoleProvider = Provider<AsyncValue<String?>>(
  (ref) => ref.watch(currentPractitionerProvider).whenData((p) => p?.role),
);

class AuthGate extends ChangeNotifier {
  AuthGate(AuthRepository repository) : session = repository.session {
    _subscription = repository.changes.listen((event) {
      session = event.session;
      recoveringPassword = event.event == AuthChangeEvent.passwordRecovery;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;
  Session? session;
  bool recoveringPassword = false;

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
