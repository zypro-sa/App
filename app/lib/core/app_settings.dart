import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تفضيلات العرض المحفوظة على الجهاز: المظهر واللغة.
class AppSettings {
  const AppSettings({required this.themeMode, required this.locale, required this.localeChosen});

  final ThemeMode themeMode;
  final String locale; // ar | en
  final bool localeChosen; // اختارها العضو على هذا الجهاز؟

  AppSettings copyWith({ThemeMode? themeMode, String? locale, bool? localeChosen}) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        localeChosen: localeChosen ?? this.localeChosen,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences? _prefs;

  static const _kTheme = 'theme_mode';
  static const _kLocale = 'locale';

  static AppSettings _load(SharedPreferences? p) {
    final theme = switch (p?.getString(_kTheme)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final saved = p?.getString(_kLocale);
    return AppSettings(themeMode: theme, locale: saved == 'en' ? 'en' : 'ar', localeChosen: saved != null);
  }

  void setTheme(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setString(_kTheme, mode.name);
  }

  /// تبديل سريع: من الفاتح إلى الداكن والعكس (حسب ما يظهر الآن).
  void toggleTheme(Brightness current) =>
      setTheme(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  /// تغيير اللغة على الجهاز وحفظها في ملف العضو لتصله الإشعارات بها.
  Future<void> setLocale(String code) async {
    state = state.copyWith(locale: code, localeChosen: true);
    await _prefs?.setString(_kLocale, code);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        await Supabase.instance.client.from('profiles').update({'locale': code}).eq('id', uid);
      } catch (_) {
        // يبقى التغيير على الجهاز حتى لو تعذّر الحفظ
      }
    }
  }

  /// أول دخول على جهاز جديد: نأخذ لغة العضو من ملفه.
  void adoptProfileLocale(String? code) {
    if (state.localeChosen || code == null || code == state.locale) return;
    if (code != 'ar' && code != 'en') return;
    state = state.copyWith(locale: code);
  }
}

/// تُهيّأ في main بعد قراءة التفضيلات.
SharedPreferences? appPrefs;

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(appPrefs),
);
