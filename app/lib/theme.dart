import 'package:flutter/material.dart';

class Pk {
  static const green = Color(0xFF1FBF75);
  static const bg = Color(0xFF0B0F0D);
  static const surface = Color(0xFF151B18);
  static const surface2 = Color(0xFF1D2521);
  static const muted = Color(0xFF8A968F);
  static const danger = Color(0xFFE5534B);
  static const amber = Color(0xFFF5B73B);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark).copyWith(
      primary: green,
      onPrimary: Colors.black,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0, centerTitle: false),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Text field look (kept per-field so we don't depend on theme classes that change between Flutter versions).
InputDecoration deco(String label, {String? hint, IconData? icon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: Pk.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

String rs(int n) => 'Rs $n';
