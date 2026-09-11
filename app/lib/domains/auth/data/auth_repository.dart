import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordRecovery(String email) =>
      _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'io.carerrecord.app://login-callback/recover',
      );

  Future<void> updatePassword(String password) =>
      _client.auth.updateUser(UserAttributes(password: password));
}
