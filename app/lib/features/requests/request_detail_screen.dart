import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// تفاصيل الطلب: البيانات، شروط الدفع، والخطوات (تمت / لم تتم)
class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(requestDetailProvider(requestId));
    final me = ref.watch(profileProvider).valueOrNull;
    final labels = {
      for (final l in ref.watch(statusLabelsProvider(ConfigEntity.request)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };
    final d = detail.valueOrNull;
    final canEdit = (me?.can(Permissions.requestsManage) ?? false) || (d != null && d.assigneeId == me?.id);
    final canDelete = me?.can(Permissions.requestsDelete) ?? false;
    final repo = ref.read(sectionRepoProvider);

    Future<void> update(Map<String, dynamic> changes, {String? success}) async {
      if (await runAction(context, () => repo.updateRequest(requestId, changes), success: success)) {
        refreshSections(ref);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('تفاصيل الطلب')),
        centerTitle: true,
        actions: [
          if (d != null && (canEdit || canDelete))
            PopupMenuButton<String>(
              tooltip: tr('خيارات'),
              onSelected: (v) async {
                if (v == 'rename') {
                  final t = await promptText(context, tr('عنوان الطلب'), initial: d.item.title);
                  if (t != null) await update({'title': t});
                } else if (v == 'delete') {
                  final ok = await confirmAction(context,
                      title: tr('حذف الطلب #{0}؟', [d.item.number]),
                      message: tr('ينتقل إلى سلة المحذوفات ويمكن استرجاعه خلال ٣٠ يومًا.'),
                      confirmLabel: tr('حذف'),
                      destructive: true);
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.softDelete('requests', [requestId]), success: tr('نُقل إلى السلة'))) {
                    refreshSections(ref);
                    if (context.mounted) context.go('/requests');
                  }
                } else {
                  await update({'status': v}, success: tr('تم تغيير الحالة'));
                }
              },
              itemBuilder: (_) => [
                if (canEdit) ...[
                  PopupMenuItem(value: 'rename', child: Text(tr('تعديل العنوان'))),
                  const PopupMenuDivider(),
                  for (final s in RequestStatus.values)
                    if (s != d.item.status)
                      PopupMenuItem(value: s.db, child: Text(tr('تغيير الحالة: {0}', [labels[s.db]?.label ?? s.label]))),
                ],
                if (canDelete) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text(tr('حذف الطلب'), style: TextStyle(color: AppColors.urgent))),
                ],
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(requestDetailProvider(requestId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<RequestDetail>(
              value: detail,
              onRetry: () => ref.invalidate(requestDetailProvider(requestId)),
              builder: (d) => _Body(d: d, labels: labels, canEdit: canEdit, update: update),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.d, required this.labels, required this.canEdit, required this.update});

  final RequestDetail d;
  final Map<String, StatusLabel> labels;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>, {String? success}) update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = d.item;
    final cfg = ref.watch(fieldConfigProvider(ConfigEntity.request)).valueOrNull ?? FieldConfig(const []);
    final sl = labels[r.status.db];
    final progressColor = r.isOverdue ? AppColors.danger : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          radius: 20,
          padding: const EdgeInsets.all(16),
          borderColor: r.isOverdue ? AppColors.urgentBorder : AppColors.line,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: d.clientId == null ? null : () => context.go('/more/clients/${d.clientId}'),
                      child: Text(
                        '#${r.number}${r.clientName != null ? ' · ${r.clientName}' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: d.clientId == null ? AppColors.muted : AppColors.accentText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  (r.isOverdue || sl == null) ? Pill.forRequest(r) : statusPill(sl.label, sl.color),
                ],
              ),
              const SizedBox(height: 8),
              Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: ProgressLine(r.progress, height: 10, color: progressColor)),
                  const SizedBox(width: 10),
                  Text(tr('{0}٪', [r.progress]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              if (d.steps.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tr('{0} من {1} خطوات تمت', [d.doneSteps, d.steps.length]),
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormCard(children: [
          if (cfg.isVisible('service_type'))
            canEdit
                ? FormDropdown<String>(
                    label: cfg.labelOf('service_type', tr('نوع الخدمة')),
                    value: d.serviceType,
                    items: {
                      for (final o in {...cfg.optionsOf('service_type'), if (d.serviceType != null) d.serviceType!}) o: o,
                    },
                    onChanged: (v) => update({'service_type': v}),
                  )
                : FormRow(label: cfg.labelOf('service_type', tr('نوع الخدمة')), value: d.serviceType ?? '—'),
          if (cfg.isVisible('payment_terms'))
            canEdit
                ? FormDropdown<String>(
                    label: cfg.labelOf('payment_terms', tr('شروط الدفع')),
                    value: d.paymentTerms,
                    emptyLabel: tr('حدّد'),
                    items: {
                      for (final o in {...cfg.optionsOf('payment_terms'), if (d.paymentTerms != null) d.paymentTerms!}) o: o,
                    },
                    onChanged: (v) => update({'payment_terms': v}),
                  )
                : FormRow(label: cfg.labelOf('payment_terms', tr('شروط الدفع')), value: d.paymentTerms ?? '—'),
          if (cfg.isVisible('estimated_value') || d.estimatedValue != null)
            FormRow(
              label: cfg.labelOf('estimated_value', tr('القيمة')),
              value: d.estimatedValue == null ? tr('أدخل') : money(d.estimatedValue!),
              muted: d.estimatedValue == null,
              onTap: !canEdit
                  ? null
                  : () async {
                      final v = await promptNumber(context, cfg.labelOf('estimated_value', tr('القيمة')), initial: d.estimatedValue);
                      if (v != null) await update({'estimated_value': v});
                    },
            ),
          if (cfg.isVisible('due_date'))
            FormRow(
              label: cfg.labelOf('due_date', tr('الموعد النهائي')),
              value: r.dueDate == null ? tr('بدون موعد') : formatShortDate(r.dueDate!),
              muted: r.dueDate == null,
              onTap: !canEdit
                  ? null
                  : () async {
                      final dt = await pickDate(context, initial: r.dueDate);
                      if (dt != null) {
                        await update({'due_date': dt.toIso8601String().substring(0, 10)});
                      }
                    },
            ),
          if (cfg.isVisible('priority')) FormRow(label: cfg.labelOf('priority', tr('الأولوية')), value: r.priority.label),
          FormRow(label: tr('المسؤول'), value: r.assigneeName ?? '—'),
          if (d.receivedAt != null) FormRow(label: tr('تاريخ الاستلام'), value: formatShortDate(d.receivedAt!)),
          for (final f in cfg.customVisible)
            if (d.custom[f.key] != null)
              FormRow(label: f.label, value: f.type == FieldType.boolean ? (d.custom[f.key] == true ? tr('نعم') : tr('لا')) : '${d.custom[f.key]}'),
        ]),
        if (d.description != null && d.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          CardBox(
            radius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('التفاصيل'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                const SizedBox(height: 6),
                Text(d.description!, style: const TextStyle(fontSize: 14, height: 1.7)),
              ],
            ),
          ),
        ],
        if (canEdit && r.status.isOpen && d.steps.isNotEmpty && d.doneSteps == d.steps.length) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('كل الخطوات تمت. أغلق الطلب ليبدأ تحصيل المتبقي من فواتيره.'),
                      style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.accentText, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => update({'status': 'closed'}, success: tr('أُغلق الطلب')),
                  child: Text(tr('إغلاق الطلب')),
                ),
              ],
            ),
          ),
        ],
        _LinkedInvoices(requestId: r.id, open: r.status.isOpen),
        const SizedBox(height: 18),
        _Steps(d: d, canEdit: canEdit),
      ],
    );
  }
}

class _Steps extends ConsumerWidget {
  const _Steps({required this.d, required this.canEdit});
  final RequestDetail d;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sectionRepoProvider);
    final firstOpen = d.steps.indexWhere((s) => !s.isDone);

    Future<void> run(Future<void> Function() action, {String? success}) async {
      if (await runAction(context, action, success: success)) refreshSections(ref);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                d.steps.isEmpty ? tr('الخطوات') : tr('الخطوات · {0}/{1}', [d.doneSteps, d.steps.length]),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (canEdit)
              TextButton.icon(
                onPressed: () async {
                  final t = await promptText(context, tr('خطوة جديدة'), label: tr('مثال: إصدار رخصة الدفاع المدني'), confirmLabel: tr('إضافة'));
                  if (t != null) await run(() => repo.addStep(d.item.id, t, d.steps.length + 1), success: tr('أُضيفت الخطوة'));
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('خطوة')),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (d.steps.isEmpty)
          CardBox(
            radius: 16,
            child: Text(
              canEdit
                  ? tr('قسّم الطلب إلى خطوات، وعند تأشير كل خطوة تتحدث نسبة الإنجاز تلقائيًا.')
                  : tr('لم تُضف خطوات لهذا الطلب بعد.'),
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.6),
            ),
          )
        else
          CardBox(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                for (var i = 0; i < d.steps.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TaskCheck(
                        done: d.steps[i].isDone,
                        onChanged: canEdit ? (v) => run(() => repo.setStepDone(d.steps[i].id, v)) : (_) {},
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.steps[i].title,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  fontWeight: i == firstOpen ? FontWeight.w700 : FontWeight.w500,
                                  color: d.steps[i].isDone ? AppColors.muted : AppColors.ink,
                                  decoration: d.steps[i].isDone ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              if (d.steps[i].isDone && d.steps[i].doneAt != null)
                                Text(tr('تمت {0}', [relativeDay(d.steps[i].doneAt!)]),
                                    style: TextStyle(fontSize: 11, color: AppColors.done)),
                              if (i == firstOpen)
                                Text(tr('الخطوة الحالية'), style: TextStyle(fontSize: 11, color: AppColors.accentText)),
                            ],
                          ),
                        ),
                      ),
                      if (canEdit)
                        PopupMenuButton<String>(
                          tooltip: tr('خيارات الخطوة'),
                          icon: Icon(Icons.more_vert, size: 18, color: AppColors.muted),
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final t = await promptText(context, tr('تعديل الخطوة'), initial: d.steps[i].title);
                              if (t != null) await run(() => repo.renameStep(d.steps[i].id, t));
                            } else {
                              final ok = await confirmAction(context,
                                  title: tr('حذف الخطوة؟'), message: '«${d.steps[i].title}»', confirmLabel: tr('حذف'), destructive: true);
                              if (ok) await run(() => repo.deleteStep(d.steps[i].id), success: tr('حُذفت الخطوة'));
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'rename', child: Text(tr('تعديل'))),
                            PopupMenuItem(value: 'delete', child: Text(tr('حذف'), style: TextStyle(color: AppColors.urgent))),
                          ],
                        )
                      else
                        const SizedBox(width: 12),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// الفواتير المرتبطة بالطلب (لمن يملك صلاحية المالية).
class _LinkedInvoices extends ConsumerWidget {
  const _LinkedInvoices({required this.requestId, required this.open});
  final String requestId;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canFinance = ref.watch(profileProvider).valueOrNull?.can(Permissions.financeManage) ?? false;
    if (!canFinance) return const SizedBox.shrink();
    final list = ref.watch(requestInvoicesProvider(requestId)).valueOrNull ?? const <Invoice>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final remaining = list.where((i) => !i.isVoid).fold<num>(0, (a, i) => a + i.remaining);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CardBox(
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('الفواتير المرتبطة'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                ),
                if (remaining > 0) Pill.waiting(tr('المتبقي {0}', [moneyShort(remaining)])) else Pill.done(tr('مسددة')),
              ],
            ),
            const SizedBox(height: 6),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${i.number} · ${moneyShort(i.net)} · ${i.isVoid ? tr('ملغاة') : (i.remaining > 0 ? tr('متبقٍ {0}', [moneyShort(i.remaining)]) : tr('مدفوعة'))}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (open && remaining > 0)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(tr('متابعة التحصيل تُنشأ تلقائيًا عند إغلاق الطلب'),
                    style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ),
          ],
        ),
      ),
    );
  }
}
