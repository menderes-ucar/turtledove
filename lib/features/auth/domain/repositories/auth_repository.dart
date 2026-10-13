import '../entities/app_user.dart';
abstract class AuthRepository {
  AppUser? get currentUser;
  Stream<AppUser?> authChanges();
  Future<AppUser> signIn(String email, String password);
  Future<AppUser?> signUp(String email, String password, {
    String? fullName
  });
  Future<void> signOut();
  Future<void> resetPassword(String email);
}
