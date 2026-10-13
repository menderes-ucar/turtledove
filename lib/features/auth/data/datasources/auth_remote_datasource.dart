import 'package:supabase_flutter/supabase_flutter.dart';
class AuthRemoteDataSource {
  final SupabaseClient client;
  const AuthRemoteDataSource(this.client);
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;
  User? get currentUser => client.auth.currentUser;
  Future<AuthResponse> signIn(String email, String password) => client.auth.signInWithPassword(email: email.trim(), password: password);
  Future<AuthResponse> signUp(String email, String password, {
    String? fullName
  }) => client.auth.signUp(email: email.trim(), password: password, data: {
    'full_name': fullName?.trim() ?? ''
  });
  Future<void> signOut() => client.auth.signOut();
  Future<void> resetPassword(String email) => client.auth.resetPasswordForEmail(email.trim());
}
