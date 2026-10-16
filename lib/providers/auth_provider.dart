import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:async';


import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService authService;
  Profile? _profile;
  bool _isLoading = true;
  String? _lastError;
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _profileChannel;
  String? _profileChannelUserId;
  bool _authActionInProgress = false;
  int _authGeneration = 0;

  AuthProvider(this.authService) {
    _init();
    _listenToAuthChanges();
  }

  Profile? get profile => _profile;
  bool get hasSession => authService.client.auth.currentSession != null;
  bool get isLoading => _isLoading;
  bool get isPaired => _profile?.pairedWith != null;
  String? get lastError => _lastError;

  void _listenToAuthChanges() {
    _authSubscription = authService.client.auth.onAuthStateChange.listen((data) async {
      // _init() handles the initial restored session.
      if (data.event == AuthChangeEvent.initialSession) return;

      // Explicit sign-in/sign-up/sign-out methods own their state transition.
      if (_authActionInProgress) return;

      final generation = ++_authGeneration;
      final session = data.session;
      if (session == null) {
        await _removeProfileChannel();
        if (generation != _authGeneration) return;
        _profile = null;
        _lastError = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isLoading = true;
      _lastError = null;
      notifyListeners();
      await _removeProfileChannel();
      try {
        final profile = await authService.getProfile().timeout(
          const Duration(seconds: 20),
        );
        if (generation != _authGeneration ||
            authService.client.auth.currentUser?.id != session.user.id) return;
        _profile = profile;
        if (profile != null) _subscribeToOwnProfile(profile.id);
      } catch (e) {
        if (generation != _authGeneration) return;
        debugPrint('🔴 AuthProvider auth state error: $e');
        _lastError = e.toString();
        _profile = null;
      } finally {
        if (generation == _authGeneration) {
          _isLoading = false;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _init() async {
    final generation = _authGeneration;
    final initialUserId = authService.client.auth.currentUser?.id;
    try {
      if (initialUserId == null) {
        if (authService.client.auth.currentUser == null && generation == _authGeneration) {
          _profile = null;
          _isLoading = false;
          notifyListeners();
        }
        return;
      }

      final profile = await authService.getProfile().timeout(
        const Duration(seconds: 20),
      );
      // Ignore an old startup request if the user changed while it was loading.
      if (generation != _authGeneration ||
          authService.client.auth.currentUser?.id != initialUserId) return;
      _profile = profile;
      if (profile != null) _subscribeToOwnProfile(profile.id);
      _lastError = null;
    } catch (e) {
      if (generation != _authGeneration) return;
      debugPrint('🔴 AuthProvider._init error: $e');
      _lastError = e.toString();
      _profile = null;
    } finally {
      if (generation == _authGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _subscribeToOwnProfile(String userId) {
    if (_profileChannel != null && _profileChannelUserId == userId) return;
    if (_profileChannel != null) {
      final oldChannel = _profileChannel;
      _profileChannel = null;
      _profileChannelUserId = null;
      unawaited(authService.client.removeChannel(oldChannel!));
    }

    final channel = authService.client.channel('bestie-profile-$userId');
    _profileChannel = channel;
    _profileChannelUserId = userId;

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final record = payload.newRecord;
            if (record['id'] != userId) return;

            try {
              _profile = Profile.fromMap(Map<String, dynamic>.from(record));
              _lastError = null;
              notifyListeners();
            } catch (e) {
              debugPrint('🔴 AuthProvider profile realtime parse error: $e');
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('🟢 BESTIE PROFILE Realtime SUBSCRIBED');
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('🔴 BESTIE PROFILE Realtime status=$status error=$error');
          }
        });
  }

  Future<void> _removeProfileChannel() async {
    final channel = _profileChannel;
    _profileChannel = null;
    _profileChannelUserId = null;
    if (channel != null) {
      await authService.client.removeChannel(channel);
    }
  }

  Future<bool> signUp(String email, String password, String username) async {
    ++_authGeneration;
    _authActionInProgress = true;
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      _profile = await authService.signUp(email, password, username);
      if (_profile != null) {
        _subscribeToOwnProfile(_profile!.id);
      }
      _isLoading = false;
      _authActionInProgress = false;
      notifyListeners();
      return _profile != null;
    } catch (e) {
      print('🔴 AuthProvider.signUp error: $e');
      _lastError = e.toString();
      _isLoading = false;
      _authActionInProgress = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    ++_authGeneration;
    _authActionInProgress = true;
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      _profile = await authService.signIn(email, password);
      if (_profile != null) {
        _subscribeToOwnProfile(_profile!.id);
      }
      _isLoading = false;
      _authActionInProgress = false;
      notifyListeners();
      return _profile != null;
    } catch (e) {
      print('🔴 AuthProvider.signIn error: $e');
      _lastError = e.toString();
      _isLoading = false;
      _authActionInProgress = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    ++_authGeneration;
    _authActionInProgress = true;
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      await _removeProfileChannel();
      await authService.signOut();
      _profile = null;
    } catch (e) {
      debugPrint('🔴 AuthProvider.signOut error: $e');
      _lastError = e.toString();
    } finally {
      _authActionInProgress = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfileDetails({String? username, String? status, String? avatarUrl}) async {
    final current = _profile;
    if (current == null) return false;
    _lastError = null;
    try {
      final updated = await authService.updateProfile(
        userId: current.id,
        username: username,
        status: status,
        avatarUrl: avatarUrl,
      );
      _profile = updated;
      notifyListeners();
      return true;
    } catch (e) {
      print('🔴 AuthProvider.updateProfileDetails error: $e');
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadAvatar(XFile file) async {
    final current = _profile;
    if (current == null) return false;
    _lastError = null;
    try {
      final updated = await authService.uploadAvatar(current.id, file);
      _profile = updated;
      notifyListeners();
      return true;
    } catch (e) {
      print('🔴 AuthProvider.uploadAvatar error: $e');
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> setPresence(String status) async {
    final current = _profile;
    if (current == null) return false;
    try {
      await authService.setPresence(current.id, status);
      _profile = current.copyWith(status: status, lastSeenAt: DateTime.now());
      notifyListeners();
      return true;
    } catch (e) {
      print('🔴 AuthProvider.setPresence error: $e');
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  void updateProfile(Profile profile) {
    _profile = profile;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    final channel = _profileChannel;
    _profileChannel = null;
    if (channel != null) {
      authService.client.removeChannel(channel);
    }
    super.dispose();
  }
}
