import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';

/// ٨ · المزيد
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider);
    bool can(String k) => profile?.can(k) ?? false;

    void soon() => showSnack(context, tr('هذا القسم في المرحلة القادمة'));

    final sections = <_Section>[
      _Section(tr('العملاء'), Icons.people_outline, AppColors.primary, AppColors.primarySoft, () => context.go('/more/clients')),
      _Section(tr('المشاريع'), Icons.folder_outlined, AppColors.done, AppColors.doneSoft, () => context.go('/more/projects')),
      _Section(tr('المتابعات'), Icons.schedule, AppColors.waiting, AppColors.waitingSoft, () => context.go('/more/followups')),
      if (can(Permissions.financeManage)) _Section(tr('المالية'), Icons.receipt_long_outlined, AppColors.urgent, AppColors.urgentSoft, () => context.go('/more/finance')),
      _Section(tr('الملاحظات'), Icons.sticky_note_2_outlined, AppColors.subtle, AppColors.neutralSoft, () => context.go('/more/notes')),
      if (can(Permissions.reportsView)) _Section(tr('التقارير'), Icons.bar_chart, AppColors.primary, AppColors.primarySoft, () => context.go('/more/reports')),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Row(
              children: [
                Avatar(profile?.initial ?? tr('؟'), size: 52, fg: AppColors.accent, bg: AppColors.hero, radius: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.name ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      Text(
                        [profile?.role.label, profile?.jobTitle].whereType<String>().join(' · '),
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [for (final s in sections) _SectionTile(s)],
            ),
            const SizedBox(height: 16),
            CardBox(
              radius: 16,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (can(Permissions.settingsFields) || can(Permissions.settingsLists) || can(Permissions.dataDelete)) ...[
                    ListTile(
                      title: Text(tr('لوحة التحكم والإعدادات'), style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Icon(AppIcons.forward),
                      onTap: () => context.go('/more/settings'),
                    ),
                    Divider(height: 1, color: AppColors.divider),
                  ],
                  ListTile(title: Text(tr('الفريق والصلاحيات')), trailing: Icon(AppIcons.forward), onTap: () => context.go('/more/team')),
                  Divider(height: 1, color: AppColors.divider),
                  ListTile(title: Text(tr('الإشعارات والتذكيرات')), trailing: Icon(AppIcons.forward), onTap: () => context.go('/more/notifications')),
                  Divider(height: 1, color: AppColors.divider),
                  ListTile(
                    title: Text(tr('المظهر')),
                    leading: Icon(AppColors.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
                    subtitle: Text(_themeLabel(settings.themeMode), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    trailing: Icon(AppIcons.forward),
                    onTap: () => _pickTheme(context, ref),
                  ),
                  Divider(height: 1, color: AppColors.divider),
                  ListTile(
                    title: Text(tr('اللغة')),
                    leading: const Icon(Icons.translate),
                    subtitle: Text(L.isEn ? 'English' : 'العربية', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    trailing: Icon(AppIcons.forward),
                    onTap: () => _pickLanguage(context, ref),
                  ),
                  Divider(height: 1, color: AppColors.divider),
                  if (can(Permissions.financeManage)) ...[
                    ListTile(
                      title: Text(tr('ربط دفترة')),
                      leading: const Icon(Icons.sync_alt),
                      subtitle: Text(tr('العملاء والفواتير والدفعات وعروض الأسعار'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      trailing: Icon(AppIcons.forward),
                      onTap: () => context.go('/more/daftra'),
                    ),
                    Divider(height: 1, color: AppColors.divider),
                  ],
                  ListTile(title: Text(tr('ربط التقويم والبريد')), trailing: Icon(AppIcons.forward), onTap: soon),
                  Divider(height: 1, color: AppColors.divider),
                  ListTile(
                    title: Text(tr('تسجيل الخروج'), style: TextStyle(color: AppColors.urgent)),
                    leading: Icon(Icons.logout, color: AppColors.urgent),
                    onTap: () => Supabase.instance.client.auth.signOut(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _themeLabel(ThemeMode m) => switch (m) {
      ThemeMode.light => tr('فاتح'),
      ThemeMode.dark => tr('داكن'),
      ThemeMode.system => tr('حسب إعداد الجوال'),
    };

Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final current = ref.read(appSettingsProvider).themeMode;
  final picked = await _choiceSheet<ThemeMode>(
    context,
    title: tr('المظهر'),
    current: current,
    options: [
      (ThemeMode.light, tr('فاتح'), Icons.light_mode_outlined),
      (ThemeMode.dark, tr('داكن'), Icons.dark_mode_outlined),
      (ThemeMode.system, tr('حسب إعداد الجوال'), Icons.brightness_auto_outlined),
    ],
  );
  if (picked != null) ref.read(appSettingsProvider.notifier).setTheme(picked);
}

Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
  final picked = await _choiceSheet<String>(
    context,
    title: tr('اللغة'),
    current: L.code,
    options: const [
      ('ar', 'العربية', Icons.translate),
      ('en', 'English', Icons.translate),
    ],
    note: tr('تصلك الإشعارات والتذكيرات باللغة نفسها'),
  );
  if (picked != null) await ref.read(appSettingsProvider.notifier).setLocale(picked);
}

Future<T?> _choiceSheet<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<(T, String, IconData)> options,
  String? note,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(o.$3),
              title: Text(o.$2),
              trailing: o.$1 == current ? const Icon(Icons.check_circle, color: AppColors.accent) : null,
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(note, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _Section {
  _Section(this.label, this.icon, this.fg, this.bg, this.onTap);
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;
}

class _SectionTile extends StatelessWidget {
  const _SectionTile(this.s);
  final _Section s;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      onTap: s.onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(s.icon, color: s.fg, size: 22),
          ),
          Text(s.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
