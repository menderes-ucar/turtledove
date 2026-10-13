import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const supportedCodes = ['tr', 'en', 'de', 'es', 'fr'];

  Locale _locale = const Locale('tr');
  bool _loaded = false;

  Locale get locale => _locale;
  bool get isLoaded => _loaded;

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_locale');
    if (saved != null && supportedCodes.contains(saved)) {
      _locale = Locale(saved);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedCodes.contains(languageCode) || _locale.languageCode == languageCode) return;
    _locale = Locale(languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', languageCode);
  }
}
