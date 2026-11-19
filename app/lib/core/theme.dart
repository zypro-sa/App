import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان التصميم المعتمد.
/// ألوان هوية Zypro (مأخوذة من الشعار).
class AppColors {
  // الكحلي: الأزرار الرئيسية والعناوين والعناصر النشطة
  static const primary = Color(0xFF34343F);
  // الأخضر الفاتح: خلفيات التمييز الخفيفة
  static const primarySoft = Color(0xFFE3F8F0);
  // أخضر الشعار: نسبة الإنجاز وزر الإضافة والتمييز (لا يُكتب عليه بالأبيض)
  static const accent = Color(0xFF18C894);
  // أخضر غامق: الروابط والنصوص الخضراء
  static const accentText = Color(0xFF0B7A57);
  static const ink = Color(0xFF34343F);
  static const muted = Color(0xFF5B5E6B);
  static const subtle = Color(0xFF4A4D59);
  static const line = Color(0xFFE4E6EA);
  static const divider = Color(0xFFEEF0F3);
  static const background = Color(0xFFF5F6F7);
  static const surface = Colors.white;

  static const urgent = Color(0xFF9A3412);
  static const urgentSoft = Color(0xFFFDEEE6);
  static const urgentBorder = Color(0xFFF6D3C0);
  static const waiting = Color(0xFF7A4F00);
  static const waitingSoft = Color(0xFFFFF4D6);
  static const done = Color(0xFF0B7A57);
  static const doneSoft = Color(0xFFE3F8F0);
  static const neutralSoft = Color(0xFFEEF0F3);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );

  final text = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: GoogleFonts.ibmPlexSansArabic().fontFamily,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.muted,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accentText),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : null,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ink),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
      backgroundColor: AppColors.surface,
    ),
  );
}
