import 'package:flutter/material.dart';
import 'dart:async';

import 'package:image_picker/image_picker.dart';
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
  bool _authActionInProgress = false;

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
      // _init() handles the initial restored session. Ignore that event here
      // to prevent a second profile request during app startup.
      if (data.event == AuthChangeEvent.initialSession) return;

      // signIn/signUp already load the profile themselves. Avoid racing them
      // with a second request from the auth listener.
      if (_authActionInProgress) return;

      final session = data.session;
      if (session == null) {
        _removeProfileChannel();
        _profile = null;
        _lastError = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      try {
        final profile = await authService.getProfile();
        _profile = profile;
        if (profile != null) {
          _subscribeToOwnProfile(profile.id);
        }
        _lastError = null;
      } catch (e) {
        print('🔴 AuthProvider auth state error: $e');
        _lastError = e.toString();
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> _init() async {
    try {
      final hasSession = authService.client.auth.currentSession != null;
      if (!hasSession) {
        _profile = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Supabase may restore the auth session immediately while the profile
      // query is still settling. Keep the router on /splash during these
      // short retries so the login screen never flashes for a valid session.
      for (var attempt = 0; attempt < 4 && _profile == null; attempt++) {
        _profile = await authService.getProfile();
        if (_profile != null) break;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 90 * (attempt + 1)));
        }
      }

      if (_profile != null) {
        _subscribeToOwnProfile(_profile!.id);
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('🔴 AuthProvider._init error: $e');
      _lastError = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeToOwnProfile(String userId) {
    if (_profileChannel != null) return;

    final channel = authService.client.channel('bestie-profile-$userId');
    _profileChannel = channel;

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
    if (channel != null) {
      await authService.client.removeChannel(channel);
    }
  }

  Future<bool> signUp(String email, String password, String username) async {
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
    try {
      await _removeProfileChannel();
      await authService.signOut();
      _profile = null;
      notifyListeners();
    } catch (e) {
      print('🔴 AuthProvider.signOut error: $e');
      _lastError = e.toString();
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
