import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local visual theme. It is intentionally NOT synchronized with the
/// partner. Partner mood is a separate realtime feature.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    unawaited(_init());
  }

  bool _isDark = false;
  int _colorIndex = 0;

  static const colors = [
    Color(0xFF7C4DFF),
    Color(0xFFFF7043),
    Color(0xFF00897B),
    Color(0xFFF9A825),
    Color(0xFFE91E63),
  ];

  bool get isDark => _isDark;
  Color get primaryColor => colors[_colorIndex.clamp(0, colors.length - 1).toInt()];
  int get colorIndex => _colorIndex;

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getBool('app_theme_dark') ?? false;
      _colorIndex = (prefs.getInt('app_theme_color') ?? 0)
          .clamp(0, colors.length - 1)
          .toInt();
    } catch (e) {
      debugPrint('[Theme] preferences load failed: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_theme_dark', _isDark);
      await prefs.setInt('app_theme_color', _colorIndex);
    } catch (e) {
      debugPrint('[Theme] preferences save failed: $e');
    }
  }

  Future<void> toggleDarkMode() async {
    _isDark = !_isDark;
    notifyListeners();
    await _persist();
  }

  Future<void> setColor(int index) async {
    if (index < 0 || index >= colors.length) return;
    _colorIndex = index;
    notifyListeners();
    await _persist();
  }
}
