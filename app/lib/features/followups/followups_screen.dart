import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

/// ٦ · المتابعات
class FollowupsScreen extends ConsumerStatefulWidget {
  const FollowupsScreen({super.key});

  @override
  ConsumerState<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends ConsumerState<FollowupsScreen> {
  FollowupDirection _direction = FollowupDirection.promised;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(followupsProvider(_direction));
    final promised = ref.watch(followupsProvider(FollowupDirection.promised)).valueOrNull?.length;
    final waiting = ref.watch(followupsProvider(FollowupDirection.waiting)).valueOrNull?.length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المتابعات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text('حتى لا تضيع أي فرصة أو وعد',
                style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SegmentedButton<FollowupDirection>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: FollowupDirection.promised,
                  label: Text('وعدتُ بها${promised != null ? ' $promised' : ''}'),
                ),
                ButtonSegment(
                  value: FollowupDirection.waiting,
                  label: Text('أنتظرها${waiting != null ? ' $waiting' : ''}'),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 14),
            AsyncBody<List<FollowUp>>(
              value: items,
              onRetry: () => ref.invalidate(followupsProvider(_direction)),
              builder: (list) => list.isEmpty
                  ? const EmptyState('لا توجد متابعات مفتوحة', icon: Icons.task_alt)
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          _FollowupCard(f: list[i], expanded: i == 0),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowupCard extends ConsumerWidget {
  const _FollowupCard({required this.f, required this.expanded});

  final FollowUp f;
  final bool expanded;

  Pill _duePill() {
    final today = dateOnly(DateTime.now());
    final due = dateOnly(f.dueAt);
    if (!due.isAfter(today)) {
      return Pill.urgent(due == today ? 'مستحقة اليوم' : 'متأخرة · ${relativeDay(f.dueAt)}');
    }
    if (due.difference(today).inDays == 1) return Pill.waiting('غدًا');
    return Pill.neutral(relativeDay(f.dueAt));
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      refreshAll(ref);
      if (context.mounted) showSnack(context, done);
    } catch (e) {
      if (context.mounted) showSnack(context, 'تعذّر التنفيذ: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final pill = _duePill();
    final urgent = pill.bg == AppColors.urgentSoft;

    return CardBox(
      borderColor: urgent ? AppColors.urgentBorder : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              pill,
              const Spacer(),
              if (f.counterpart != null)
                Text(f.counterpart!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              if (f.isAuto) ...[
                const SizedBox(width: 6),
                Pill.info('تلقائية'),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(f.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _run(context, ref, () => repo.completeFollowup(f.id), 'تمت المتابعة'),
                  child: const Text('تم'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(context, ref,
                      () => repo.snoozeFollowup(f.id, const Duration(days: 1)), 'أُجّلت إلى الغد'),
                  child: const Text('تأجيل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(context, ref, () => repo.followupToTask(f), 'تحوّلت إلى مهمة'),
                  child: const Text('إلى مهمة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
