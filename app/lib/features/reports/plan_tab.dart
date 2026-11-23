import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_models.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/people_picker.dart';
import 'report_common.dart';

/// فترة جدول الأعمال
enum PlanPeriod { week, month, quarter }

(DateTime, DateTime) planRange(PlanPeriod p, [DateTime? now]) {
  final t = dateOnly(now ?? DateTime.now());
  switch (p) {
    case PlanPeriod.week:
      final start = t.subtract(Duration(days: t.weekday % 7)); // يبدأ الأحد
      return (start, start.add(const Duration(days: 6)));
    case PlanPeriod.quarter:
      final q = (t.month - 1) ~/ 3;
      return (DateTime(t.year, q * 3 + 1), DateTime(t.year, q * 3 + 4, 0));
    case PlanPeriod.month:
      return (DateTime(t.year, t.month), DateTime(t.year, t.month + 1, 0));
  }
}

Color planStatusColor(PlanStatus s) => switch (s) {
      PlanStatus.done => ChartColors.green,
      PlanStatus.on => ChartColors.blue,
      PlanStatus.risk => ChartColors.coral,
      PlanStatus.todo => ChartColors.slate,
    };

Pill planStatusPill(PlanStatus s) => switch (s) {
      PlanStatus.done => Pill.done(tr(s.label)),
      PlanStatus.on => Pill.info(tr(s.label)),
      PlanStatus.risk => Pill.urgent(tr(s.label)),
      PlanStatus.todo => Pill.neutral(tr(s.label)),
    };

Pill decisionPill(DecisionState s) => switch (s) {
      DecisionState.done => Pill.done(tr(s.label)),
      DecisionState.on => Pill.info(tr(s.label)),
      DecisionState.late => Pill.urgent(tr(s.label)),
    };

/// نص المؤشر المرتبط: «📊 المحصّل 214.5K من 250K»
String? planKpiText(PlanItem i) {
  if (i.kpi == null) return null;
  final g = GoalMetric.all.where((g) => g.key == i.kpi).firstOrNull;
  if (g == null) return null;
  String f(num? v) => v == null ? '—' : g.percent ? fmtPct(v) : g.money ? moneyCompact(v) : fmtNum(v);
  if (i.kpiTarget == null) return tr('{0}: {1}', [tr(g.labelAr), f(i.kpiValue)]);
  return tr('{0}: {1} من {2}', [tr(g.labelAr), f(i.kpiValue), f(i.kpiTarget)]);
}

Widget peopleAvatars(List<PlanPerson> people, {double size = 22}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < people.length && i < 4; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 2),
            child: Avatar(people[i].name.isEmpty ? '؟' : people[i].name.characters.first, size: size, imageUrl: people[i].avatarUrl),
          ),
      ],
    );

/// تبويب «جدول الأعمال» في التقارير: خطة عمل المكتب
class PlanTab extends ConsumerStatefulWidget {
  const PlanTab({super.key});

  @override
  ConsumerState<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends ConsumerState<PlanTab> {
  PlanPeriod _period = PlanPeriod.month;

  @override
  Widget build(BuildContext context) {
    final range = planRange(_period);
    final data = ref.watch(workPlanProvider(range));
    final labels = {PlanPeriod.week: tr('هذا الأسبوع'), PlanPeriod.month: tr('هذا الشهر'), PlanPeriod.quarter: tr('الربع')};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PlanPeriod>(
          showSelectedIcon: false,
          segments: [for (final p in PlanPeriod.values) ButtonSegment(value: p, label: Text(labels[p]!))],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
        const SizedBox(height: 6),
        Text(tr('{0} – {1}', [formatShortDate(range.$1), formatShortDate(range.$2)]),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 12),
        AsyncBody<WorkPlan>(
          value: data,
          onRetry: () => ref.invalidate(workPlanProvider(range)),
          builder: (p) => _PlanBody(plan: p, range: range),
        ),
      ],
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.plan, required this.range});
  final WorkPlan plan;
  final (DateTime, DateTime) range;

  void _refresh(WidgetRef ref) => ref.invalidate(workPlanProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).valueOrNull;
    final items = plan.items;
    final decisions = plan.decisions;
    final topics = plan.topics;
    final inits = plan.initiatives;
    final doneN = items.where((i) => i.status == PlanStatus.done).length;
    final riskN = items.where((i) => i.status == PlanStatus.risk || i.overdue).length;
    final decDone = decisions.where((d) => d.state == DecisionState.done).length;
    final repo = ref.read(sectionRepoProvider);

    Widget box(String v, String l, {Color? bg, Color? fg}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: bg ?? AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: bg == null ? AppColors.line : bg),
            ),
            child: Column(
              children: [
                Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
                Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: fg ?? AppColors.muted)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            box('${items.length}', tr('بنود الخطة')),
            const SizedBox(width: 6),
            box('$doneN', tr('منجز'), bg: AppColors.doneSoft, fg: AppColors.done),
            const SizedBox(width: 6),
            box('$riskN', tr('متعثر'), bg: riskN > 0 ? AppColors.urgentSoft : null, fg: riskN > 0 ? AppColors.urgent : null),
            const SizedBox(width: 6),
            box(decisions.isEmpty ? '—' : fmtPct(decDone * 100 / decisions.length), tr('قرارات منفذة')),
          ],
        ),
        const SizedBox(height: 14),

        // ---------- خطة العمل ----------
        ReportCard(
          title: tr('خطة العمل'),
          subtitle: items.isEmpty ? null : tr('متوسط الإنجاز {0}', [fmtPct(plan.planProgress)]),
          trailing: plan.canEdit
              ? TextButton.icon(
                  onPressed: () async {
                    if (await editPlanItem(context, ref) && context.mounted) _refresh(ref);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('بند')),
                )
              : null,
          child: items.isEmpty
              ? mutedText(plan.canEdit ? tr('أضف أول بند في خطة المكتب') : tr('لا توجد بنود في هذه الفترة'))
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: AppColors.divider),
                      _PlanItemTile(
                        item: items[i],
                        canEdit: plan.canEdit,
                        isOwner: items[i].owners.any((o) => o.id == me?.id),
                        onChanged: () => _refresh(ref),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // ---------- القرارات ----------
        ReportCard(
          title: tr('متابعة القرارات والتكليفات'),
          subtitle: tr('من محاضر الاجتماعات · آخر ٦٠ يومًا'),
          trailing: decisions.isEmpty ? null : Pill.done(tr('{0} من {1} نُفّذت', [decDone, decisions.length])),
          child: decisions.isEmpty
              ? mutedText(tr('لا توجد قرارات — تُضاف من محضر الاجتماع'))
              : Column(
                  children: [
                    for (final d in decisions)
                      ReportRowTile(
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (d.state) {
                              DecisionState.done => ChartColors.green,
                              DecisionState.on => ChartColors.blue,
                              DecisionState.late => ChartColors.coral,
                            },
                          ),
                        ),
                        title: d.text,
                        subtitle: [
                          if (d.meeting != null) d.meeting!,
                          if (d.meetingDate != null) formatShortDate(d.meetingDate!),
                          if (d.owner != null) d.owner!,
                          if (d.dueDate != null) tr('الموعد {0}', [formatShortDate(d.dueDate!)]),
                        ].join(' · '),
                        trailing: decisionPill(d.state),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // ---------- للنقاش ----------
        ReportCard(
          title: tr('للنقاش في الاجتماع القادم'),
          trailing: topics.isEmpty
              ? null
              : Text(tr('{0} دقيقة', [topics.fold<int>(0, (a, t) => a + (t.minutes ?? 0))]),
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (topics.isEmpty) mutedText(tr('لا توجد مواضيع بعد')),
              for (var i = 0; i < topics.length; i++)
                ReportRowTile(
                  leading: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(8)),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  title: topics[i].title,
                  subtitle: [
                    if (topics[i].proposer != null) tr('يطرحه {0}', [topics[i].proposer]),
                    if (topics[i].minutes != null) tr('{0} دقيقة', [topics[i].minutes]),
                    if (topics[i].status == 'postponed') tr('مؤجل من اجتماع سابق'),
                  ].join(' · '),
                  trailing: (plan.canEdit || topics[i].proposedBy == me?.id)
                      ? PopupMenuButton<String>(
                          tooltip: tr('خيارات'),
                          onSelected: (v) async {
                            final ok = await runAction(
                              context,
                              () => v == 'delete' ? repo.deleteTopic(topics[i].id) : repo.setTopicStatus(topics[i].id, v),
                            );
                            if (ok) _refresh(ref);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'discussed', child: Text(tr('نوقش ✓'))),
                            PopupMenuItem(value: 'postponed', child: Text(tr('تأجيل للاجتماع التالي'))),
                            PopupMenuItem(value: 'delete', child: Text(tr('حذف'), style: TextStyle(color: AppColors.danger))),
                          ],
                        )
                      : null,
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await addTopic(context, ref) && context.mounted) _refresh(ref);
                },
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: Text(tr('اقترح موضوعًا')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---------- المشاريع والأفكار ----------
        ReportCard(
          title: tr('المشاريع والأفكار'),
          trailing: TextButton(onPressed: () => context.push('/more/reports/initiatives'), child: Text(tr('اللوحة'))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in inits.where((n) => n.stage == InitiativeStage.active || n.stage == InitiativeStage.waiting).take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                          Text(tr(n.stage.label), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          peopleAvatars(n.owners, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: ProgressBar(ratio: n.progress / 100, color: ChartColors.blue, trackColor: AppColors.divider)),
                          const SizedBox(width: 8),
                          Text(fmtPct(n.progress), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
              if (!inits.any((n) => n.stage == InitiativeStage.active || n.stage == InitiativeStage.waiting))
                mutedText(tr('لا توجد مشاريع جارية')),
              const SizedBox(height: 6),
              Material(
                color: const Color(0xFFFDF4DD),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/more/reports/initiatives'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('💡 {0} أفكار بانتظار المناقشة', [inits.where((n) => n.stage == InitiativeStage.idea).length]),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8A5A00)),
                          ),
                        ),
                        Icon(AppIcons.forward, size: 18, color: const Color(0xFF8A5A00)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => context.push('/tv'),
          icon: const Icon(Icons.tv_outlined),
          label: Text(tr('عرض على شاشة الاجتماعات')),
        ),
      ],
    );
  }
}

class _PlanItemTile extends ConsumerWidget {
  const _PlanItemTile({required this.item, required this.canEdit, required this.isOwner, required this.onChanged});
  final PlanItem item;
  final bool canEdit;
  final bool isOwner;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = item;
    final kpi = planKpiText(i);
    final done = i.status == PlanStatus.done;
    return InkWell(
      onTap: canEdit
          ? () async {
              if (await editPlanItem(context, ref, item: i)) onChanged();
            }
          : isOwner
              ? () async {
                  if (await updatePlanProgressSheet(context, ref, i)) onChanged();
                }
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    i.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: done ? AppColors.muted : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                planStatusPill(i.status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (i.owners.isNotEmpty) ...[peopleAvatars(i.owners), const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    [
                      if (i.owners.isNotEmpty) i.owners.map((o) => o.name).join(tr('، ')),
                      if (i.dueDate != null) '🗓 ${formatShortDate(i.dueDate!)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: i.overdue ? AppColors.urgent : AppColors.muted),
                  ),
                ),
              ],
            ),
            if (kpi != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFF2F7FC), borderRadius: BorderRadius.circular(8)),
                  child: Text('📊 $kpi', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2C5F93))),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ProgressBar(
                    ratio: i.progress / 100,
                    color: i.status == PlanStatus.risk ? ChartColors.coral : ChartColors.green,
                    trackColor: AppColors.divider,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 34, child: Text(fmtPct(i.progress), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// النماذج
// =====================================================================
/// إضافة/تعديل بند — يعيد true عند الحفظ أو الحذف
Future<bool> editPlanItem(BuildContext context, WidgetRef ref, {PlanItem? item}) async {
  final r = await showFormSheet<bool>(context, _PlanItemSheet(item: item));
  return r == true;
}

class _PlanItemSheet extends ConsumerStatefulWidget {
  const _PlanItemSheet({this.item});
  final PlanItem? item;

  @override
  ConsumerState<_PlanItemSheet> createState() => _PlanItemSheetState();
}

class _PlanItemSheetState extends ConsumerState<_PlanItemSheet> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  late final _target = TextEditingController(text: widget.item?.kpiTarget == null ? '' : fmtNum(widget.item!.kpiTarget!).replaceAll(',', ''));
  late PlanStatus _status = widget.item?.status ?? PlanStatus.todo;
  late double _progress = (widget.item?.progress ?? 0).toDouble();
  late DateTime? _due = widget.item?.dueDate;
  late String? _kpi = widget.item?.kpi;
  late List<String> _owners = [for (final o in widget.item?.owners ?? const <PlanPerson>[]) o.id];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, tr('اكتب عنوان البند'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(sectionRepoProvider).savePlanItem(
            id: widget.item?.id,
            title: title,
            notes: _notes.text,
            status: _status,
            progress: _progress.round(),
            dueDate: _due,
            kpi: _kpi,
            kpiTarget: num.tryParse(_target.text.replaceAll(',', '').trim()),
            ownerIds: _owners,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context,
        title: tr('حذف البند؟'), message: widget.item!.title, confirmLabel: tr('حذف'), destructive: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).deletePlanItem(widget.item!.id)) && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider).valueOrNull ?? const <Profile>[];
    final kpis = {for (final g in GoalMetric.all) g.key: tr(g.labelAr)};
    return SheetBody(
      title: widget.item == null ? tr('بند جديد في الخطة') : tr('تعديل البند'),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _title, autofocus: widget.item == null, decoration: InputDecoration(labelText: tr('البند'))),
        const SizedBox(height: 12),
        FormCard(children: [
          FormRow(
            label: tr('المسؤولون'),
            value: peopleNames(team, _owners, empty: tr('غير محدد')),
            onTap: () async {
              final v = await pickPeople(context, team: team, selected: _owners, title: tr('المسؤولون عن البند'),
                  hint: tr('يمكنك اختيار أكثر من شخص'));
              if (v != null) setState(() => _owners = v);
            },
          ),
          FormRow(
            label: tr('الموعد'),
            value: _due == null ? tr('بدون موعد') : formatDay(_due!),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _due ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (d != null) setState(() => _due = d);
            },
          ),
          FormDropdown<PlanStatus>(
            label: tr('الحالة'),
            value: _status,
            allowEmpty: false,
            items: {for (final s in PlanStatus.values) s: tr(s.label)},
            onChanged: (v) => setState(() {
              _status = v ?? _status;
              if (_status == PlanStatus.done) _progress = 100;
            }),
          ),
          FormDropdown<String>(
            label: tr('مؤشر من التقارير'),
            value: _kpi,
            emptyLabel: tr('بدون'),
            items: kpis,
            onChanged: (v) => setState(() => _kpi = v),
          ),
        ]),
        if (_kpi != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('المستهدف (اختياري)')),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Text(tr('التقدم'), style: const TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
              child: Slider(
                value: _progress,
                min: 0,
                max: 100,
                divisions: 20,
                label: fmtPct(_progress),
                onChanged: (v) => setState(() {
                  _progress = v;
                  if (v >= 100) _status = PlanStatus.done;
                  if (v < 100 && _status == PlanStatus.done) _status = PlanStatus.on;
                }),
              ),
            ),
            SizedBox(width: 40, child: Text(fmtPct(_progress), style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
        TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('ملاحظات'))),
        if (widget.item != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.danger),
            label: Text(tr('حذف البند'), style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ],
    );
  }
}

/// تحديث التقدم للمسؤول عن البند (بدون صلاحية الإدارة)
Future<bool> updatePlanProgressSheet(BuildContext context, WidgetRef ref, PlanItem item) async {
  var progress = item.progress.toDouble();
  var status = item.status;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in PlanStatus.values)
                    ChoiceChip(
                      label: Text(tr(s.label)),
                      selected: status == s,
                      showCheckmark: false,
                      onSelected: (_) => set(() {
                        status = s;
                        if (s == PlanStatus.done) progress = 100;
                      }),
                    ),
                ],
              ),
              Slider(
                value: progress,
                min: 0,
                max: 100,
                divisions: 20,
                label: fmtPct(progress),
                onChanged: (v) => set(() {
                  progress = v;
                  if (v >= 100) status = PlanStatus.done;
                  if (v < 100 && status == PlanStatus.done) status = PlanStatus.on;
                }),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('حفظ · {0}', [fmtPct(progress)])),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return runAction(context, () => ref.read(sectionRepoProvider).updatePlanProgress(item.id, status: status, progress: progress.round()));
}

/// اقتراح موضوع للنقاش
Future<bool> addTopic(BuildContext context, WidgetRef ref) async {
  final title = TextEditingController();
  int? minutes = 10;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('موضوع للنقاش')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: title, autofocus: true, decoration: InputDecoration(labelText: tr('الموضوع'))),
            const SizedBox(height: 12),
            Text(tr('المدة المقترحة'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            Wrap(
              spacing: 6,
              children: [
                for (final m in const [5, 10, 15, 30])
                  ChoiceChip(
                    label: Text(tr('{0} د', [m])),
                    selected: minutes == m,
                    showCheckmark: false,
                    onSelected: (_) => set(() => minutes = m),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('إضافة'))),
        ],
      ),
    ),
  );
  final t = title.text.trim();
  title.dispose();
  if (ok != true || t.isEmpty || !context.mounted) return false;
  return runAction(context, () => ref.read(sectionRepoProvider).addTopic(t, minutes), success: tr('أُضيف الموضوع'));
}
