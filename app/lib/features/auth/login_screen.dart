import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/security.dart';
import '../../core/theme.dart';
import '../../core/web/web_tools.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';
import '../../widgets/forms.dart';
import '../../widgets/display_toggles.dart';

/// تسجيل الدخول وإنشاء الحساب.
/// أول حساب يُنشأ يصبح «المالك» تلقائيًا (من قاعدة البيانات).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _remember = AuthPrefs.remember;

  @override
  void initState() {
    super.initState();
    _email.text = AuthPrefs.savedEmail ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// يُرسل رابطًا لتعيين كلمة مرور جديدة، يفتح التطبيق مباشرة على شاشة كلمة المرور
  Future<void> _forgotPassword() async {
    final email = await promptText(
      context,
      tr('استعادة كلمة المرور'),
      initial: _email.text.trim(),
      label: tr('البريد الإلكتروني المسجّل'),
      confirmLabel: tr('إرسال الرابط'),
    );
    if (email == null || !mounted) return;
    if (!email.contains('@')) {
      showSnack(context, tr('أدخل بريدًا صحيحًا'));
      return;
    }
    setState(() => _busy = true);
    try {
      final here = Uri.base.toString().split('#').first.split('?').first;
      await Supabase.instance.client.auth.resetPasswordForEmail(email.trim(), redirectTo: here);
      if (mounted) showSnack(context, tr('إن كان البريد مسجّلًا فسيصلك رابط لتعيين كلمة مرور جديدة'));
    } catch (e) {
      if (mounted) showSnack(context, tr('حدث خطأ: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'name': _name.text.trim()},
        );
        if (res.session == null && mounted) {
          showSnack(context, tr('تم إنشاء الحساب. افتح بريدك لتأكيده ثم سجّل الدخول.'));
          setState(() => _signUp = false);
        }
      } else {
        await AuthPrefs.setRemember(_remember, _email.text.trim());
        sessionFlag(set: true);
        pendingBioOffer = true;
        lastLoginPassword = _password.text;
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
        // يحفظ المتصفح/الآيفون كلمة المرور في سلسلة المفاتيح لتُملأ لاحقًا بـ Face ID
        TextInput.finishAutofillContext();
      }
    } on AuthException catch (e) {
      pendingBioOffer = false;
      lastLoginPassword = null;
      if (mounted) showSnack(context, _authMessage(e));
    } catch (e) {
      if (mounted) showSnack(context, tr('حدث خطأ: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// الدخول بـ Face ID: فك كلمة المرور المحفوظة بعد التحقق ثم تسجيل الدخول
  Future<void> _bioLogin() async {
    final cred = AuthPrefs.credentialId, sealed = AuthPrefs.bioSecret, email = AuthPrefs.bioEmail;
    if (cred == null || sealed == null || email == null) return;
    setState(() => _busy = true);
    try {
      final res = await bioOpen(cred, sealed);
      if (!res.startsWith('ok:')) {
        if (mounted) {
          showSnack(context, res.contains('NotAllowed') ? tr('أُلغي التحقق') : tr('تعذّر التحقق — ادخل بكلمة المرور'));
        }
        return;
      }
      await AuthPrefs.setRemember(_remember, email);
      sessionFlag(set: true);
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: res.substring(3));
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid login')) {
        await AuthPrefs.clearBioLogin();
        if (mounted) {
          showSnack(context, tr('تغيّرت كلمة المرور — ادخل بها مرة واحدة ليُعاد تفعيل Face ID'));
          setState(() {});
        }
      } else if (mounted) {
        showSnack(context, _authMessage(e));
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('حدث خطأ: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return tr('البريد أو كلمة المرور غير صحيحة');
    if (m.contains('already registered')) return tr('هذا البريد مسجّل مسبقًا');
    if (m.contains('email not confirmed')) return tr('أكّد بريدك الإلكتروني أولًا');
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: AlignmentDirectional.centerEnd, child: DisplayToggles()),
                  const SizedBox(height: 8),
                  Center(child: Image.asset(AppAssets.wordmark, width: 170, semanticLabel: 'Zypro')),
                  const SizedBox(height: 16),
                  Text(
                    _signUp ? tr('إنشاء حساب') : tr('أهلًا بعودتك'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _signUp ? tr('أنشئ حسابك للبدء') : tr('سجّل الدخول لمتابعة يومك'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 32),
                  if (!_signUp && AuthPrefs.hasBioLogin) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: _busy ? null : _bioLogin,
                      icon: const Icon(Icons.face_retouching_natural),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('الدخول بـ Face ID'), style: const TextStyle(fontSize: 16)),
                          Text(AuthPrefs.bioEmail ?? '', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(tr('أو بكلمة المرور'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_signUp) ...[
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(labelText: tr('الاسم')),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty) ? tr('أدخل الاسم') : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: InputDecoration(labelText: tr('البريد الإلكتروني')),
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    validator: (v) => (v == null || !v.contains('@')) ? tr('أدخل بريدًا صحيحًا') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: InputDecoration(labelText: tr('كلمة المرور')),
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    autofillHints: _signUp ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v == null || v.length < 8) ? tr('٨ أحرف على الأقل') : null,
                  ),
                  if (!_signUp)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _remember = !_remember),
                            child: Row(
                              children: [
                                Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true)),
                                Flexible(child: Text(tr('تذكرني'), style: const TextStyle(fontSize: 14))),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _forgotPassword,
                          child: Text(tr('نسيت كلمة المرور؟')),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_signUp ? tr('إنشاء الحساب') : tr('تسجيل الدخول')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? tr('لديك حساب؟ سجّل الدخول') : tr('ليس لديك حساب؟ أنشئ حسابًا')),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
