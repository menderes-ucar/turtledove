import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
class AuthProvider extends ChangeNotifier {
  final AuthRepository repository;
  StreamSubscription<AppUser?>? _sub;
  AppUser? user;
  bool loading=false;
  String? error;
  AuthProvider(this.repository) {
    user=repository.currentUser;
    _sub=repository.authChanges().listen((u) {
      user=u;
      notifyListeners();
    });
  }
  bool get isAuthenticated=>user!=null;
  Future<void> signIn(String e,String p) async {
    await _run(() async {
      user=await repository.signIn(e,p);
    });
  }
  Future<void> signUp(String e,String p, {
    String? name
  }) async {
    await _run(() async {
      user=await repository.signUp(e,p,fullName:name);
    });
  }
  Future<void> signOut() async {
    await repository.signOut();
    user=null;
    notifyListeners();
  }
  Future<void> resetPassword(String e) async {
    await repository.resetPassword(e);
  }
  Future<void> _run(Future<void> Function() action) async {
    loading=true;
    error=null;
    notifyListeners();
    try {
      await action();
    } catch(e) {
      error=_message(e);
      rethrow;
    } finally {
      loading=false;
      notifyListeners();
    }
  }
  String _message(Object e) {
    final m=e.toString();
    if(m.contains('Invalid login credentials'))return 'E-posta veya şifre hatalı.';
    if(m.contains('already registered'))return 'Bu e-posta zaten kayıtlı.';
    return 'İşlem gerçekleştirilemedi.';
  }
  @override void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
