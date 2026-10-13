import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const supportedCodes = ['tr', 'en', 'de', 'es', 'fr'];

  final SupabaseClient client;
  Locale _locale = const Locale('tr');
  bool _loaded = false;
  StreamSubscription<AuthState>? _authSubscription;

  LocaleProvider(this.client) {
    _load();
    _authSubscription = client.auth.onAuthStateChange.listen((_) {
      unawaited(_load());
    });
  }

  Locale get locale => _locale;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('app_locale')?.toLowerCase();
      final user = client.auth.currentUser;

      // Load the device-local choice first. It must work before sign-in too.
      if (savedCode != null && supportedCodes.contains(savedCode)) {
        _locale = Locale(savedCode);
      }

      // A signed-in user's profile is authoritative, and refreshes the local
      // preference so native call UI and Flutter use the same language.
      if (user != null) {
        final row = await client
            .from('profiles')
            .select('language_code')
            .eq('id', user.id)
            .maybeSingle();
        final profileCode = row?['language_code']?.toString().toLowerCase();
        if (profileCode != null && supportedCodes.contains(profileCode)) {
          _locale = Locale(profileCode);
          await prefs.setString('app_locale', profileCode);
        } else {
          await prefs.setString('app_locale', _locale.languageCode);
        }
      } else if (savedCode == null || !supportedCodes.contains(savedCode)) {
        _locale = const Locale('tr');
        await prefs.setString('app_locale', 'tr');
      }
    } catch (e) {
      debugPrint('[Locale] language load failed: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setLocale(String languageCode) async {
    final code = languageCode.trim().toLowerCase();

    if (!supportedCodes.contains(code)) return;

    if (_locale.languageCode != code) {
      _locale = Locale(code);
      notifyListeners();
    }

    // Native Android call UI reads the same locale key while Flutter may be
    // paused/backgrounded.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_locale', code);
    } catch (e) {
      debugPrint('[Locale] native locale cache failed: $e');
    }

    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      await client
          .from('profiles')
          .update({
        'language_code': code,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
          .eq('id', user.id);
    } catch (e) {
      debugPrint('[Locale] profile language save failed: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
