import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// حسابي: الصورة والاسم والجوال والبريد وكلمة المرور.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _uploading = false;

  void _refresh() {
    ref.invalidate(profileProvider);
    ref.invalidate(teamMembersProvider);
    ref.invalidate(teamProvider);
  }

  Future<void> _pickPhoto() async {
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّر فتح الصور: {0}', [e]));
      return;
    }
    if (x == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await x.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) throw Exception(tr('الصورة أكبر من ٣ ميجابايت'));
      await ref.read(sectionRepoProvider).uploadMyAvatar(bytes, x.mimeType ?? 'image/jpeg');
      _refresh();
      if (mounted) showSnack(context, tr('تم تحديث الصورة'));
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّر رفع الصورة: {0}', ['$e'.replaceFirst('Exception: ', '')]));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final repo = ref.read(sectionRepoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('حسابي')), centerTitle: true),
      body: AsyncBody<Profile?>(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        builder: (p) {
          if (p == null) return EmptyState(tr('تعذّر تحميل الحساب'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              Center(
                child: Stack(
                  children: [
                    Avatar(p.initial, size: 96, radius: 30, fg: AppColors.accent, bg: AppColors.hero, imageUrl: p.avatarUrl),
                    if (_uploading)
                      const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _uploading ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(p.avatarUrl == null ? tr('إضافة صورة') : tr('تغيير الصورة')),
                  ),
                  if (p.avatarUrl != null)
                    TextButton(
                      onPressed: _uploading
                          ? null
                          : () async {
                              if (await runAction(context, repo.removeMyAvatar, success: tr('أُزيلت الصورة'))) _refresh();
                            },
                      child: Text(tr('إزالة'), style: TextStyle(color: AppColors.urgent)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              FormCard(children: [
                FormRow(
                  label: tr('الاسم'),
                  value: p.name,
                  onTap: () async {
                    final v = await promptText(context, tr('الاسم'), initial: p.name);
                    if (v == null || v.trim().isEmpty || !context.mounted) return;
                    if (await runAction(context, () => repo.updateMyProfile(name: v), success: tr('حُفظ التعديل'))) _refresh();
                  },
                ),
                FormRow(
                  label: tr('الجوال'),
                  value: p.phone ?? tr('أضف رقمك'),
                  muted: p.phone == null,
                  onTap: () async {
                    final v = await promptText(context, tr('الجوال'), initial: p.phone ?? '');
                    if (v == null || !context.mounted) return;
                    if (await runAction(context, () => repo.updateMyProfile(phone: v), success: tr('حُفظ التعديل'))) _refresh();
                  },
                ),
                FormRow(
                  label: tr('البريد الإلكتروني'),
                  value: p.email ?? '—',
                  onTap: () => showFormSheet(context, _ChangeEmailSheet(current: p.email ?? '')),
                ),
                FormRow(label: tr('المسمى الوظيفي'), value: p.jobTitle ?? '—', muted: p.jobTitle == null),
                FormRow(label: tr('الدور'), value: p.role.label),
              ]),
              const SizedBox(height: 6),
              Text(tr('المسمى الوظيفي والدور يحددهما المالك'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => showFormSheet(context, const _ChangePasswordSheet()),
                icon: const Icon(Icons.password),
                label: Text(tr('تغيير كلمة المرور')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChangeEmailSheet extends ConsumerStatefulWidget {
  const _ChangeEmailSheet({required this.current});
  final String current;

  @override
  ConsumerState<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends ConsumerState<_ChangeEmailSheet> {
  late final _email = TextEditingController(text: widget.current);
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
      showSnack(context, tr('أدخل بريدًا صحيحًا'));
      return;
    }
    if (v.toLowerCase() == widget.current.toLowerCase()) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(sectionRepoProvider).changeMyEmail(v),
        success: tr('أرسلنا رابط تأكيد إلى {0} · يتغير البريد بعد الضغط عليه', [v]));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: tr('تغيير البريد الإلكتروني'),
      busy: _busy,
      onSubmit: _save,
      submitLabel: tr('إرسال رابط التأكيد'),
      children: [
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('البريد الجديد')),
        ),
        const SizedBox(height: 8),
        Text(tr('للحماية: يصلك رابط تأكيد على البريد الجديد، ويبقى القديم فعّالًا حتى تضغطه.'),
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1.text.length < 8) {
      showSnack(context, tr('كلمة المرور يجب أن تكون ٨ أحرف على الأقل'));
      return;
    }
    if (_p1.text != _p2.text) {
      showSnack(context, tr('كلمتا المرور غير متطابقتين'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(sectionRepoProvider).changeMyPassword(_p1.text),
        success: tr('تم تغيير كلمة المرور'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: tr('تغيير كلمة المرور'),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(
          controller: _p1,
          autofocus: true,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('كلمة المرور الجديدة'),
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _p2,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('تأكيد كلمة المرور')),
        ),
      ],
    );
  }
}
