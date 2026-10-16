import 'dart:math';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';

class AuthService {
  final SupabaseClient client;
  Future<Profile>? _profileLoadFuture;

  AuthService(this.client);

  Future<Profile?> signUp(String email, String password, String username) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final normalizedUsername = username.trim();

      if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
        throw const FormatException('Please enter a valid email address');
      }
      if (password.length < 6) {
        throw const FormatException('Password must be at least 6 characters');
      }
      if (normalizedUsername.length < 3 || normalizedUsername.length > 20) {
        throw const FormatException('Username must be between 3 and 20 characters');
      }

      print('📝 Signing up: $normalizedEmail');

      final res = await client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {'username': normalizedUsername},
      );
      final user = res.user;
      if (user == null) {
        throw const AuthException('Supabase kayıt yanıtında kullanıcı döndürmedi.');
      }

      // Supabase can return a user with no identities when this email is
      // already registered (depending on the project's email-confirmation
      // settings). Do not pretend that a new account was created.
      if (user.identities != null && user.identities!.isEmpty) {
        throw const AuthException(
          'Bu e-posta adresiyle zaten bir hesap var. Giriş yapmayı veya şifreni sıfırlamayı dene.',
        );
      }

      // When email confirmation is enabled, signUp succeeds but Supabase
      // intentionally returns no session. The old code tried to insert into
      // profiles anyway; RLS could reject it, and auth-state changes could
      // then send the user back to login without explaining why. Keep the user
      // on this screen and tell them to verify their email. Profile recovery
      // after the first confirmed login uses the username stored in metadata.
      if (res.session == null) {
        throw const AuthException(
          'Kayıt isteği alındı. E-posta doğrulaması açıksa gelen kutunu ve spam klasörünü kontrol edip hesabını doğrula; sonra giriş yap.',
        );
      }

      print('✅ Auth signup success: ${user.id}');
      final pairCode = _generatePairCode();

      print('📝 Creating profile in database...');

      await client.from('profiles').insert({
        'id': user.id,
        'email': normalizedEmail,
        'username': normalizedUsername,
        'pair_code': pairCode,
        'avatar_url': null,
        'paired_with': null,
        'status': 'online',
        'last_seen_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('✅ Profile created successfully');

      return Profile(
        id: user.id,
        username: normalizedUsername,
        pairCode: pairCode,
        avatarUrl: null,
        pairedWith: null,
        status: 'online',
        lastSeenAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      print('🔴 AuthService.signUp error: $e');
      rethrow;
    }
  }

  Future<Profile?> signIn(String email, String password) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      print('🔑 Signing in: $normalizedEmail');

      final res = await client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      if (res.user == null) {
        print('❌ Auth signin failed: no user returned');
        return null;
      }

      print('✅ Auth signin success: ${res.user!.id}');
      print('📝 Fetching profile from database...');

      final profile = await _loadOrCreateProfile(res.user!);
      print('✅ Profile fetched: ${profile.id}');
      await _setPresence(res.user!.id, 'online');
      return profile.copyWith(status: 'online', lastSeenAt: DateTime.now());
    } catch (e) {
      print('🔴 AuthService.signIn error: $e');
      rethrow;
    }
  }

  Future<Profile> updateProfile({
    required String userId,
    String? username,
    String? status,
    String? avatarUrl,
  }) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to update your profile');
    }

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (username != null) {
      final normalized = username.trim();
      if (normalized.isEmpty) {
        throw const FormatException('Username cannot be empty');
      }
      updates['username'] = normalized;
    }
    if (status != null) {
      const allowed = {'online', 'offline', 'away'};
      if (!allowed.contains(status)) {
        throw const FormatException('Invalid status');
      }
      updates['status'] = status;
    }
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    final data = await client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
    return Profile.fromMap(data);
  }

  Future<Profile> uploadAvatar(String userId, XFile file) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to upload an avatar');
    }

    final bytes = await file.readAsBytes();
    final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';

    await client.storage.from('avatars').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    final publicUrl = client.storage.from('avatars').getPublicUrl(path);
    return updateProfile(userId: userId, avatarUrl: publicUrl);
  }

  Future<void> setPresence(String userId, String status) => _setPresence(userId, status);

  Future<void> _setPresence(String userId, String status) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return;
    await client.from('profiles').update({
      'status': status,
      'last_seen_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<void> signOut() async {
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        await _setPresence(user.id, 'offline');
      }
      await client.auth.signOut();
      print('✅ Signed out');
    } catch (e) {
      print('🔴 SignOut error: $e');
      rethrow;
    }
  }

  Future<Profile?> getProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        print('ℹ️ No user logged in');
        return null;
      }

      print('📝 Fetching profile for user: ${user.id}');

      final profile = await _loadOrCreateProfile(user);
      print('✅ Profile fetched: ${profile.id}');
      await _setPresence(user.id, 'online');
      return profile.copyWith(status: 'online', lastSeenAt: DateTime.now());
    } catch (e) {
      print('⚠️ AuthService.getProfile error: $e');
      rethrow;
    }
  }

  Future<Profile> _loadOrCreateProfile(User user) {
    final existing = _profileLoadFuture;
    if (existing != null) return existing;

    late Future<Profile> future;
    future = _getOrCreateProfile(user).whenComplete(() {
      if (identical(_profileLoadFuture, future)) {
        _profileLoadFuture = null;
      }
    });
    _profileLoadFuture = future;
    return future;
  }

  Future<Profile> _getOrCreateProfile(User user) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (data != null) {
      return Profile.fromMap(data);
    }

    print('⚠️ Profile not found for ${user.id}; creating a recovery profile...');

    final email = user.email?.trim().toLowerCase() ?? '';
    final emailName = email.contains('@') ? email.split('@').first : '';
    final metadataUsername = user.userMetadata?['username']?.toString().trim() ?? '';
    final preferred = metadataUsername.length >= 3 && metadataUsername.length <= 20
        ? metadataUsername
        : emailName;
    final safeBase = preferred.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final base = safeBase.isNotEmpty ? safeBase : 'bestie_user';
    final suffix = '_${user.id.substring(0, 8)}';
    final maxBaseLength = 20 - suffix.length;
    final username = '${base.substring(0, base.length > maxBaseLength ? maxBaseLength : base.length)}$suffix';
    final pairCode = _generatePairCode();
    final now = DateTime.now();

    final created = await client.from('profiles').insert({
      'id': user.id,
      'email': email,
      'username': username,
      'pair_code': pairCode,
      'avatar_url': null,
      'paired_with': null,
      'status': 'online',
      'last_seen_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }).select().single();

    print('✅ Recovery profile created: $username');
    return Profile.fromMap(created);
  }

  String _generatePairCode() {
    final random = Random.secure();
    final code = List.generate(6, (_) => random.nextInt(10)).join();
    print('✅ Generated pair code: $code');
    return code;
  }
}