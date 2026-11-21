import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import 'custom_report.dart';
import 'report_common.dart';

// =====================================================================
// التقارير المخصصة
// =====================================================================
void openBuilder(BuildContext context, {String? id}) =>
    context.push(Uri(path: '/more/reports/builder', queryParameters: {if (id != null) 'id': id}).toString());

class CustomReportsTab extends ConsumerWidget {
  const CustomReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(savedReportsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          color: AppColors.primarySoft,
          borderColor: AppColors.primarySoft,
          padding: const EdgeInsets.all(16),
          onTap: () => openBuilder(context),
          child: Row(
            children: [
              Icon(Icons.add_chart, color: AppColors.accentText, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('تقرير جديد'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(tr('اختر المصدر والفترة والتجميع والمقياس وطريقة العرض'),
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(AppIcons.forward, color: AppColors.accentText),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AsyncBody<List<SavedReport>>(
          value: list,
          onRetry: () => ref.invalidate(savedReportsProvider),
          builder: (items) => items.isEmpty
              ? EmptyState(tr('لا توجد تقارير محفوظة بعد — أنشئ أول تقرير لك'), icon: Icons.insert_chart_outlined)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in items) ...[SavedReportCard(report: r), const SizedBox(height: 12)],
                  ],
                ),
        ),
      ],
    );
  }
}

class SavedReportCard extends ConsumerWidget {
  const SavedReportCard({super.key, required this.report, this.compact = false});
  final SavedReport report;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).valueOrNull;
    final mine = report.ownerId == me?.id;
    final repo = ref.read(sectionRepoProvider);

    Future<void> toggle({bool? pinned, bool? onTv, bool? shared}) async {
      if (await runAction(
        context,
        () => repo.saveReport(
          id: report.id,
          name: report.name,
          config: report.config,
          shared: shared ?? report.shared,
          pinned: pinned ?? report.pinned,
          onTv: onTv ?? report.onTv,
        ),
      )) {
        ref.invalidate(savedReportsProvider);
      }
    }

    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(report.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        if (report.shared) ...[
                          const SizedBox(width: 6),
                          Tooltip(message: tr('مشترك مع الفريق'), child: Icon(Icons.group_outlined, size: 16, color: AppColors.muted)),
                        ],
                        if (report.onTv) ...[
                          const SizedBox(width: 4),
                          Tooltip(message: tr('على شاشة المكتب'), child: Icon(Icons.tv_outlined, size: 16, color: AppColors.muted)),
                        ],
                      ],
                    ),
                    Text(customSummary(report.config), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('خيارات'),
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      openBuilder(context, id: report.id);
                    case 'pin':
                      await toggle(pinned: !report.pinned);
                    case 'tv':
                      await toggle(onTv: !report.onTv);
                    case 'share':
                      await toggle(shared: !report.shared);
                    case 'delete':
                      final ok = await confirmAction(
                        context,
                        title: tr('حذف التقرير'),
                        message: tr('سيُحذف «{0}» نهائيًا.', [report.name]),
                        confirmLabel: tr('حذف'),
                        destructive: true,
                      );
                      if (ok && context.mounted && await runAction(context, () => repo.deleteReport(report.id))) {
                        ref.invalidate(savedReportsProvider);
                      }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(mine ? tr('تعديل') : tr('نسخ وتعديل'))),
                  if (mine) ...[
                    PopupMenuItem(value: 'pin', child: Text(report.pinned ? tr('إلغاء التثبيت من «نظرة عامة»') : tr('تثبيت في «نظرة عامة»'))),
                    PopupMenuItem(value: 'share', child: Text(report.shared ? tr('إلغاء المشاركة') : tr('مشاركة مع الفريق'))),
                    PopupMenuItem(value: 'tv', child: Text(report.onTv ? tr('إزالته من شاشة المكتب') : tr('عرضه على شاشة المكتب'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('حذف'), style: TextStyle(color: AppColors.danger))),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: CustomReportView(config: report.config, height: compact ? 160 : 200),
          ),
        ],
      ),
    );
  }
}

/// التقارير المثبّتة أسفل «نظرة عامة»
class PinnedReports extends ConsumerWidget {
  const PinnedReports({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = (ref.watch(savedReportsProvider).valueOrNull ?? const <SavedReport>[]).where((r) => r.pinned).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 2 : 1;
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final r in pinned) SizedBox(width: w, child: SavedReportCard(report: r, compact: true))],
        );
      }),
    );
  }
}

// =====================================================================
// خريطة ضغط العمل
// =====================================================================
class WorkloadCard extends ConsumerWidget {
  const WorkloadCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(workloadProvider);
    return ReportCard(
      title: tr('ضغط العمل · الأسبوعان القادمان'),
      subtitle: tr('المهام والطلبات والاجتماعات المستحقة لكل عضو يوميًا — وزّع قبل أن يتأخر العمل'),
      child: AsyncBody<Map<String, dynamic>>(
        value: data,
        onRetry: () => ref.invalidate(workloadProvider),
        builder: (m) {
          final days = [for (final d in (m['days'] as List? ?? const [])) DateTime.tryParse('$d') ?? DateTime.now()];
          final members = [
            for (final x in (m['members'] as List? ?? const []))
              if (x is Map) Map<String, dynamic>.from(x),
          ];
          if (members.isEmpty || days.isEmpty) return mutedText(tr('لا توجد بيانات'));
          int load(Map c) => ReportData.n(c['tasks']).toInt() + ReportData.n(c['requests']).toInt() + ReportData.n(c['meetings']).toInt();
          var maxLoad = 1;
          for (final mm in members) {
            for (final c in (mm['cells'] as List? ?? const [])) {
              if (c is Map && load(c) > maxLoad) maxLoad = load(c);
            }
          }
          Color cellColor(int v) {
            if (v == 0) return AppColors.divider;
            final t = (v / maxLoad).clamp(0.0, 1.0);
            if (t < 0.34) return ChartColors.green.withValues(alpha: 0.35 + t);
            if (t < 0.67) return ChartColors.amber.withValues(alpha: 0.55 + t / 3);
            return ChartColors.coral.withValues(alpha: 0.75 + t / 4);
          }

          const cell = 30.0, nameW = 96.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: nameW),
                        SizedBox(
                          width: 46,
                          child: Text(tr('متأخر'), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.urgent)),
                        ),
                        for (final d in days)
                          SizedBox(
                            width: cell + 4,
                            child: Column(
                              children: [
                                Text(formatPattern('E', d), style: TextStyle(fontSize: 9, color: AppColors.muted)),
                                Text('${d.day}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: d.weekday == DateTime.friday || d.weekday == DateTime.saturday ? AppColors.faint : AppColors.ink,
                                    )),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final mm in members)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: nameW,
                              child: Text('${mm['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            SizedBox(
                              width: 46,
                              child: Center(
                                child: ReportData.n(mm['overdue']) > 0
                                    ? Pill.urgent(fmtNum(ReportData.n(mm['overdue'])))
                                    : Text('—', style: TextStyle(color: AppColors.faint)),
                              ),
                            ),
                            for (var i = 0; i < days.length; i++)
                              () {
                                final cells = mm['cells'] as List? ?? const [];
                                final c = i < cells.length && cells[i] is Map ? cells[i] as Map : const {};
                                final v = load(c);
                                return ChartTip(
                                  message: [
                                    '${mm['name']} · ${formatDay(days[i])}',
                                    tr('مهام: {0} · طلبات: {1} · اجتماعات: {2}',
                                        [ReportData.n(c['tasks']), ReportData.n(c['requests']), ReportData.n(c['meetings'])]),
                                  ].join('\n'),
                                  child: Container(
                                    width: cell,
                                    height: cell,
                                    margin: const EdgeInsets.all(2),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: cellColor(v), borderRadius: BorderRadius.circular(7)),
                                    child: v == 0
                                        ? null
                                        : Text('$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E1E26))),
                                  ),
                                );
                              }(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Legend([
                (tr('خفيف'), ChartColors.green.withValues(alpha: 0.5)),
                (tr('متوسط'), ChartColors.amber.withValues(alpha: 0.8)),
                (tr('مزدحم'), ChartColors.coral),
              ]),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// مسار البيع
// =====================================================================
class FunnelCard extends ConsumerWidget {
  const FunnelCard({super.key, required this.filter});
  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (filter.from, filter.to);
    final data = ref.watch(funnelProvider(key));
    final names = {
      'created': tr('عروض الفترة'),
      'sent': tr('أُرسلت'),
      'accepted': tr('قُبلت'),
      'invoiced': tr('فُوترت'),
      'collected': tr('حُصّلت بالكامل'),
    };
    const colors = [ChartColors.slate, ChartColors.blue, Color(0xFF4FB3BF), ChartColors.amber, ChartColors.green];
    return ReportCard(
      title: tr('مسار البيع'),
      subtitle: tr('من عرض السعر حتى التحصيل — للعروض المرسلة في الفترة'),
      child: AsyncBody<Map<String, dynamic>>(
        value: data,
        onRetry: () => ref.invalidate(funnelProvider(key)),
        builder: (m) {
          final stages = [
            for (final s in (m['stages'] as List? ?? const []))
              if (s is Map) Map<String, dynamic>.from(s),
          ];
          final first = stages.isEmpty ? 0 : ReportData.n(stages.first['count']);
          if (first == 0) return mutedText(tr('لا توجد عروض أسعار في هذه الفترة'));
          final lost = m['lost'] is Map ? Map<String, dynamic>.from(m['lost'] as Map) : const <String, dynamic>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < stages.length; i++)
                () {
                  final s = stages[i];
                  final n = ReportData.n(s['count']);
                  final prev = i == 0 ? n : ReportData.n(stages[i - 1]['count']);
                  final conv = prev == 0 ? null : n * 100 / prev;
                  return ChartTip(
                    message: [
                      names[s['key']] ?? '${s['key']}',
                      tr('العدد: {0}', [fmtNum(n)]),
                      tr('القيمة: {0}', [moneyLabel(ReportData.n(s['value']))]),
                      if (i > 0) tr('من المرحلة السابقة: {0}', [fmtPct(conv)]),
                      tr('من كل العروض: {0}', [fmtPct(n * 100 / first)]),
                    ].join('\n'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 92, child: Text(names[s['key']] ?? '', style: const TextStyle(fontSize: 13))),
                          Expanded(
                            child: LayoutBuilder(builder: (context, c) {
                              final w = c.maxWidth * (n / first);
                              return Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Container(
                                  width: w < 28 ? 28 : w,
                                  height: 30,
                                  alignment: AlignmentDirectional.centerStart,
                                  padding: const EdgeInsetsDirectional.only(start: 8),
                                  decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(8)),
                                  child: Text(fmtNum(n),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                              );
                            }),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(moneyCompact(ReportData.n(s['value'])),
                                textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(i == 0 ? '' : fmtPct(conv),
                                textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (ReportData.n(lost['waiting']) > 0)
                    ActionChip(
                      label: Text(tr('{0} بانتظار الرد', [fmtNum(ReportData.n(lost['waiting']))])),
                      onPressed: () => openDrill(context, 'quotes_no_reply', filter),
                    ),
                  if (ReportData.n(lost['rejected']) > 0) Pill.urgent(tr('{0} مرفوض', [fmtNum(ReportData.n(lost['rejected']))])),
                  if (ReportData.n(lost['expired']) > 0) Pill.neutral(tr('{0} منتهٍ', [fmtNum(ReportData.n(lost['expired']))])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// تصنيف العملاء
// =====================================================================
class ClientTiersCard extends ConsumerStatefulWidget {
  const ClientTiersCard({super.key});

  @override
  ConsumerState<ClientTiersCard> createState() => _ClientTiersCardState();
}

class _ClientTiersCardState extends ConsumerState<ClientTiersCard> {
  String _tier = 'at_risk';

  static final _tiers = <(String, String, String, Color)>[
    ('gold', 'ذهبي', 'أعلى ٢٠٪ قيمةً ومتعامل خلال ٩٠ يومًا', ChartColors.amber),
    ('active', 'نشط', 'تعامل خلال آخر ٤٥ يومًا', ChartColors.green),
    ('new', 'جديد', 'أُضيف خلال آخر ٣٠ يومًا', ChartColors.blue),
    ('at_risk', 'معرّض للفقد', 'لا تواصل منذ ٤٦–١٢٠ يومًا', ChartColors.coral),
    ('dormant', 'خامل', 'لا تواصل منذ أكثر من ١٢٠ يومًا', ChartColors.slate),
  ];

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(clientTiersProvider);
    return ReportCard(
      title: tr('تصنيف العملاء'),
      subtitle: tr('حسب القيمة وانتظام التعامل — اضغط على الفئة لعرض عملائها'),
      child: AsyncBody<Map<String, dynamic>>(
        value: data,
        onRetry: () => ref.invalidate(clientTiersProvider),
        builder: (m) {
          final counts = m['counts'] is Map ? Map<String, dynamic>.from(m['counts'] as Map) : const <String, dynamic>{};
          final total = _tiers.fold<num>(0, (a, t) => a + ReportData.n(counts[t.$1]));
          final clients = [
            for (final c in (m['clients'] as List? ?? const []))
              if (c is Map && c['tier'] == _tier) Map<String, dynamic>.from(c),
          ];
          final fin = m['can_finance'] == true;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StackedBar(
                height: 16,
                trackColor: AppColors.divider,
                parts: [for (final t in _tiers) (ReportData.n(counts[t.$1]), t.$4)],
                tips: [for (final t in _tiers) shareTip(tr(t.$2), ReportData.n(counts[t.$1]), total)],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tiers)
                    Tooltip(
                      message: tr(t.$3),
                      child: ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: t.$4, radius: 5),
                        label: Text('${tr(t.$2)} ${fmtNum(ReportData.n(counts[t.$1]))}'),
                        selected: _tier == t.$1,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _tier = t.$1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (clients.isEmpty)
                mutedText(tr('لا يوجد عملاء في هذه الفئة'))
              else
                for (final c in clients.take(10))
                  ReportRowTile(
                    title: '${c['name']}',
                    subtitle: [
                      tr('{0} طلب خلال سنة', [c['requests']]),
                      if (fin && c['value'] != null) moneyLabel(ReportData.n(c['value'])),
                    ].join(' · '),
                    trailing: Text(
                      ReportData.n(c['days']) == 0 ? tr('اليوم') : tr('آخر تواصل منذ {0} يوم', [c['days']]),
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    onTap: () => context.go('/more/clients/${c['id']}'),
                  ),
              if (clients.length > 10)
                Text(tr('و{0} أخرى', [clients.length - 10]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          );
        },
      ),
    );
  }
}
