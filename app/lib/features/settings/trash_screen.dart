import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ٢١ · سلة المحذوفات
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashProvider);
    final me = ref.watch(profileProvider).valueOrNull;
    final isOwner = me?.role == UserRole.owner;
    final canRestore = me?.can(Permissions.dataDelete) ?? false;
    final repo = ref.read(sectionRepoProvider);

    return Scaffold(
      appBar: sectionAppBar('سلة المحذوفات', subtitle: 'تُحذف نهائيًا بعد ٣٠ يومًا'),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(trashProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: const Row(
                children: [
                  Icon(Icons.restore, size: 18, color: Color(0xFF163BA0)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('الاسترجاع يعيد العنصر بكل بياناته وارتباطاته',
                        style: TextStyle(fontSize: 13, color: Color(0xFF163BA0))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AsyncBody<List<TrashItem>>(
              value: trash,
              onRetry: () => ref.invalidate(trashProvider),
              builder: (list) {
                if (list.isEmpty) return const EmptyState('السلة فارغة', icon: Icons.delete_outline);
                final groups = <String, List<TrashItem>>{};
                for (final t in list) {
                  groups.putIfAbsent(t.entity, () => []).add(t);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in groups.entries) ...[
                      Text('${TrashItem.labels[g.key] ?? g.key} · ${g.value.length}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                      const SizedBox(height: 8),
                      CardBox(
                        radius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            for (var i = 0; i < g.value.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: AppColors.divider),
                              _TrashRow(item: g.value[i], canPurge: isOwner, canRestore: canRestore),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (isOwner)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.urgent,
                          side: const BorderSide(color: AppColors.urgentBorder),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: () async {
                          final ok = await confirmAction(
                            context,
                            title: 'إفراغ السلة نهائيًا؟',
                            message: 'سيُحذف ${list.length} عنصرًا ولا يمكن استرجاعها بعد ذلك.',
                            confirmLabel: 'حذف نهائي',
                            destructive: true,
                          );
                          if (!ok || !context.mounted) return;
                          await runAction(context, () async {
                            for (final t in list) {
                              try {
                                await repo.deleteForever(t);
                              } catch (_) {
                                // عنصر مرتبط ببيانات أخرى يبقى في السلة
                              }
                            }
                          }, success: 'أُفرغت السلة');
                          refreshSections(ref);
                        },
                        child: const Text('إفراغ السلة نهائيًا'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.item, required this.canPurge, required this.canRestore});
  final TrashItem item;
  final bool canPurge;
  final bool canRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = item.daysLeft;
    final repo = ref.read(sectionRepoProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (item.deletedByName != null) 'حذفه ${item.deletedByName}',
                    relativeDay(item.deletedAt),
                    days <= 3 ? 'يُحذف نهائيًا بعد ${days < 1 ? 'أقل من يوم' : '$days أيام'}' : 'يبقى $days يومًا',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: days <= 3 ? AppColors.urgent : AppColors.muted,
                    fontWeight: days <= 3 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (canRestore)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
            onPressed: () async {
              if (await runAction(context, () => repo.restore(item), success: 'استُرجع العنصر')) {
                refreshSections(ref);
              }
            },
            child: const Text('استرجاع'),
          ),
          if (canPurge)
            IconButton(
              tooltip: 'حذف نهائي',
              icon: const Icon(Icons.delete_forever_outlined, color: AppColors.urgent),
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: 'حذف نهائي؟',
                  message: '«${item.title}» سيُحذف ولا يمكن استرجاعه.',
                  confirmLabel: 'حذف نهائي',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                if (await runAction(context, () => repo.deleteForever(item), success: 'حُذف نهائيًا')) {
                  refreshSections(ref);
                }
              },
            ),
        ],
      ),
    );
  }
}
