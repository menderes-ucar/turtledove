import 'package:flutter/material.dart';

class AppTheme {
  static const themeColors = [
    Color(0xFF7C4DFF),
    Color(0xFFFF7043),
    Color(0xFF00897B),
    Color(0xFFF9A825),
    Color(0xFFE91E63),
  ];

  static ThemeData lightTheme(Color primaryColor) {
    final scheme = ColorScheme.fromSeed(seedColor: primaryColor, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F7FA),
      appBarTheme: AppBarTheme(elevation: 0, centerTitle: false, backgroundColor: primaryColor, foregroundColor: Colors.white, surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: primaryColor.withOpacity(.22),
        margin: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(22)), side: BorderSide(color: primaryColor.withOpacity(.14), width: 1)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: primaryColor, width: 1.4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        height: 72, backgroundColor: primaryColor,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: Colors.white70)),
        indicatorColor: Colors.white24,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData darkTheme(Color primaryColor) {
    final scheme = ColorScheme.fromSeed(seedColor: primaryColor, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F1014),
      appBarTheme: AppBarTheme(elevation: 0, centerTitle: false, backgroundColor: primaryColor, foregroundColor: Colors.white, surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: primaryColor.withOpacity(.28),
        margin: EdgeInsets.zero,
        color: const Color(0xFF181A20),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: primaryColor.withOpacity(.18), width: 1)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF181A20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: primaryColor, width: 1.4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        height: 72, backgroundColor: primaryColor,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: Colors.white70)),
        indicatorColor: Colors.white24,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
