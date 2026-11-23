import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart' show runAction;
import '../../widgets/people_picker.dart';
import '../../core/i18n.dart';

/// ٣ · المهام
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

enum _View { mine, done, team }

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _View _view = _View.mine;
  bool get _assignedByMe => _view == _View.team;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider(_assignedByMe));
    final mine = ref.watch(tasksProvider(false)).valueOrNull;
    final team = ref.watch(tasksProvider(true)).valueOrNull;
    final done = ref.watch(doneTasksProvider);

    final list = tasks.valueOrNull ?? const <TaskItem>[];
    final today = dateOnly(DateTime.now());
    final todayTasks = list.where((t) => t.dueAt != null && dateOnly(t.dueAt!) == today).toList();
    final doneToday = todayTasks.where((t) => t.isDone).length;
    final percent = todayTasks.isEmpty ? 0 : (doneToday * 100 / todayTasks.length).round();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('المهام'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
              tr('أنجزت {0} من {1} اليوم', [doneToday, todayTasks.length]),
              style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SegmentedButton<_View>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _View.mine, label: Text(tr('مهامي {0}', [_openCount(mine)]))),
                ButtonSegment(value: _View.done, label: Text(tr('المنجزة'))),
                ButtonSegment(value: _View.team, label: Text(tr('أسندتها {0}', [_openCount(team)]))),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: ProgressLine(percent, height: 8)),
                const SizedBox(width: 10),
                Text(tr('{0}٪', [percent]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.done)),
              ],
            ),
            const SizedBox(height: 14),
            if (_view == _View.done)
              AsyncBody<List<TaskItem>>(
                value: done,
                onRetry: () => ref.invalidate(doneTasksProvider),
                builder: (list) => list.isEmpty
                    ? EmptyState(tr('لم تُنجز أي مهمة بعد'), icon: Icons.task_alt)
                    : _DoneTasks(tasks: list),
              )
            else
              AsyncBody<List<TaskItem>>(
                value: tasks,
                onRetry: () => ref.invalidate(tasksProvider(_assignedByMe)),
                builder: (list) {
                  // مهامي: المفتوحة فقط — المنجزة تنتقل إلى «المنجزة»
                  final shown = _view == _View.mine ? list.where((t) => !t.isDone).toList() : list;
                  return shown.isEmpty
                      ? EmptyState(
                          _view == _View.mine ? tr('لا توجد مهام مفتوحة — أحسنت!') : tr('لا توجد مهام'),
                          icon: Icons.check_circle_outline,
                        )
                      : _GroupedTasks(tasks: shown, showAssignee: _assignedByMe);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _openCount(List<TaskItem>? l) => l == null ? '' : '${l.where((t) => !t.isDone).length}';
}

class _GroupedTasks extends StatelessWidget {
  const _GroupedTasks({required this.tasks, required this.showAssignee});

  final List<TaskItem> tasks;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final weekEnd = today.add(const Duration(days: 7));

    final overdue = <TaskItem>[];
    final todayList = <TaskItem>[];
    final week = <TaskItem>[];
    final later = <TaskItem>[];
    final done = <TaskItem>[];

    for (final t in tasks) {
      if (t.isDone && (t.dueAt == null || dateOnly(t.dueAt!) != today)) {
        done.add(t);
      } else if (t.isOverdue) {
        overdue.add(t);
      } else if (t.dueAt != null && dateOnly(t.dueAt!) == today) {
        todayList.add(t);
      } else if (t.dueAt != null && t.dueAt!.isBefore(weekEnd)) {
        week.add(t);
      } else {
        later.add(t);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(tr('متأخرة'), overdue, color: AppColors.urgent, showAssignee: showAssignee),
        _Group(tr('اليوم'), todayList, showAssignee: showAssignee),
        _Group(tr('هذا الأسبوع'), week, showAssignee: showAssignee),
        _Group(tr('لاحقًا'), later, showAssignee: showAssignee),
        _Group(tr('منجزة مؤخرًا'), done, showAssignee: showAssignee),
      ],
    );
  }
}

/// مهامي المنجزة مجمّعة حسب تاريخ الإنجاز
class _DoneTasks extends StatelessWidget {
  const _DoneTasks({required this.tasks});
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final groups = <String, List<TaskItem>>{};
    for (final t in tasks) {
      final d = t.completedAt == null ? null : dateOnly(t.completedAt!);
      final key = d == null
          ? tr('سابقًا')
          : d == today
              ? tr('اليوم')
              : d == today.subtract(const Duration(days: 1))
                  ? tr('أمس')
                  : today.difference(d).inDays < 7
                      ? tr('هذا الأسبوع')
                      : formatPattern('MMMM y', d);
      (groups[key] ??= []).add(t);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in groups.entries) _Group(e.key, e.value, color: AppColors.done, showAssignee: false),
        if (tasks.length >= 300)
          Text(tr('تظهر آخر ٣٠٠ مهمة منجزة'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.faint)),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.tasks, {Color? color, required this.showAssignee}) : _color = color;

  final String title;
  final List<TaskItem> tasks;
  final Color? _color;
  Color get color => _color ?? AppColors.subtle;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$title · ${tasks.length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ),
          CardBox(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  TaskRow(task: tasks[i], showAssignee: showAssignee),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صف مهمة مع مربع الإنجاز والوسوم.
class TaskRow extends ConsumerWidget {
  const TaskRow({super.key, required this.task, this.showAssignee = false});

  final TaskItem task;
  final bool showAssignee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    final me = ref.watch(profileProvider).valueOrNull;
    final canReassign = !t.isDone &&
        (me?.can(Permissions.tasksAssign) ?? false) &&
        (t.assignedById == me?.id || (me?.can(Permissions.tasksEdit) ?? false));
    final tags = <Widget>[
      if (!t.isDone && t.priority == Priority.urgent) Pill.urgent(tr('عاجل')),
      if (t.requestNumber != null) _Tag('#${t.requestNumber}'),
      if (t.clientName != null) _Tag(t.clientName!),
      if (t.fromMeeting) Pill.info(tr('من اجتماع')),
      if (showAssignee && t.peopleLabel.isNotEmpty) _Tag(t.peopleLabel)
      else if (t.isShared) Pill.info(tr('مشتركة · {0}', [t.people.length])),
      if (t.dueAt != null)
        Text(
          t.isOverdue ? relativeDay(t.dueAt!) : _dueLabel(t.dueAt!),
          style: TextStyle(
            fontSize: 11,
            color: t.isOverdue ? AppColors.urgent : AppColors.muted,
            fontWeight: t.isOverdue ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskCheck(
            done: t.isDone,
            overdue: t.isOverdue,
            onChanged: (v) async {
              final repo = ref.read(repositoryProvider);
              final messenger = ScaffoldMessenger.of(context);
              final container = ProviderScope.containerOf(context, listen: false);
              await repo.setTaskDone(t.id, v);
              refreshAll(ref);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(v ? tr('نُقلت إلى «المنجزة»') : tr('أُعيدت إلى «مهامي»')),
                  action: SnackBarAction(
                    label: tr('تراجع'),
                    onPressed: () async {
                      await repo.setTaskDone(t.id, !v);
                      refreshAllIn(container);
                    },
                  ),
                ));
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: t.isDone ? AppColors.muted : AppColors.ink,
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: tags),
                  ],
                ],
              ),
            ),
          ),
          if (canReassign)
            IconButton(
              tooltip: tr('المسؤولون'),
              visualDensity: VisualDensity.compact,
              icon: Icon(t.isShared ? Icons.group_outlined : Icons.person_add_alt, size: 20, color: AppColors.muted),
              onPressed: () async {
                final team = ref.read(teamProvider).valueOrNull ?? const <Profile>[];
                final current = [t.assigneeId, for (final p in t.people) if (p.$1 != t.assigneeId) p.$1];
                final v = await pickPeople(
                  context,
                  team: team,
                  selected: current,
                  title: tr('إسناد المهمة'),
                  hint: tr('يمكنك اختيار أكثر من شخص للمهمة نفسها'),
                );
                if (v == null || v.isEmpty || !context.mounted) return;
                if (await runAction(context, () => ref.read(repositoryProvider).setTaskAssignees(t, v), success: tr('حُدّث المسؤولون'))) {
                  refreshAll(ref);
                }
              },
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }

  String _dueLabel(DateTime d) {
    final day = relativeDay(d);
    final hasTime = d.hour != 0 || d.minute != 0;
    if (day == tr('اليوم')) return hasTime ? formatTime(d) : tr('اليوم');
    return day;
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: AppColors.subtle)),
    );
  }
}
