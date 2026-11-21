import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'web/web_tools.dart';

/// «تذكرني» وقفل التطبيق بالبصمة — إعدادات محفوظة على هذا الجهاز فقط.
class AuthPrefs {
  static const _kRemember = 'remember_me';
  static const _kEmail = 'remember_email';
  static const _kLock = 'bio_lock';
  static const _kCred = 'bio_cred';
  static const _kLockUser = 'bio_user';

  static bool get remember => appPrefs?.getBool(_kRemember) ?? true;
  static String? get savedEmail => appPrefs?.getString(_kEmail);

  static Future<void> setRemember(bool on, String email) async {
    await appPrefs?.setBool(_kRemember, on);
    if (on) {
      await appPrefs?.setString(_kEmail, email);
    } else {
      await appPrefs?.remove(_kEmail);
    }
  }

  /// القفل مفعّل لهذا المستخدم على هذا الجهاز؟
  static bool lockEnabledFor(String? userId) =>
      userId != null && (appPrefs?.getBool(_kLock) ?? false) && appPrefs?.getString(_kLockUser) == userId && credentialId != null;

  static String? get credentialId => appPrefs?.getString(_kCred);

  static Future<void> enableLock(String userId, String credentialId) async {
    await appPrefs?.setString(_kCred, credentialId);
    await appPrefs?.setString(_kLockUser, userId);
    await appPrefs?.setBool(_kLock, true);
  }

  static Future<void> disableLock() async {
    await appPrefs?.setBool(_kLock, false);
    await appPrefs?.remove(_kCred);
    await appPrefs?.remove(_kLockUser);
  }
}

/// هل التطبيق مقفل الآن بانتظار البصمة؟
final appLocked = ValueNotifier<bool>(false);

/// يُستدعى عند تشغيل التطبيق: يطبّق «تذكرني» ثم يقفل التطبيق إن لزم.
Future<void> applyStartupSecurity() async {
  final auth = Supabase.instance.client.auth;
  final hadFlag = sessionFlag();
  if (auth.currentSession != null && !AuthPrefs.remember && !hadFlag) {
    // لم يختر «تذكرني» وهذه فتحة جديدة للتطبيق → تسجيل خروج من هذا الجهاز
    try {
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
  sessionFlag(set: true);
  lockIfNeeded();
}

void lockIfNeeded() {
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null && AuthPrefs.lockEnabledFor(user.id)) appLocked.value = true;
}

/// بعد تسجيل الدخول: اعرض تفعيل البصمة مرة واحدة
bool pendingBioOffer = false;
