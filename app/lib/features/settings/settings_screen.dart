import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

/// ١٧ · لوحة التحكم
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Map<ConfigEntity, (IconData, Color, Color)> get _icons => {
    ConfigEntity.request: (Icons.inbox_outlined, AppColors.primary, AppColors.primarySoft),
    ConfigEntity.task: (Icons.check_box_outlined, AppColors.done, AppColors.doneSoft),
    ConfigEntity.meeting: (Icons.calendar_today_outlined, AppColors.waiting, AppColors.waitingSoft),
    ConfigEntity.client: (Icons.people_outline, AppColors.primary, AppColors.primarySoft),
    ConfigEntity.project: (Icons.folder_outlined, AppColors.done, AppColors.doneSoft),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).valueOrNull;
    bool can(String k) => me?.can(k) ?? false;
    if (me != null && !can(Permissions.settingsFields) && !can(Permissions.settingsLists) && !can(Permissions.dataDelete) && !can(Permissions.settingsListsView) && !can(Permissions.settingsFieldsView) && !can(Permissions.statusesView)) {
      return Scaffold(appBar: sectionAppBar(tr('لوحة التحكم')), body: EmptyState(tr('ليست لديك صلاحية لوحة التحكم'), icon: Icons.lock_outline));
    }
    final counts = ref.watch(fieldCountsProvider).valueOrNull ?? const {};
    final trashCount = ref.watch(trashProvider).valueOrNull?.length;

    return Scaffold(
      appBar: sectionAppBar(tr('لوحة التحكم'), subtitle: tr('الحقول والقوائم والبيانات لكل قسم')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          Text(tr('الأقسام'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
          const SizedBox(height: 8),
          CardBox(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ConfigEntity.values.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  _row(
                    context,
                    icon: _icons[ConfigEntity.values[i]]!,
                    title: ConfigEntity.values[i].label,
                    subtitle: (counts[ConfigEntity.values[i]] ?? 0) == 0
                        ? tr('الحقول الافتراضية')
                        : tr('{0} حقول مخصصة', [counts[ConfigEntity.values[i]]]),
                    onTap: () => context.go('/more/settings/section/${ConfigEntity.values[i].db}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('البيانات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
          const SizedBox(height: 8),
          CardBox(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _row(context,
                    title: tr('إدارة البيانات المُدخلة'),
                    subtitle: tr('تحديد وتعديل وحذف جماعي'),
                    onTap: () => context.go('/more/settings/data')),
                Divider(height: 1, color: AppColors.divider),
                _row(context,
                    title: tr('سلة المحذوفات'),
                    subtitle: tr('{0}تُحذف نهائيًا بعد ٣٠ يومًا', [trashCount == null ? '' : tr('{0} عناصر · ', [trashCount])]),
                    onTap: () => context.go('/more/settings/trash')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: AppColors.subtle),
                SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ما يظهر هنا حسب صلاحياتك · يحددها المالك من الفريق والصلاحيات'),
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
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.muted)),
      trailing: Icon(AppIcons.forward, color: AppColors.faint),
    );
  }
}
