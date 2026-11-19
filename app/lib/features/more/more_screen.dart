import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

/// ٨ · المزيد
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    bool can(String k) => profile?.can(k) ?? false;

    void soon() => showSnack(context, 'هذا القسم في المرحلة القادمة');

    final sections = <_Section>[
      _Section('العملاء', Icons.people_outline, AppColors.primary, AppColors.primarySoft, () => context.go('/more/clients')),
      _Section('المشاريع', Icons.folder_outlined, AppColors.done, AppColors.doneSoft, () => context.go('/more/projects')),
      _Section('المتابعات', Icons.schedule, AppColors.waiting, AppColors.waitingSoft, () => context.go('/more/followups')),
      if (can(Permissions.financeManage)) _Section('المالية', Icons.receipt_long_outlined, AppColors.urgent, AppColors.urgentSoft, () => context.go('/more/finance')),
      _Section('الملاحظات', Icons.sticky_note_2_outlined, AppColors.subtle, AppColors.neutralSoft, () => context.go('/more/notes')),
      if (can(Permissions.reportsView)) _Section('التقارير', Icons.bar_chart, AppColors.primary, AppColors.primarySoft, () => context.go('/more/reports')),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Row(
              children: [
                Avatar(profile?.initial ?? '؟', size: 52, fg: Colors.white, bg: AppColors.primary, radius: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.name ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      Text(
                        [profile?.role.label, profile?.jobTitle].whereType<String>().join(' · '),
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
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
                      title: const Text('لوحة التحكم والإعدادات', style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => context.go('/more/settings'),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                  ],
                  ListTile(title: const Text('الفريق والصلاحيات'), trailing: const Icon(Icons.chevron_left), onTap: () => context.go('/more/team')),
                  const Divider(height: 1, color: AppColors.divider),
                  ListTile(title: const Text('الإشعارات والتذكيرات'), trailing: const Icon(Icons.chevron_left), onTap: soon),
                  const Divider(height: 1, color: AppColors.divider),
                  ListTile(title: const Text('ربط التقويم والبريد'), trailing: const Icon(Icons.chevron_left), onTap: soon),
                  const Divider(height: 1, color: AppColors.divider),
                  ListTile(
                    title: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.urgent)),
                    leading: const Icon(Icons.logout, color: AppColors.urgent),
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
