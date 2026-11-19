import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ١٧ · لوحة التحكم
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _icons = {
    ConfigEntity.request: (Icons.inbox_outlined, AppColors.primary, AppColors.primarySoft),
    ConfigEntity.task: (Icons.check_box_outlined, AppColors.done, AppColors.doneSoft),
    ConfigEntity.meeting: (Icons.calendar_today_outlined, AppColors.waiting, AppColors.waitingSoft),
    ConfigEntity.client: (Icons.people_outline, AppColors.primary, AppColors.primarySoft),
    ConfigEntity.project: (Icons.folder_outlined, AppColors.done, AppColors.doneSoft),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).valueOrNull?.role;
    if (role == UserRole.employee) {
      return Scaffold(appBar: sectionAppBar('لوحة التحكم'), body: const EmptyState('لوحة التحكم للمالك والمدير', icon: Icons.lock_outline));
    }
    final counts = ref.watch(fieldCountsProvider).valueOrNull ?? const {};
    final trashCount = ref.watch(trashProvider).valueOrNull?.length;

    return Scaffold(
      appBar: sectionAppBar('لوحة التحكم', subtitle: 'الحقول والقوائم والبيانات لكل قسم'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          const Text('الأقسام', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
          const SizedBox(height: 8),
          CardBox(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ConfigEntity.values.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.divider),
                  _row(
                    context,
                    icon: _icons[ConfigEntity.values[i]]!,
                    title: ConfigEntity.values[i].label,
                    subtitle: (counts[ConfigEntity.values[i]] ?? 0) == 0
                        ? 'الحقول الافتراضية'
                        : '${counts[ConfigEntity.values[i]]} حقول مخصصة',
                    onTap: () => context.go('/more/settings/section/${ConfigEntity.values[i].db}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('البيانات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
          const SizedBox(height: 8),
          CardBox(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _row(context,
                    title: 'إدارة البيانات المُدخلة',
                    subtitle: 'تحديد وتعديل وحذف جماعي',
                    onTap: () => context.go('/more/settings/data')),
                const Divider(height: 1, color: AppColors.divider),
                _row(context,
                    title: 'سلة المحذوفات',
                    subtitle: '${trashCount == null ? '' : '$trashCount عناصر · '}تُحذف نهائيًا بعد ٣٠ يومًا',
                    onTap: () => context.go('/more/settings/trash')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: AppColors.subtle),
                SizedBox(width: 8),
                Expanded(
                  child: Text('الحقول للمالك فقط · المدير يعدّل خيارات القوائم',
                      style: TextStyle(fontSize: 12, color: AppColors.subtle)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    (IconData, Color, Color)? icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: icon == null
          ? null
          : Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: icon.$3, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon.$1, color: icon.$2, size: 20),
            ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      trailing: const Icon(Icons.chevron_left, color: Color(0xFF9AA2AE)),
    );
  }
}
