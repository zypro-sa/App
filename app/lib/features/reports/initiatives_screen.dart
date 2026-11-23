import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/people_picker.dart';
import 'plan_tab.dart';
import 'report_common.dart';

Color _stageColor(InitiativeStage s) => switch (s) {
      InitiativeStage.idea => const Color(0xFFE8A33D),
      InitiativeStage.active => ChartColors.blue,
      InitiativeStage.waiting => const Color(0xFF8E7CC3),
      InitiativeStage.done => ChartColors.green,
    };

/// لوحة المشاريع والأفكار (تطوير المكتب)
class InitiativesScreen extends ConsumerStatefulWidget {
  const InitiativesScreen({super.key});

  @override
  ConsumerState<InitiativesScreen> createState() => _InitiativesScreenState();
}

class _InitiativesScreenState extends ConsumerState<InitiativesScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final range = planRange(PlanPeriod.month);
    final data = ref.watch(workPlanProvider(range));
    return Scaffold(
      appBar: sectionAppBar(
        tr('المشاريع والأفكار'),
        subtitle: tr('تطوير المكتب'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(
              onPressed: () async {
                if (await editInitiative(context, ref)) ref.invalidate(workPlanProvider);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('جديد')),
            ),
          ),
        ],
      ),
      body: AsyncBody<WorkPlan>(
        value: data,
        onRetry: () => ref.invalidate(workPlanProvider(range)),
        builder: (plan) {
          final all = plan.initiatives.where((n) => _category == null || n.category == _category).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(workPlanProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(tr('الكل {0}', [plan.initiatives.length])),
                        selected: _category == null,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      for (final e in initiativeCategories.entries) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(tr(e.value)),
                          selected: _category == e.key,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _category = e.key),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in InitiativeStage.values)
                        _Column(stage: s, items: all.where((n) => n.stage == s).toList(), canEdit: plan.canEdit),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Column extends ConsumerWidget {
  const _Column({required this.stage, required this.items, required this.canEdit});
  final InitiativeStage stage;
  final List<Initiative> items;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = _stageColor(stage);
    return Container(
      width: 270,
      margin: const EdgeInsetsDirectional.only(end: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(20)),
      child: DragTarget<Initiative>(
        onWillAcceptWithDetails: (d) => d.data.stage != stage,
        onAcceptWithDetails: (d) async {
          if (await runAction(context, () => ref.read(sectionRepoProvider).moveInitiative(d.data.id, stage))) {
            ref.invalidate(workPlanProvider);
          }
        },
        builder: (context, cand, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(tr(stage.label), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                Text('${items.length}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 10),
            if (cand.isNotEmpty)
              Container(
                height: 60,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: c, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(tr('أفلت هنا'), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              ),
            for (final n in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LongPressDraggable<Initiative>(
                  data: n,
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(width: 250, child: Opacity(opacity: .9, child: _Card(n: n))),
                  ),
                  childWhenDragging: Opacity(opacity: .35, child: _Card(n: n)),
                  child: _Card(n: n),
                ),
              ),
            if (items.isEmpty && cand.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('لا يوجد'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.faint)),
              ),
            if (stage == InitiativeStage.idea)
              OutlinedButton.icon(
                onPressed: () async {
                  if (await editInitiative(context, ref)) ref.invalidate(workPlanProvider);
                },
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(tr('أضف فكرة')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.n});
  final Initiative n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sectionRepoProvider);
    return CardBox(
      padding: const EdgeInsets.all(12),
      onTap: () async {
        if (await editInitiative(context, ref, item: n)) ref.invalidate(workPlanProvider);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Pill.neutral(tr(initiativeCategories[n.category] ?? n.category)),
              const Spacer(),
              if (n.stage == InitiativeStage.idea)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    if (await runAction(context, () => repo.toggleVote(n.id, !n.voted))) ref.invalidate(workPlanProvider);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('👍 ${n.votes}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: n.voted ? AppColors.accentText : AppColors.muted)),
                  ),
                )
              else
                Text(fmtPct(n.progress), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4)),
          if (n.stage != InitiativeStage.idea) ...[
            const SizedBox(height: 8),
            ProgressBar(ratio: n.progress / 100, color: _stageColor(n.stage), trackColor: AppColors.divider),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              peopleAvatars(n.owners, size: 20),
              const Spacer(),
              Text(
                n.stage == InitiativeStage.idea
                    ? (n.creator == null ? '' : tr('اقترحها {0}', [n.creator]))
                    : (n.dueDate == null ? '' : '🗓 ${formatShortDate(n.dueDate!)}'),
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// إضافة/تعديل مشروع أو فكرة
Future<bool> editInitiative(BuildContext context, WidgetRef ref, {Initiative? item}) async {
  final r = await showFormSheet<bool>(context, _InitiativeSheet(item: item));
  return r == true;
}

class _InitiativeSheet extends ConsumerStatefulWidget {
  const _InitiativeSheet({this.item});
  final Initiative? item;

  @override
  ConsumerState<_InitiativeSheet> createState() => _InitiativeSheetState();
}

class _InitiativeSheetState extends ConsumerState<_InitiativeSheet> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late String _category = widget.item?.category ?? 'dev';
  late InitiativeStage _stage = widget.item?.stage ?? InitiativeStage.idea;
  late double _progress = (widget.item?.progress ?? 0).toDouble();
  late DateTime? _due = widget.item?.dueDate;
  late List<String> _owners = [for (final o in widget.item?.owners ?? const <PlanPerson>[]) o.id];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      showSnack(context, tr('اكتب العنوان'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(sectionRepoProvider).saveInitiative(
            id: widget.item?.id,
            title: t,
            description: _desc.text,
            category: _category,
            stage: _stage,
            progress: _progress.round(),
            dueDate: _due,
            ownerIds: _owners,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context, title: tr('حذف؟'), message: widget.item!.title, confirmLabel: tr('حذف'), destructive: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).deleteInitiative(widget.item!.id)) && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider).valueOrNull ?? const <Profile>[];
    return SheetBody(
      title: widget.item == null ? tr('مشروع أو فكرة جديدة') : tr('تعديل'),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _title, autofocus: widget.item == null, decoration: InputDecoration(labelText: tr('العنوان'))),
        const SizedBox(height: 12),
        TextField(controller: _desc, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('الوصف'))),
        const SizedBox(height: 12),
        FormCard(children: [
          FormDropdown<String>(
            label: tr('التصنيف'),
            value: _category,
            allowEmpty: false,
            items: {for (final e in initiativeCategories.entries) e.key: tr(e.value)},
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          FormDropdown<InitiativeStage>(
            label: tr('المرحلة'),
            value: _stage,
            allowEmpty: false,
            items: {for (final s in InitiativeStage.values) s: tr(s.label)},
            onChanged: (v) => setState(() => _stage = v ?? _stage),
          ),
          FormRow(
            label: tr('المسؤولون'),
            value: peopleNames(team, _owners, empty: tr('غير محدد')),
            onTap: () async {
              final v = await pickPeople(context, team: team, selected: _owners, title: tr('المسؤولون'));
              if (v != null) setState(() => _owners = v);
            },
          ),
          FormRow(
            label: tr('الموعد'),
            value: _due == null ? tr('بدون موعد') : formatDay(_due!),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                  context: context, initialDate: _due ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
              if (d != null) setState(() => _due = d);
            },
          ),
        ]),
        if (_stage != InitiativeStage.idea) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(tr('التقدم'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(
                  value: _stage == InitiativeStage.done ? 100 : _progress,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: _stage == InitiativeStage.done ? null : (v) => setState(() => _progress = v),
                ),
              ),
              SizedBox(width: 40, child: Text(fmtPct(_stage == InitiativeStage.done ? 100 : _progress))),
            ],
          ),
        ],
        if (widget.item != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.danger),
            label: Text(tr('حذف'), style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ],
    );
  }
}
