import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

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
            const Text('الاجتماعات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
              '${DateFormat('MMMM y', 'ar').format(_day)}'
              '${count != null ? ' · $count ${isToday ? 'اجتماعات اليوم' : 'اجتماعات'}' : ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'اختيار تاريخ', onPressed: _pickMonthDay, icon: const Icon(Icons.calendar_month_outlined)),
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
                  return const EmptyState('لا توجد اجتماعات في هذا اليوم', icon: Icons.event_available_outlined);
                }
                final now = DateTime.now();
                final nextIndex = list.indexWhere((m) => m.endAt.isAfter(now));
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
        color: selected ? AppColors.primary : Colors.transparent,
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
                    style: TextStyle(fontSize: 11, color: selected ? Colors.white : AppColors.muted)),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : (weekend ? const Color(0xFF9AA2AE) : AppColors.ink),
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
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.subtle)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: highlighted ? _MeetingCardExpanded(meeting) : _MeetingCardCompact(meeting)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            [
              '${m.durationMinutes} دقيقة',
              m.type.label,
              if (m.clientName != null) m.clientName!,
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill.info(started ? 'جارٍ الآن' : timeUntil(m.startAt)),
              const Spacer(),
              Text('${m.durationMinutes} دقيقة · ${m.type.label}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (m.clientName != null)
            Text(m.clientName!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          if (m.agenda.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('جدول الأعمال',
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
                const Icon(Icons.group_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('${m.attendeeCount} حضور', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openMinutes(context, m),
                  child: const Text('كتابة المحضر'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showSnack(context, 'تحويل القرارات لمهام: في المرحلة القادمة'),
                  child: const Text('تحويل القرارات لمهام', textAlign: TextAlign.center),
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
    backgroundColor: Colors.white,
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveMinutes(widget.meeting.id, _controller.text.trim());
      refreshAll(ref);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('تم حفظ المحضر')));
      }
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّر الحفظ: $e');
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
          Text('محضر: ${widget.meeting.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(hintText: 'ما الذي نوقش؟ وما القرارات؟'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ المحضر')),
        ],
      ),
    );
  }
}
