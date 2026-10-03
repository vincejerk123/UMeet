import 'package:flutter/material.dart';

class AppColors {
  static const red = Color(0xFFC62828);
  static const lightRed = Color(0xFFFFCDD2);
  static const gold = Color(0xFFF9A825);
  static const bg = Color(0xFFF7F7F7);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF1A1A1A);
  static const textMuted = Color(0xFF757575);
  static const chipBg = Color(0xFFF0F0F0);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.bg,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.red),
  fontFamily: 'Poppins', // was 'Poppins'
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.bg,
    elevation: 0,
    foregroundColor: AppColors.textPrimary,
    centerTitle: false,
  ),
);
