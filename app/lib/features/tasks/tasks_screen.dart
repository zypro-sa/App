import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

/// ٣ · المهام
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _assignedByMe = false;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider(_assignedByMe));
    final mine = ref.watch(tasksProvider(false)).valueOrNull;
    final team = ref.watch(tasksProvider(true)).valueOrNull;

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
            const Text('المهام', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
              'أنجزت $doneToday من ${todayTasks.length} اليوم',
              style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('مهامي ${_openCount(mine)}')),
                ButtonSegment(value: true, label: Text('أسندتها للفريق ${_openCount(team)}')),
              ],
              selected: {_assignedByMe},
              onSelectionChanged: (s) => setState(() => _assignedByMe = s.first),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: ProgressLine(percent, color: AppColors.done, height: 8)),
                const SizedBox(width: 10),
                Text('$percent٪', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.done)),
              ],
            ),
            const SizedBox(height: 14),
            AsyncBody<List<TaskItem>>(
              value: tasks,
              onRetry: () => ref.invalidate(tasksProvider(_assignedByMe)),
              builder: (list) => list.isEmpty
                  ? const EmptyState('لا توجد مهام', icon: Icons.check_circle_outline)
                  : _GroupedTasks(tasks: list, showAssignee: _assignedByMe),
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
        _Group('متأخرة', overdue, color: AppColors.urgent, showAssignee: showAssignee),
        _Group('اليوم', todayList, showAssignee: showAssignee),
        _Group('هذا الأسبوع', week, showAssignee: showAssignee),
        _Group('لاحقًا', later, showAssignee: showAssignee),
        _Group('منجزة مؤخرًا', done, showAssignee: showAssignee),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.tasks, {this.color = AppColors.subtle, required this.showAssignee});

  final String title;
  final List<TaskItem> tasks;
  final Color color;
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
                  if (i > 0) const Divider(height: 1, color: AppColors.divider),
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
    final tags = <Widget>[
      if (!t.isDone && t.priority == Priority.urgent) Pill.urgent('عاجل'),
      if (t.requestNumber != null) _Tag('#${t.requestNumber}'),
      if (t.clientName != null) _Tag(t.clientName!),
      if (t.fromMeeting) Pill.info('من اجتماع'),
      if (showAssignee && t.assigneeName != null) _Tag(t.assigneeName!),
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
              await ref.read(repositoryProvider).setTaskDone(t.id, v);
              refreshAll(ref);
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
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  String _dueLabel(DateTime d) {
    final day = relativeDay(d);
    final hasTime = d.hour != 0 || d.minute != 0;
    if (day == 'اليوم') return hasTime ? formatTime(d) : 'اليوم';
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
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.subtle)),
    );
  }
}
