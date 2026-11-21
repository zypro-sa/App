import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/display_toggles.dart';
import '../quick_add/quick_add_sheet.dart';
import '../../core/i18n.dart';

/// ١ · لوحة اليوم
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeSummaryProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => refreshSections(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              _Header(profile: profile),
              const SizedBox(height: 16),
              AsyncBody<HomeSummary>(
                value: summary,
                onRetry: () => ref.invalidate(homeSummaryProvider),
                builder: (s) => _Body(summary: s),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Image.asset(AppAssets.wordmark, height: 26, semanticLabel: 'Zypro'),
            const Spacer(),
            IconButton(
              tooltip: tr('إضافة بالصوت'),
              onPressed: () => showQuickAdd(context, voice: true),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.accentText,
                fixedSize: const Size(38, 38),
                minimumSize: const Size(38, 38),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              iconSize: 20,
              icon: const Icon(Icons.mic_none),
            ),
            const SizedBox(width: 6),
            const DisplayToggles(),
          ],
        ),
        const SizedBox(height: 10),
        _greetingRow(context),
      ],
    );
  }

  Widget _greetingRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatDay(DateTime.now()), style: TextStyle(fontSize: 13, color: AppColors.muted)),
              Text(
                tr('{0}، {1}', [greeting(), profile?.name ?? '']),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: tr('الإشعارات'),
          onPressed: () => context.go('/home/notifications'),
          icon: Consumer(
            builder: (_, ref, __) {
              final unread = ref.watch(unreadNotificationsProvider);
              return Badge(
                isLabelVisible: unread > 0,
                backgroundColor: AppColors.accent,
                textColor: AppColors.onAccent,
                label: Text(unread > 9 ? '+9' : '$unread'),
                child: const Icon(Icons.notifications_none),
              );
            },
          ),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            fixedSize: const Size(44, 44),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => context.go('/more/account'),
          child: Avatar(profile?.initial ?? tr('؟'), size: 44, fg: AppColors.accent, bg: AppColors.hero, radius: 14, imageUrl: profile?.avatarUrl),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary});
  final HomeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Stat(value: s.meetingsToday, label: tr('اجتماعات اليوم'), onTap: () => context.go('/meetings'))),
            const SizedBox(width: 10),
            Expanded(child: _Stat(value: s.urgentTasks, label: tr('مهام عاجلة'), onTap: () => context.go('/tasks'))),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                value: s.overdueRequests,
                label: tr('طلبات متأخرة'),
                alert: s.overdueRequests > 0,
                onTap: () => context.go('/requests'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (s.nextMeeting != null) ...[
          _NextMeeting(meeting: s.nextMeeting!),
          const SizedBox(height: 16),
        ],
        SectionHeader(tr('مهام اليوم'), onSeeAll: () => context.go('/tasks')),
        if (s.todayTasks.isEmpty)
          CardBox(child: Text(tr('لا توجد مهام لليوم'), style: TextStyle(color: AppColors.muted)))
        else
          CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: [
                for (var i = 0; i < s.todayTasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  _HomeTaskRow(task: s.todayTasks[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        SectionHeader(tr('متابعات تنتظرك'), onSeeAll: () => context.go('/more/followups')),
        if (s.followups.isEmpty)
          CardBox(child: Text(tr('لا توجد متابعات مفتوحة'), style: TextStyle(color: AppColors.muted)))
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < s.followups.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _FollowupMini(f: s.followups[i])),
              ],
            ],
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.onTap, this.alert = false});

  final int value;
  final String label;
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = alert ? AppColors.urgent : AppColors.ink;
    return CardBox(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.all(12),
      color: alert ? AppColors.urgentSoft : AppColors.surface,
      borderColor: alert ? AppColors.urgentBorder : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: fg)),
          Text(label, style: TextStyle(fontSize: 12, color: alert ? AppColors.urgent : AppColors.muted)),
        ],
      ),
    );
  }
}

class _NextMeeting extends StatelessWidget {
  const _NextMeeting({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    final isToday = dateOnly(m.startAt) == dateOnly(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tr('التالي · {0}', [isToday ? timeUntil(m.startAt) : relativeDay(m.startAt)]),
                  style: TextStyle(color: AppColors.onAccent, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              Text(
                '${formatTime(m.startAt)} – ${formatTime(m.endAt)}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(m.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          Text(
            [m.clientName, m.location ?? m.type.label].whereType<String>().join(' · '),
            style: const TextStyle(color: Color(0xFFC9CBD3), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF34343F)),
                  onPressed: () => context.go('/meetings'),
                  child: Text(tr('جدول الأعمال')),
                ),
              ),
              if (m.clientId != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => context.go('/more/clients/${m.clientId}'),
                    child: Text(tr('ملف العميل')),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTaskRow extends ConsumerWidget {
  const _HomeTaskRow({required this.task});
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    Widget? trailing;
    if (!t.isDone && (t.priority == Priority.urgent || t.isOverdue)) {
      trailing = Pill.urgent(t.isOverdue ? tr('متأخرة') : tr('عاجل'));
    } else if (t.dueAt != null && !t.isDone) {
      trailing = Text(formatTime(t.dueAt!), style: TextStyle(fontSize: 12, color: AppColors.muted));
    }
    return Row(
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
          child: Text(
            t.title,
            style: TextStyle(
              fontSize: 14,
              color: t.isDone ? AppColors.muted : AppColors.ink,
              decoration: t.isDone ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (trailing != null) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: trailing),
      ],
    );
  }
}

class _FollowupMini extends StatelessWidget {
  const _FollowupMini({required this.f});
  final FollowUp f;

  @override
  Widget build(BuildContext context) {
    final promised = f.direction == FollowupDirection.promised;
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.all(12),
      onTap: () => context.go('/more/followups'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${promised ? tr('وعدت بالرد') : tr('بانتظار رد')} · ${relativeDay(f.dueAt)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: promised ? AppColors.waiting : AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(f.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
