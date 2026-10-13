import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/app_user_model.dart';
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remote;
  const AuthRepositoryImpl(this.remote);
  AppUser? _map(User? u) => u == null ? null : AppUserModel.fromUser(u);
  @override AppUser? get currentUser => _map(remote.currentUser);
  @override Stream<AppUser?> authChanges() => remote.authStateChanges.map((s) => _map(s.session?.user));
  @override Future<AppUser> signIn(String email, String password) async {
    final r=await remote.signIn(email,password);
    final u=r.user;
    if(u==null) throw StateError('Oturum oluşturulamadı.');
    return AppUserModel.fromUser(u);
  }
  @override Future<AppUser?> signUp(String email,String password, {
    String? fullName
  }) async {
    final r=await remote.signUp(email,password,fullName:fullName);
    return _map(r.user);
  }
  @override Future<void> signOut()=>remote.signOut();
  @override Future<void> resetPassword(String email)=>remote.resetPassword(email);
}
