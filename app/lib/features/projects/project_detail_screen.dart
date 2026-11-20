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
import '../tasks/tasks_screen.dart' show TaskRow;
import '../../core/i18n.dart';

/// ١٠ · تفاصيل المشروع
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider(widget.projectId));
    final canManage = ref.watch(profileProvider).valueOrNull?.can(Permissions.projectsManage) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('تفاصيل المشروع')),
        centerTitle: true,
        actions: [
          if (canManage)
            PopupMenuButton<String>(
              tooltip: tr('خيارات'),
              onSelected: (v) async {
                final repo = ref.read(sectionRepoProvider);
                if (v == 'delete') {
                  final ok = await confirmAction(context,
                      title: tr('حذف المشروع؟'),
                      message: tr('ينتقل إلى سلة المحذوفات ويمكن استرجاعه خلال ٣٠ يومًا.'),
                      confirmLabel: tr('حذف'),
                      destructive: true);
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.softDelete('projects', [widget.projectId]), success: tr('نُقل إلى السلة'))) {
                    refreshSections(ref);
                    if (context.mounted) Navigator.of(context).maybePop();
                  }
                } else {
                  final s = ProjectStatus.from(v);
                  if (await runAction(context, () => repo.setProjectStatus(widget.projectId, s), success: tr('تم تغيير الحالة'))) {
                    refreshSections(ref);
                  }
                }
              },
              itemBuilder: (_) => [
                for (final s in ProjectStatus.values) PopupMenuItem(value: s.db, child: Text(tr('تغيير الحالة: {0}', [s.label]))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text(tr('حذف المشروع'), style: TextStyle(color: AppColors.urgent))),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSections(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<Project>(
              value: project,
              onRetry: () => ref.invalidate(projectProvider(widget.projectId)),
              builder: (p) => _Header(p),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, label: Text(tr('المراحل'))),
                ButtonSegment(value: 1, label: Text(tr('المهام'))),
                ButtonSegment(value: 2, label: Text(tr('الطلبات'))),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 14),
            if (_tab == 0) _Milestones(projectId: widget.projectId, canEdit: canManage),
            if (_tab == 1) _Tasks(projectId: widget.projectId),
            if (_tab == 2) _Requests(projectId: widget.projectId),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header(this.p);
  final Project p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = {
      for (final l in ref.watch(statusLabelsProvider(ConfigEntity.project)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };
    final sl = labels[p.status.db];
    final days = p.daysLeft;
    final openTasks = ref.watch(projectTasksProvider(p.id)).valueOrNull?.where((t) => !t.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [p.clientName, if (p.managerName != null) tr('مدير المشروع: {0}', [p.managerName])].whereType<String>().join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  statusPill(sl?.label ?? p.status.label, sl?.color ?? 'neutral'),
                ],
              ),
              const SizedBox(height: 8),
              Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: ProgressLine(p.progress, height: 10)),
                  const SizedBox(width: 10),
                  Text(tr('{0}٪', [p.progress]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Metric(p.contractValue == null ? '—' : moneyShort(p.contractValue!), tr('قيمة العقد'))),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(
                days == null ? '—' : (days < 0 ? tr('متأخر {0}', [-days]) : tr('{0} يومًا', [days])),
                days != null && days < 0 ? tr('عن التسليم') : tr('على التسليم'),
                warn: days != null && days <= 7,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _Metric(openTasks?.toString() ?? '…', tr('مهام مفتوحة'))),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label, {this.warn = false});
  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final fg = warn ? AppColors.urgent : AppColors.ink;
    return CardBox(
      radius: 14,
      padding: const EdgeInsets.all(12),
      color: warn ? AppColors.urgentSoft : AppColors.surface,
      borderColor: warn ? AppColors.urgentBorder : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg))),
          Text(label, style: TextStyle(fontSize: 12, color: warn ? AppColors.urgent : AppColors.muted)),
        ],
      ),
    );
  }
}

class _Milestones extends ConsumerWidget {
  const _Milestones({required this.projectId, required this.canEdit});
  final String projectId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ms = ref.watch(milestonesProvider(projectId));
    final repo = ref.read(sectionRepoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsyncBody<List<Milestone>>(
          value: ms,
          builder: (list) {
            if (list.isEmpty) return EmptyState(tr('أضف مراحل المشروع لتُحسب نسبة الإنجاز تلقائيًا'), icon: Icons.flag_outlined);
            final firstOpen = list.indexWhere((m) => !m.isDone);
            return CardBox(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.divider),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: TaskCheck(
                        done: list[i].isDone,
                        onChanged: (v) async {
                          if (await runAction(context, () => repo.setMilestoneDone(list[i].id, v))) {
                            refreshSections(ref);
                          }
                        },
                      ),
                      title: Text(
                        list[i].title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == firstOpen ? FontWeight.w700 : FontWeight.w500,
                          color: list[i].isDone ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                      trailing: list[i].dueDate == null
                          ? null
                          : Text(
                              formatShortDate(list[i].dueDate!),
                              style: TextStyle(
                                fontSize: 12,
                                color: (!list[i].isDone && list[i].dueDate!.isBefore(DateTime.now())) ? AppColors.urgent : AppColors.muted,
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        if (canEdit) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final title = await promptText(context, tr('مرحلة جديدة'), label: tr('اسم المرحلة'), confirmLabel: tr('التالي'));
              if (title == null || !context.mounted) return;
              final due = await pickDate(context);
              if (!context.mounted) return;
              if (await runAction(context, () => repo.addMilestone(projectId, title, due), success: tr('أُضيفت المرحلة'))) {
                refreshSections(ref);
              }
            },
            icon: const Icon(Icons.add),
            label: Text(tr('إضافة مرحلة')),
          ),
        ],
      ],
    );
  }
}

class _Tasks extends ConsumerWidget {
  const _Tasks({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<TaskItem>>(
      value: ref.watch(projectTasksProvider(projectId)),
      builder: (list) => list.isEmpty
          ? EmptyState(tr('لا توجد مهام مرتبطة بهذا المشروع'), icon: Icons.check_box_outlined)
          : CardBox(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.divider),
                    TaskRow(task: list[i], showAssignee: true),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Requests extends ConsumerWidget {
  const _Requests({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<RequestItem>>(
      value: ref.watch(projectRequestsProvider(projectId)),
      builder: (list) => list.isEmpty
          ? EmptyState(tr('لا توجد طلبات مرتبطة بهذا المشروع'))
          : Column(
              children: [
                for (final r in list) ...[
                  CardBox(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${r.number}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              Text(r.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Pill.forRequest(r),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}
