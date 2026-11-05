import 'package:flutter/material.dart';

const Color kBrand = Color(0xFF4B55E0);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: b);
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamilyFallback: const ['Malgun Gothic', 'Noto Sans KR', 'Roboto'],
    scaffoldBackgroundColor: dark ? const Color(0xFF111318) : const Color(0xFFF5F6FA),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF111318) : const Color(0xFFF5F6FA),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1F27) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(0, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(0, 44),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? Colors.white10 : Colors.black12,
      space: 1,
      thickness: 0.6,
    ),
  );
}

ThemeData lightTheme() => _build(Brightness.light);
ThemeData darkTheme() => _build(Brightness.dark);
