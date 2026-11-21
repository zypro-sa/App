import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../core/web/web_tools.dart';

/// شاشة القفل: فتح التطبيق بـ Face ID أو البصمة.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    final id = AuthPrefs.credentialId;
    if (id == null) {
      appLocked.value = false;
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await bioVerify(id);
    if (!mounted) return;
    if (res == 'ok') {
      appLocked.value = false;
    } else {
      setState(() => _error = res.contains('NotAllowed') ? tr('لم يتم التحقق — حاول مرة أخرى') : tr('تعذّر التحقق على هذا الجهاز'));
    }
    setState(() => _busy = false);
  }

  Future<void> _usePassword() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    appLocked.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset(AppAssets.wordmark, width: 150, semanticLabel: 'Zypro')),
                  const SizedBox(height: 36),
                  Icon(Icons.face_retouching_natural, size: 64, color: AppColors.accentText),
                  const SizedBox(height: 14),
                  Text(tr('التطبيق مقفل'), textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  if (email != null) ...[
                    const SizedBox(height: 4),
                    Text(email, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: TextStyle(color: AppColors.muted)),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: _busy ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(tr('فتح بـ Face ID أو البصمة'), style: const TextStyle(fontSize: 16)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.urgent)),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : _usePassword,
                    child: Text(tr('الدخول بكلمة المرور بدلًا من ذلك')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _err(String res) => res.contains('NotAllowed') ? tr('أُلغي التحقق') : tr('تعذّر التفعيل: {0}', [res.replaceFirst('error:', '')]);

void _snack(BuildContext context, String m) {
  final s = ScaffoldMessenger.maybeOf(context);
  s?.showSnackBar(SnackBar(content: Text(m)));
}

/// يضمن وجود بصمة مسجّلة لهذا المستخدم على الجهاز
Future<String?> _ensureCredential(BuildContext context, {bool fresh = false}) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  if (!await bioAvailable()) {
    if (context.mounted) _snack(context, tr('هذا الجهاز أو المتصفح لا يدعم Face ID أو البصمة'));
    return null;
  }
  final existing = AuthPrefs.credentialFor(user.id);
  if (!fresh && existing != null) return existing;
  final res = await bioRegister(user.id, user.email ?? 'Zypro');
  if (!context.mounted) return null;
  if (res.startsWith('error:')) {
    _snack(context, _err(res));
    return null;
  }
  await AuthPrefs.setCredential(user.id, res);
  return res;
}

/// تفعيل القفل بالبصمة لهذا الجهاز. يعيد true عند النجاح.
Future<bool> enableBioLock(BuildContext context, {bool quiet = false}) async {
  final user = Supabase.instance.client.auth.currentUser;
  final cred = await _ensureCredential(context);
  if (cred == null || user == null) return false;
  await AuthPrefs.enableLock(user.id, cred);
  if (!quiet && context.mounted) _snack(context, tr('تم التفعيل — سيُطلب Face ID أو البصمة عند فتح التطبيق'));
  return true;
}

/// حفظ كلمة المرور مشفّرة للدخول بـ Face ID
Future<bool> enableBioLogin(BuildContext context, String password) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user?.email == null) return false;
  var cred = await _ensureCredential(context);
  if (cred == null || !context.mounted) return false;
  var sealed = await bioSeal(cred, password);
  if (sealed == 'error:NoPrf' && context.mounted) {
    // بصمة قديمة بلا مفتاح تشفير → نسجّل واحدة جديدة
    cred = await _ensureCredential(context, fresh: true);
    if (cred == null || !context.mounted) return false;
    sealed = await bioSeal(cred, password);
  }
  if (!context.mounted) return false;
  if (sealed == 'error:NoPrf') {
    _snack(context, tr('هذا الجهاز لا يدعم حفظ كلمة المرور بـ Face ID — حدّث نظام الآيفون إلى iOS 18 أو أحدث'));
    return false;
  }
  if (sealed.startsWith('error:')) {
    _snack(context, _err(sealed));
    return false;
  }
  await AuthPrefs.saveBioLogin(user!.email!, sealed);
  if (context.mounted) _snack(context, tr('تم — يمكنك الآن الدخول بـ Face ID دون كلمة المرور'));
  return true;
}

/// عرض التفعيل بعد أول تسجيل دخول (مرة واحدة)
Future<void> maybeOfferBio(BuildContext context) async {
  if (!pendingBioOffer) return;
  pendingBioOffer = false;
  final password = lastLoginPassword;
  lastLoginPassword = null;
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null || !await bioAvailable() || !context.mounted) return;
  final needLogin = password != null && !AuthPrefs.hasBioLogin;
  final needLock = !AuthPrefs.lockEnabledFor(user.id);
  if (!needLogin && !needLock) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.face_retouching_natural, color: AppColors.accentText, size: 40),
      title: Text(tr('تفعيل Face ID / البصمة؟')),
      content: Text(
        tr('ادخل وافتح التطبيق بوجهك أو بصمتك بدل كتابة كلمة المرور. تُحفظ كلمة المرور مشفّرة على هذا الجهاز فقط ولا تُفك إلا بعد التحقق.'),
        style: const TextStyle(height: 1.6),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ليس الآن'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تفعيل'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (needLogin && password != null) {
    final done = await enableBioLogin(context, password);
    if (done && needLock && context.mounted) await enableBioLock(context, quiet: true);
  } else {
    await enableBioLock(context);
  }
}
