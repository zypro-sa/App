import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router.dart' show passwordRecovery;
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';
import '../../widgets/display_toggles.dart';

/// تعيين كلمة المرور لعضو دُعي للفريق، أو بعد طلب استعادتها.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1.text.length < 8) {
      showSnack(context, tr('كلمة المرور ٨ أحرف على الأقل'));
      return;
    }
    if (_p1.text != _p2.text) {
      showSnack(context, tr('كلمتا المرور غير متطابقتين'));
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _p1.text, data: {'needs_password': false}),
      );
      passwordRecovery.value = false;
    } on AuthException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = Supabase.instance.client.auth.currentUser?.userMetadata?['name'] as String?;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: AlignmentDirectional.centerEnd, child: DisplayToggles()),
                  const SizedBox(height: 8),
                  Center(child: Image.asset(AppAssets.wordmark, width: 170, semanticLabel: 'Zypro')),
                const SizedBox(height: 16),
                Text(
                  name == null ? tr('مرحبًا بك') : tr('مرحبًا {0}', [name]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(tr('اختر كلمة مرور لحسابك'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 28),
                TextField(
                  controller: _p1,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(labelText: tr('كلمة المرور الجديدة')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _p2,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(labelText: tr('تأكيد كلمة المرور')),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr('حفظ والدخول')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
