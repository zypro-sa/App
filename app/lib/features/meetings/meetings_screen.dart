import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';
import '../../core/voice/command_parser.dart';
import '../../widgets/voice_input.dart';
import '../../core/permissions.dart';

/// ٤ · الاجتماعات
class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  DateTime _day = dateOnly(DateTime.now());

  /// أسبوع يبدأ بالأحد.
  List<DateTime> get _week {
    final sunday = _day.subtract(Duration(days: _day.weekday % 7));
    return List.generate(7, (i) => sunday.add(Duration(days: i)));
  }

  Future<void> _pickMonthDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final meetings = ref.watch(meetingsProvider(_day));
    final count = meetings.valueOrNull?.length;
    final isToday = _day == dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('الاجتماعات'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
              '${DateFormat('MMMM y', L.code).format(_day)}'
              '${count != null ? ' · $count ${isToday ? tr('اجتماعات اليوم') : tr('اجتماعات')}' : ''}',
              style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: tr('اختيار تاريخ'), onPressed: _pickMonthDay, icon: const Icon(Icons.calendar_month_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Row(
              children: [
                for (final d in _week)
                  Expanded(
                    child: _DayChip(
                      day: d,
                      selected: d == _day,
                      onTap: () => setState(() => _day = d),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AsyncBody<List<Meeting>>(
              value: meetings,
              onRetry: () => ref.invalidate(meetingsProvider(_day)),
              builder: (list) {
                if (list.isEmpty) {
                  return EmptyState(tr('لا توجد اجتماعات في هذا اليوم'), icon: Icons.event_available_outlined);
                }
                final now = DateTime.now();
                final nextIndex = list.indexWhere((m) => m.endAt.isAfter(now) && m.status == MeetingStatus.scheduled);
                return Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      _TimelineRow(meeting: list[i], highlighted: i == nextIndex),
                      const SizedBox(height: 12),
                    ],
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

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.onTap});

  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend = day.weekday == DateTime.friday || day.weekday == DateTime.saturday;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? AppColors.inkBlock : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatWeekdayShort(day),
                    style: TextStyle(fontSize: 11, color: selected ? AppColors.onInkBlock : AppColors.muted)),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppColors.onInkBlock : (weekend ? AppColors.faint : AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.meeting, required this.highlighted});

  final Meeting meeting;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(formatTime(meeting.startAt),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.subtle)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Opacity(
            opacity: meeting.status == MeetingStatus.cancelled ? 0.55 : 1,
            child: highlighted ? _MeetingCardExpanded(meeting) : _MeetingCardCompact(meeting),
          ),
        ),
      ],
    );
  }
}

class _MeetingCardCompact extends StatelessWidget {
  const _MeetingCardCompact(this.m);
  final Meeting m;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      onTap: () => _openMinutes(context, m),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (m.status != MeetingStatus.scheduled) _statusPill(m.status),
              MeetingActions(meeting: m),
            ],
          ),
          Text(
            [
              tr('{0} دقيقة', [m.durationMinutes]),
              m.type.label,
              if (m.clientName != null) m.clientName!,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MeetingCardExpanded extends StatelessWidget {
  const _MeetingCardExpanded(this.m);
  final Meeting m;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final started = m.startAt.isBefore(now);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill.info(started ? tr('جارٍ الآن') : timeUntil(m.startAt)),
              const Spacer(),
              Text(tr('{0} دقيقة · {1}', [m.durationMinutes, m.type.label]),
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              MeetingActions(meeting: m),
            ],
          ),
          const SizedBox(height: 10),
          Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (m.clientName != null)
            Text(m.clientName!, style: TextStyle(fontSize: 13, color: AppColors.muted)),
          if (m.agenda.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('جدول الأعمال'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                  const SizedBox(height: 6),
                  for (var i = 0; i < m.agenda.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${i + 1}. ${m.agenda[i].title}', style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          ],
          if (m.attendeeCount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.group_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(tr('{0} حضور', [m.attendeeCount]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openMinutes(context, m),
                  child: Text(tr('كتابة المحضر')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => (m.minutes ?? '').trim().isEmpty
                      ? _openMinutes(context, m)
                      : openTasksFromMinutes(context, m, m.minutes!),
                  child: Text(tr('تحويل القرارات لمهام'), textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _openMinutes(BuildContext context, Meeting m) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _MinutesSheet(meeting: m),
  );
}

class _MinutesSheet extends ConsumerStatefulWidget {
  const _MinutesSheet({required this.meeting});
  final Meeting meeting;

  @override
  ConsumerState<_MinutesSheet> createState() => _MinutesSheetState();
}

class _MinutesSheetState extends ConsumerState<_MinutesSheet> {
  late final _controller = TextEditingController(text: widget.meeting.minutes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dictate() async {
    final text = await listenForSpeech(context, continuous: true);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final cur = _controller.text.trimRight();
    _controller.text = cur.isEmpty ? text.trim() : '$cur\n${text.trim()}';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  Future<void> _save({bool thenTasks = false}) async {
    setState(() => _saving = true);
    try {
      final text = _controller.text.trim();
      await ref.read(repositoryProvider).saveMinutes(widget.meeting.id, text);
      refreshAll(ref);
      if (mounted) {
        // ذكر المحضر تأجيل الاجتماع؟ نسأل قبل إغلاق النافذة
        final postpone = findPostponement(text);
        if (postpone != null) await _offerPostpone(context, ref, widget.meeting, postpone);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context);
        final rootContext = nav.context;
        nav.pop();
        messenger.showSnackBar(SnackBar(content: Text(tr('تم حفظ المحضر'))));
        if (thenTasks && text.isNotEmpty && rootContext.mounted) {
          await openTasksFromMinutes(rootContext, widget.meeting, text);
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّر الحفظ: {0}', [e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('محضر: {0}', [widget.meeting.title]),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton.filledTonal(
                tooltip: tr('إملاء بالصوت'),
                onPressed: _saving ? null : _dictate,
                icon: const Icon(Icons.mic_none),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('اكتب كل مهمة في سطر يبدأ بـ «-»، مثل: - أحمد يرسل العرض يوم الخميس'),
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 12,
            decoration: InputDecoration(hintText: tr('ما الذي نوقش؟ وما القرارات؟')),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(thenTasks: true),
                  child: Text(tr('حفظ وتحويل لمهام'), textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(tr('حفظ المحضر'))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// اقتراح المهام من المحضر، ومراجعتها، ثم إنشاؤها.
Future<void> openTasksFromMinutes(BuildContext context, Meeting m, String minutes) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _TasksFromMinutesSheet(meeting: m, minutes: minutes),
  );
}

class _TasksFromMinutesSheet extends ConsumerStatefulWidget {
  const _TasksFromMinutesSheet({required this.meeting, required this.minutes});
  final Meeting meeting;
  final String minutes;

  @override
  ConsumerState<_TasksFromMinutesSheet> createState() => _TasksFromMinutesSheetState();
}

class _TasksFromMinutesSheetState extends ConsumerState<_TasksFromMinutesSheet> {
  List<MinuteTask>? _items;
  final Map<int, String?> _assignee = {};
  final Map<int, DateTime?> _due = {};
  final Map<int, TextEditingController> _titles = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _titles.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _build(List<Profile> team) {
    if (_items != null) return;
    final items = extractTasks(widget.minutes, team: [for (final p in team) NamedRef(p.id, p.name)]);
    _items = items;
    for (var i = 0; i < items.length; i++) {
      _assignee[i] = items[i].parsed.assigneeId;
      _due[i] = items[i].parsed.when;
      _titles[i] = TextEditingController(text: items[i].parsed.title);
    }
  }

  Future<void> _pickDue(int i) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due[i] ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _due[i] = d);
  }

  Future<void> _create() async {
    final items = _items ?? const [];
    final chosen = [for (var i = 0; i < items.length; i++) if (items[i].selected && _titles[i]!.text.trim().isNotEmpty) i];
    if (chosen.isEmpty) {
      showSnack(context, tr('اختر مهمة واحدة على الأقل'));
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    try {
      for (final i in chosen) {
        await repo.createTaskFromMinutes(
          meetingId: widget.meeting.id,
          title: _titles[i]!.text.trim(),
          assigneeId: _assignee[i],
          dueAt: _due[i],
          clientId: widget.meeting.clientId,
        );
      }
      refreshAll(ref);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(tr('أُنشئت {0} مهام من المحضر', [chosen.length]))));
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّرت الإضافة: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider).valueOrNull;
    final me = ref.watch(profileProvider).valueOrNull;
    final canAssign = me?.can(Permissions.tasksAssign) ?? false;
    if (team == null) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    _build(team);
    final items = _items!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('تحويل القرارات لمهام'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            items.any((t) => t.selected)
                ? tr('اقترحتُ هذه المهام من المحضر · راجعها ثم أنشئها')
                : tr('لم أجد أسطرًا واضحة كمهام · اختر ما تريد تحويله'),
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            EmptyState(tr('المحضر فارغ'), icon: Icons.notes)
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: items[i].selected,
                        onChanged: (v) => setState(() => items[i].selected = v ?? false),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _titles[i],
                              minLines: 1,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(isDense: true),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (canAssign)
                                  PopupMenuButton<String>(
                                    tooltip: tr('المسؤول'),
                                    onSelected: (v) => setState(() => _assignee[i] = v),
                                    itemBuilder: (_) => [
                                      for (final p in team) PopupMenuItem(value: p.id, child: Text(p.name)),
                                    ],
                                    child: Chip(
                                      avatar: const Icon(Icons.person_outline, size: 16),
                                      label: Text(
                                        team.where((p) => p.id == _assignee[i]).map((p) => p.name).firstOrNull ?? tr('أنا'),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ActionChip(
                                  avatar: const Icon(Icons.event_outlined, size: 16),
                                  label: Text(
                                    _due[i] == null ? tr('بدون موعد') : relativeDay(_due[i]!),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () => _pickDue(i),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy || items.isEmpty ? null : _create,
            child: Text(tr('إنشاء المهام المختارة ({0})', [items.where((t) => t.selected).length])),
          ),
        ],
      ),
    );
  }
}


Widget _statusPill(MeetingStatus s) => switch (s) {
      MeetingStatus.done => Pill(s.label, fg: AppColors.done, bg: AppColors.doneSoft),
      MeetingStatus.postponed => Pill(s.label, fg: AppColors.waiting, bg: AppColors.waitingSoft),
      MeetingStatus.cancelled => Pill(s.label, fg: AppColors.urgent, bg: AppColors.urgentSoft),
      MeetingStatus.scheduled => Pill.neutral(s.label),
    };

/// اختيار موعد جديد (التاريخ ثم الوقت)
Future<DateTime?> _pickNewTime(BuildContext context, DateTime current, {DateTime? suggested}) async {
  final now = DateTime.now();
  final base = suggested ?? current;
  final date = await showDatePicker(
    context: context,
    initialDate: base.isBefore(now) ? now : base,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365 * 2)),
    helpText: tr('الموعد الجديد'),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<void> _reschedule(BuildContext context, WidgetRef ref, Meeting m, DateTime to) async {
  if (await runAction(
    context,
    () => ref.read(repositoryProvider).rescheduleMeeting(m.id, to, m.durationMinutes),
    success: tr('أُجّل الاجتماع إلى {0} · {1}', [relativeDay(to), formatTime(to)]),
  )) {
    refreshAll(ref);
  }
}

/// المحضر ذكر تأجيل الاجتماع: نعرض نقله للموعد المذكور
Future<void> _offerPostpone(BuildContext context, WidgetRef ref, Meeting m, ParsedCommand p) async {
  DateTime? to;
  if (p.when != null) {
    final w = p.when!;
    to = p.hasTime ? w : DateTime(w.year, w.month, w.day, m.startAt.hour, m.startAt.minute);
  }
  final answer = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('تأجيل الاجتماع؟')),
      content: Text(to != null
          ? tr('ذكر المحضر تأجيل الاجتماع. هل تريد نقله إلى {0} الساعة {1}؟', [relativeDay(to), formatTime(to)])
          : tr('ذكر المحضر تأجيل الاجتماع دون موعد. هل تريد اختيار موعد جديد؟')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('لا'))),
        if (to != null) TextButton(onPressed: () => Navigator.pop(ctx, 'pick'), child: Text(tr('موعد آخر'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, to != null ? 'yes' : 'pick'), child: Text(to != null ? tr('نعم، أجّله') : tr('اختيار موعد'))),
      ],
    ),
  );
  if (answer == null || !context.mounted) return;
  if (answer == 'pick') {
    to = await _pickNewTime(context, m.startAt, suggested: to);
    if (to == null || !context.mounted) return;
  }
  await _reschedule(context, ref, m, to!);
}

/// قائمة حالة الاجتماع: تم، تأجيل، لم يُعقد
class MeetingActions extends ConsumerWidget {
  const MeetingActions({super.key, required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = meeting;
    final repo = ref.read(repositoryProvider);
    Future<void> setStatus(MeetingStatus s, String done) async {
      if (await runAction(context, () => repo.setMeetingStatus(m.id, s), success: done)) refreshAll(ref);
    }

    return PopupMenuButton<String>(
      tooltip: tr('حالة الاجتماع'),
      icon: Icon(Icons.more_vert, color: AppColors.muted),
      onSelected: (v) async {
        switch (v) {
          case 'done':
            await setStatus(MeetingStatus.done, tr('تم تسجيل انعقاد الاجتماع'));
          case 'postpone':
            final to = await _pickNewTime(context, m.startAt);
            if (to != null && context.mounted) await _reschedule(context, ref, m, to);
          case 'postponed':
            await setStatus(MeetingStatus.postponed, tr('سُجّل الاجتماع مؤجلًا دون موعد'));
          case 'cancelled':
            await setStatus(MeetingStatus.cancelled, tr('سُجّل أن الاجتماع لم يُعقد'));
          case 'scheduled':
            await setStatus(MeetingStatus.scheduled, tr('أُعيد الاجتماع إلى مجدول'));
          case 'minutes':
            await _openMinutes(context, m);
        }
      },
      itemBuilder: (_) => [
        if (m.status != MeetingStatus.done)
          PopupMenuItem(value: 'done', child: _item(Icons.check_circle_outline, tr('تم عقد الاجتماع'), AppColors.done)),
        PopupMenuItem(value: 'postpone', child: _item(Icons.event_repeat, tr('تأجيل لموعد جديد'), AppColors.waiting)),
        if (m.status != MeetingStatus.postponed)
          PopupMenuItem(value: 'postponed', child: _item(Icons.schedule, tr('مؤجل دون موعد'), AppColors.waiting)),
        if (m.status != MeetingStatus.cancelled)
          PopupMenuItem(value: 'cancelled', child: _item(Icons.cancel_outlined, tr('لم يُعقد / أُلغي'), AppColors.urgent)),
        if (m.status != MeetingStatus.scheduled)
          PopupMenuItem(value: 'scheduled', child: _item(Icons.undo, tr('إعادة إلى مجدول'), AppColors.muted)),
        PopupMenuItem(value: 'minutes', child: _item(Icons.edit_note, tr('المحضر'), AppColors.ink)),
      ],
    );
  }

  Widget _item(IconData icon, String label, Color color) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(label),
        ],
      );
}
