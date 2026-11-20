import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/push/push.dart';
import '../../core/theme.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

/// إعدادات الإشعارات: تفعيلها على هذا الجهاز، وأنواع التذكيرات.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _busy = false;
  late String _permission = PushSupport.permission;

  void _enable() {
    // يجب أن يبدأ طلب الإذن مباشرة من الضغطة (شرط آبل)، قبل أي await
    final future = PushSupport.subscribe(AppConfig.vapidPublicKey);
    setState(() => _busy = true);
    future.then((sub) async {
      if (!mounted) return;
      setState(() => _permission = PushSupport.permission);
      if (sub == null) {
        showSnack(context, _permission == 'denied'
            ? tr('الإذن مرفوض. فعّله من إعدادات الجوال ← الإشعارات ← Zypro')
            : tr('لم يتم التفعيل'));
        return;
      }
      if (await runAction(context, () => ref.read(sectionRepoProvider).savePushSubscription(sub, null),
          success: tr('تم تفعيل الإشعارات على هذا الجهاز'))) {
        ref.invalidate(myDeviceCountProvider);
      }
    }).catchError((Object e) {
      if (mounted) showSnack(context, tr('تعذّر التفعيل: {0}', [e]));
    }).whenComplete(() {
      if (mounted) setState(() => _busy = false);
    });
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      final endpoint = await PushSupport.unsubscribe();
      if (endpoint != null) await ref.read(sectionRepoProvider).deletePushSubscription(endpoint);
      ref.invalidate(myDeviceCountProvider);
      if (mounted) showSnack(context, tr('أُوقفت الإشعارات على هذا الجهاز'));
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّر الإيقاف: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notifyPrefsProvider).valueOrNull ?? const <String, dynamic>{};
    final devices = ref.watch(myDeviceCountProvider).valueOrNull;
    final supported = kIsWeb && PushSupport.supported;
    final granted = _permission == 'granted';
    final needsHomeScreen = kIsWeb && !PushSupport.standalone && !supported;

    return Scaffold(
      appBar: sectionAppBar(tr('الإشعارات والتذكيرات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          CardBox(
            radius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.notifications_active_outlined, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('إشعارات الجوال'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(
                            !supported
                                ? tr('غير متاحة في هذا المتصفح')
                                : granted
                                    ? tr('مفعّلة على هذا الجهاز{0}', [devices != null ? tr(' · أجهزتك: {0}', [devices]) : ''])
                                    : tr('تصلك التذكيرات حتى والتطبيق مغلق'),
                            style: TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (needsHomeScreen)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.waitingSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      tr('على الآيفون: افتح Zypro من أيقونته على الشاشة الرئيسية (Safari ← مشاركة ← إضافة إلى الشاشة الرئيسية)، ثم فعّل الإشعارات من هنا. يتطلب iOS 16.4 أو أحدث.'),
                      style: TextStyle(fontSize: 12, height: 1.7, color: AppColors.waiting),
                    ),
                  )
                else if (supported && !granted)
                  FilledButton.icon(
                    onPressed: _busy ? null : _enable,
                    icon: const Icon(Icons.notifications_active),
                    label: Text(tr('تفعيل الإشعارات على هذا الجهاز')),
                  )
                else if (supported && granted)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => runAction(context, () => ref.read(sectionRepoProvider).sendTestNotification(),
                                  success: tr('أُرسل إشعار تجريبي')),
                          child: Text(tr('إرسال إشعار تجريبي')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _enable,
                          child: Text(tr('إعادة الربط')),
                        ),
                      ),
                    ],
                  ),
                if (supported && granted) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : _disable,
                    child: Text(tr('إيقاف الإشعارات على هذا الجهاز'), style: TextStyle(color: AppColors.urgent)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(tr('ما الذي يصلك؟'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
          const SizedBox(height: 4),
          Text(tr('تظهر في مركز الإشعارات دائمًا، وتصل للجوال إن كانت مفعّلة.'),
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          CardBox(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                for (var i = 0; i < NotificationKinds.all.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    value: prefs[NotificationKinds.all[i].$1] != false,
                    onChanged: (v) async {
                      final next = Map<String, dynamic>.from(prefs);
                      if (v) {
                        next.remove(NotificationKinds.all[i].$1);
                      } else {
                        next[NotificationKinds.all[i].$1] = false;
                      }
                      if (await runAction(context, () => ref.read(sectionRepoProvider).setNotifyPrefs(next))) {
                        ref.invalidate(notifyPrefsProvider);
                      }
                    },
                    title: Text(NotificationKinds.all[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(NotificationKinds.all[i].$3, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('المواعيد بتوقيت السعودية، والتذكيرات تُفحص كل ١٥ دقيقة.'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}
