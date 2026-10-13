import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local visual theme. It is intentionally NOT synchronized with the
/// partner. Partner mood is a separate realtime feature.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    unawaited(_init());
  }

  SharedPreferences? _prefs;
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
    _prefs = await SharedPreferences.getInstance();
    _isDark = _prefs?.getBool('isDark') ?? false;
    _colorIndex = (_prefs?.getInt('colorIndex') ?? 0).clamp(0, colors.length - 1).toInt();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool('isDark', _isDark);
    await prefs.setInt('colorIndex', _colorIndex);
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
