import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان هوية Zypro (مأخوذة من الشعار) بنسختين: فاتح وداكن.
/// القيم تُقرأ عند البناء، ويُعاد بناء الشجرة كاملة عند تبديل المظهر.
class AppColors {
  static bool dark = false;

  static Color _p(int light, int darkV) => Color(dark ? darkV : light);

  // الكحلي: العناوين والعناصر النشطة (في الداكن: نص فاتح)
  static Color get primary => _p(0xFF34343F, 0xFFECECF1);
  // خلفيات التمييز الخفيفة
  static Color get primarySoft => _p(0xFFE3F8F0, 0xFF173A2F);
  // أخضر الشعار: نسبة الإنجاز وزر الإضافة (لا يُكتب عليه بالأبيض)
  static const accent = Color(0xFF18C894);
  // لون النص فوق الأخضر
  static const onAccent = Color(0xFF0E1F18);
  // الروابط والنصوص الخضراء
  static Color get accentText => _p(0xFF0B7A57, 0xFF5FD8AE);
  static Color get ink => _p(0xFF34343F, 0xFFECECF1);
  static Color get muted => _p(0xFF5B5E6B, 0xFFA3A6B3);
  static Color get subtle => _p(0xFF4A4D59, 0xFFC4C6D0);
  static Color get faint => _p(0xFF9AA2AE, 0xFF7D8190);
  static Color get line => _p(0xFFE4E6EA, 0xFF34343F);
  static Color get lineStrong => _p(0xFFC5CAD3, 0xFF4A4A58);
  static Color get divider => _p(0xFFEEF0F3, 0xFF2C2C36);
  static Color get background => _p(0xFFF5F6F7, 0xFF17171D);
  static Color get surface => _p(0xFFFFFFFF, 0xFF22222B);

  // عناصر مختارة (شرائح التصفية، الصور الرمزية): كحلي في الفاتح، فاتح في الداكن
  static Color get inkBlock => _p(0xFF34343F, 0xFFECECF1);
  static Color get onInkBlock => _p(0xFFFFFFFF, 0xFF17171D);
  // البطاقات البارزة (الاجتماع القادم، ملخص المالية): نصها أبيض دائمًا
  static Color get hero => _p(0xFF34343F, 0xFF2E2E3A);

  static Color get urgent => _p(0xFF9A3412, 0xFFF4A582);
  static Color get urgentSoft => _p(0xFFFDEEE6, 0xFF3A2620);
  static Color get urgentBorder => _p(0xFFF6D3C0, 0xFF5A3A30);
  static Color get danger => _p(0xFFC2410C, 0xFFF08A5D);
  static Color get waiting => _p(0xFF7A4F00, 0xFFF2CC6B);
  static Color get waitingSoft => _p(0xFFFFF4D6, 0xFF3A3220);
  static Color get warnBorder => _p(0xFFF2DFA6, 0xFF5A4A28);
  static Color get done => _p(0xFF0B7A57, 0xFF5FD8AE);
  static Color get doneSoft => _p(0xFFE3F8F0, 0xFF173A2F);
  static Color get neutralSoft => _p(0xFFEEF0F3, 0xFF2C2C36);
  static Color get barSoft => _p(0xFFC6F0E1, 0xFF245447);
}

/// أيقونات تتبع اتجاه اللغة.
class AppIcons {
  static bool ltr = false;
  static IconData get forward => ltr ? Icons.chevron_right : Icons.chevron_left;
}

ThemeData buildTheme() {
  final isDark = AppColors.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: isDark ? AppColors.accent : AppColors.primary,
      onPrimary: isDark ? AppColors.onAccent : Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.line,
      outlineVariant: AppColors.divider,
    ),
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.divider,
  );

  final text = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  return base.copyWith(
    textTheme: text,
    dividerTheme: DividerThemeData(color: AppColors.divider),
    listTileTheme: ListTileThemeData(iconColor: AppColors.muted, textColor: AppColors.ink),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.surface, modalBackgroundColor: AppColors.surface),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.surface),
    popupMenuTheme: PopupMenuThemeData(color: AppColors.surface),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? const Color(0xFFECECF1) : const Color(0xFF34343F),
      contentTextStyle: TextStyle(color: isDark ? const Color(0xFF17171D) : Colors.white),
    ),
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
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
        ),
      ),
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
      checkColor: WidgetStatePropertyAll(AppColors.onAccent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.accent),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
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
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: isDark ? AppColors.accent : AppColors.primary, width: 1.5),
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
        side: BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: BorderSide(color: AppColors.line)),
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(color: AppColors.ink),
      checkmarkColor: AppColors.onInkBlock,
    ),
  );
}

/// صور الهوية حسب المظهر.
class AppAssets {
  static String get wordmark => AppColors.dark
      ? 'assets/brand/zypro_wordmark_light.png'
      : 'assets/brand/zypro_wordmark.png';
}
