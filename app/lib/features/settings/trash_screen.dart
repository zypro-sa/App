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
import '../../core/i18n.dart';

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
      appBar: sectionAppBar(tr('سلة المحذوفات'), subtitle: tr('تُحذف نهائيًا بعد ٣٠ يومًا')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(trashProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.restore, size: 18, color: AppColors.accentText),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('الاسترجاع يعيد العنصر بكل بياناته وارتباطاته'),
                        style: TextStyle(fontSize: 13, color: AppColors.accentText)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AsyncBody<List<TrashItem>>(
              value: trash,
              onRetry: () => ref.invalidate(trashProvider),
              builder: (list) {
                if (list.isEmpty) return EmptyState(tr('السلة فارغة'), icon: Icons.delete_outline);
                final groups = <String, List<TrashItem>>{};
                for (final t in list) {
                  groups.putIfAbsent(t.entity, () => []).add(t);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in groups.entries) ...[
                      Text('${TrashItem.labels[g.key] ?? g.key} · ${g.value.length}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                      const SizedBox(height: 8),
                      CardBox(
                        radius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            for (var i = 0; i < g.value.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: AppColors.divider),
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
                          side: BorderSide(color: AppColors.urgentBorder),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: () async {
                          final ok = await confirmAction(
                            context,
                            title: tr('إفراغ السلة نهائيًا؟'),
                            message: tr('سيُحذف {0} عنصرًا ولا يمكن استرجاعها بعد ذلك.', [list.length]),
                            confirmLabel: tr('حذف نهائي'),
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
                          }, success: tr('أُفرغت السلة'));
                          refreshSections(ref);
                        },
                        child: Text(tr('إفراغ السلة نهائيًا')),
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
                    if (item.deletedByName != null) tr('حذفه {0}', [item.deletedByName]),
                    relativeDay(item.deletedAt),
                    days <= 3 ? tr('يُحذف نهائيًا بعد {0}', [days < 1 ? tr('أقل من يوم') : tr('{0} أيام', [days])]) : tr('يبقى {0} يومًا', [days]),
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
              side: BorderSide(color: AppColors.primary),
            ),
            onPressed: () async {
              if (await runAction(context, () => repo.restore(item), success: tr('استُرجع العنصر'))) {
                refreshSections(ref);
              }
            },
            child: Text(tr('استرجاع')),
          ),
          if (canPurge)
            IconButton(
              tooltip: tr('حذف نهائي'),
              icon: Icon(Icons.delete_forever_outlined, color: AppColors.urgent),
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: tr('حذف نهائي؟'),
                  message: tr('«{0}» سيُحذف ولا يمكن استرجاعه.', [item.title]),
                  confirmLabel: tr('حذف نهائي'),
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                if (await runAction(context, () => repo.deleteForever(item), success: tr('حُذف نهائيًا'))) {
                  refreshSections(ref);
                }
              },
            ),
        ],
      ),
    );
  }
}
