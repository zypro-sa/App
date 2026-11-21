import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/web/web_tools.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import 'report_advanced.dart';
import 'report_common.dart';
import 'report_export.dart';

enum ReportPeriod { week, month, quarter, custom }

enum _Mode { dashboard, numbers, detail }

/// ١٣ · التقارير — لوحة، أرقام، وتفصيل، مع تقرير شخصي لكل عضو.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.month;
  DateTimeRange? _custom;
  String? _member;
  bool _mine = false;

  (DateTime, DateTime) get _range {
    final today = dateOnly(DateTime.now());
    if (_period == ReportPeriod.custom && _custom != null) return (dateOnly(_custom!.start), dateOnly(_custom!.end));
    final days = switch (_period) {
      ReportPeriod.week => 7,
      ReportPeriod.quarter => 90,
      _ => 30,
    };
    return (today.subtract(Duration(days: days - 1)), today);
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _custom ?? DateTimeRange(start: _range.$1, end: _range.$2),
    );
    if (r != null) {
      setState(() {
        _custom = r;
        _period = ReportPeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    if (me == null) return Scaffold(appBar: sectionAppBar(tr('التقارير')), body: const Center(child: CircularProgressIndicator()));
    final canAll = me.can(Permissions.reportsView);
    final canFinance = me.can(Permissions.financeView);
    final member = !canAll || _mine ? me.id : _member;
    final (from, to) = _range;
    final filter = ReportFilter(from: from, to: to, member: member);
    final data = ref.watch(reportDashboardProvider(filter.key));
    final d = data.valueOrNull;

    final whole = member == null;
    final tabs = <(String, Widget Function(ReportData))>[
      (tr('نظرة عامة'), (r) => _OverviewTab(r, filter)),
      (tr('تقارير مخصصة'), (_) => const CustomReportsTab()),
      (tr('الطلبات'), (r) => _RequestsTab(r, filter)),
      if (whole) (tr('الفريق'), (r) => _TeamTab(r, filter, onMember: (id) => setState(() => _member = id))),
      if (whole && canFinance) (tr('المالية'), (r) => _FinanceTab(r, filter)),
      if (whole) (tr('العملاء والاجتماعات'), (r) => _ClientsTab(r, filter)),
      if (!whole) (tr('الاجتماعات والوعود'), (r) => _MeetingsBlock(r)),
      if (whole && canAll) (tr('الأهداف'), (_) => const _GoalsTab()),
    ];

    final members = (ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[])
        .where((m) => m.isActive && !m.pending)
        .toList();
    final memberName = member == null
        ? null
        : member == me.id
            ? me.name
            : members.where((m) => m.id == member).map((m) => m.name).firstOrNull;

    return DefaultTabController(
      key: ValueKey('${tabs.length}-$whole'),
      length: tabs.length,
      child: Scaffold(
        appBar: sectionAppBar(
          !canAll || _mine ? tr('تقريري') : tr('التقارير'),
          subtitle: memberName == null ? filter.label : tr('{0} · {1}', [memberName, filter.label]),
          actions: [
            if (canAll)
              IconButton(
                tooltip: tr('عرض على شاشة المكتب'),
                icon: const Icon(Icons.tv_outlined),
                onPressed: () => context.push('/tv'),
              ),
            PopupMenuButton<String>(
              tooltip: tr('تصدير'),
              icon: const Icon(Icons.ios_share),
              enabled: d != null,
              onSelected: (v) => _export(v, d!, filter, memberName),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'pdf', child: ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(tr('PDF للطباعة')))),
                PopupMenuItem(value: 'csv', child: ListTile(leading: const Icon(Icons.table_chart_outlined), title: Text(tr('Excel (CSV)')))),
                PopupMenuItem(value: 'share', child: ListTile(leading: const Icon(Icons.share_outlined), title: Text(tr('مشاركة الملخص')))),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _FilterBar(
              period: _period,
              onPeriod: (p) => p == ReportPeriod.custom ? _pickCustom() : setState(() => _period = p),
              canAll: canAll,
              mine: _mine,
              onMine: (v) => setState(() => _mine = v),
              member: _member,
              members: members,
              onMember: (id) => setState(() => _member = id),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final t in tabs)
                    RefreshIndicator(
                      onRefresh: () async => ref.invalidate(reportDashboardProvider),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                        children: [
                          AsyncBody<ReportData>(
                            value: data,
                            onRetry: () => ref.invalidate(reportDashboardProvider(filter.key)),
                            builder: t.$2,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(String kind, ReportData d, ReportFilter f, String? memberName) async {
    final labels = requestLabelsNow(ref);
    final name = 'zypro-report-${ReportFilter.iso(f.from)}_${ReportFilter.iso(f.to)}';
    switch (kind) {
      case 'pdf':
        printHtml(reportHtml(d, f, labels, memberName: memberName));
      case 'csv':
        downloadText('$name.csv', reportCsv(d, f, labels, memberName: memberName));
      case 'share':
        final res = await shareText(tr('ملخص التقرير'), reportSummaryText(d, f, memberName: memberName));
        if (!mounted) return;
        if (res == 'copied') showSnack(context, tr('نُسخ الملخص — الصقه حيث تريد'));
        if (res == 'failed') showSnack(context, tr('تعذّرت المشاركة على هذا الجهاز'));
    }
  }
}

// =====================================================================
// شريط الفلاتر
// =====================================================================
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.period,
    required this.onPeriod,
    required this.canAll,
    required this.mine,
    required this.onMine,
    required this.member,
    required this.members,
    required this.onMember,
  });
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onPeriod;
  final bool canAll;
  final bool mine;
  final ValueChanged<bool> onMine;
  final String? member;
  final List<TeamMember> members;
  final ValueChanged<String?> onMember;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ReportPeriod.week: tr('٧ أيام'),
      ReportPeriod.month: tr('٣٠ يومًا'),
      ReportPeriod.quarter: tr('٩٠ يومًا'),
      ReportPeriod.custom: tr('فترة مخصصة'),
    };
    final selectedMember = members.where((m) => m.id == member).map((m) => m.name).firstOrNull;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          for (final p in ReportPeriod.values) ...[
            ChoiceChip(
              label: Text(labels[p]!),
              avatar: p == ReportPeriod.custom ? const Icon(Icons.date_range, size: 16) : null,
              selected: period == p,
              showCheckmark: false,
              onSelected: (_) => onPeriod(p),
            ),
            const SizedBox(width: 6),
          ],
          if (canAll) ...[
            Container(width: 1, height: 24, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
            FilterChip(
              label: Text(tr('تقريري')),
              avatar: const Icon(Icons.person_outline, size: 16),
              selected: mine,
              showCheckmark: false,
              onSelected: onMine,
            ),
            const SizedBox(width: 6),
            if (!mine && members.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: tr('العضو'),
                onSelected: (v) => onMember(v.isEmpty ? null : v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: '', child: Text(tr('كل الفريق'))),
                  for (final m in members) PopupMenuItem(value: m.id, child: Text(m.name)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.group_outlined, size: 16),
                  label: Text(selectedMember ?? tr('كل الفريق')),
                  backgroundColor: selectedMember == null ? null : AppColors.primarySoft,
                  deleteIcon: selectedMember == null ? null : const Icon(Icons.close, size: 16),
                  onDeleted: selectedMember == null ? null : () => onMember(null),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// نظرة عامة: لوحة / أرقام / تفصيلي
// =====================================================================
class _OverviewTab extends StatefulWidget {
  const _OverviewTab(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  _Mode _mode = _Mode.dashboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Mode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: _Mode.dashboard, icon: const Icon(Icons.dashboard_outlined, size: 18), label: Text(tr('لوحة'))),
            ButtonSegment(value: _Mode.numbers, icon: const Icon(Icons.pin_outlined, size: 18), label: Text(tr('أرقام'))),
            ButtonSegment(value: _Mode.detail, icon: const Icon(Icons.view_list_outlined, size: 18), label: Text(tr('تفصيلي'))),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 14),
        switch (_mode) {
          _Mode.dashboard => _Dashboard(widget.d, widget.f),
          _Mode.numbers => _Numbers(widget.d, widget.f),
          _Mode.detail => _Detail(widget.d, widget.f),
        },
      ],
    );
  }
}

List<num> _weeklyValues(ReportData d) => [for (final w in d.weekly) ReportData.n(w['count'])];

class _Dashboard extends StatelessWidget {
  const _Dashboard(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context) {
    final k = d.kpi;
    final weekly = _weeklyValues(d);
    final fin = d.finance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlertsCard(data: d, filter: f),
        const SizedBox(height: 14),
        ResponsiveGrid(children: [
          KpiCard(
            label: tr('طلبات منجزة'), info: kpiInfo('closed'), prev: fmtNum(ReportData.n(k['closed_prev'])),
            value: fmtNum(ReportData.n(k['closed'])),
            change: changeOf(ReportData.nn(k['closed']), ReportData.nn(k['closed_prev'])),
            spark: weekly,
            onTap: () => openDrill(context, 'closed', f),
          ),
          KpiCard(
            label: tr('الالتزام بالمواعيد'), info: kpiInfo('on_time'), prev: fmtPct(ReportData.nn(k['on_time_prev'])),
            value: fmtPct(ReportData.nn(k['on_time'])),
            change: changeOf(ReportData.nn(k['on_time']), ReportData.nn(k['on_time_prev']), points: true),
            onTap: () => openDrill(context, 'overdue', f),
          ),
          KpiCard(
            label: tr('متوسط زمن الإنجاز'), info: kpiInfo('avg_days'), prev: fmtDays(ReportData.nn(k['avg_days_prev'])),
            value: fmtDays(ReportData.nn(k['avg_days'])),
            change: changeOf(ReportData.nn(k['avg_days']), ReportData.nn(k['avg_days_prev']), lowerIsBetter: true),
            onTap: () => openDrill(context, 'closed', f),
          ),
          if (fin != null)
            KpiCard(
              label: tr('المحصّل'), info: kpiInfo('collected'), prev: moneyLabel(ReportData.n(fin['collected_prev'])),
              value: moneyCompact(ReportData.n(fin['collected'])),
              change: changeOf(ReportData.nn(fin['collected']), ReportData.nn(fin['collected_prev'])),
              color: ChartColors.blue,
              spark: [for (final m in d.listOf(fin, 'monthly')) ReportData.n(m['collected'])],
              note: tr('ر.س'),
              onTap: () => openDrill(context, 'late_invoices', f),
            )
          else
            KpiCard(
              label: tr('طلبات جديدة'), info: kpiInfo('new'), prev: fmtNum(ReportData.n(k['new_prev'])),
              value: fmtNum(ReportData.n(k['new'])),
              change: changeOf(ReportData.nn(k['new']), ReportData.nn(k['new_prev'])),
              onTap: () => openDrill(context, 'new', f),
            ),
        ]),
        const SizedBox(height: 14),
        _WeeklyCard(d),
        const SizedBox(height: 14),
        TwoUp(_StatusCard(d, f), _OnTimeCard(d)),
        const SizedBox(height: 14),
        ResponsiveGrid(height: 96, children: [
          KpiCard(
            label: tr('مفتوحة الآن'), info: kpiInfo('open'),
            value: fmtNum(ReportData.n(k['open'])),
            onTap: () => openDrill(context, 'open', f),
          ),
          KpiCard(
            label: tr('طلبات جديدة'), info: kpiInfo('new'), prev: fmtNum(ReportData.n(k['new_prev'])),
            value: fmtNum(ReportData.n(k['new'])),
            change: changeOf(ReportData.nn(k['new']), ReportData.nn(k['new_prev'])),
            onTap: () => openDrill(context, 'new', f),
          ),
          KpiCard(
            label: tr('مهام منجزة'), info: kpiInfo('tasks_done'), prev: fmtNum(ReportData.n(k['tasks_done_prev'])),
            value: fmtNum(ReportData.n(k['tasks_done'])),
            change: changeOf(ReportData.nn(k['tasks_done']), ReportData.nn(k['tasks_done_prev'])),
            onTap: f.member == null ? null : () => openDrill(context, 'member_tasks', f),
          ),
          KpiCard(
            label: tr('اجتماعات منعقدة'), info: kpiInfo('meetings_held'), prev: fmtNum(ReportData.n(k['meetings_held_prev'])),
            value: fmtNum(ReportData.n(k['meetings_held'])),
            change: changeOf(ReportData.nn(k['meetings_held']), ReportData.nn(k['meetings_held_prev'])),
            onTap: () => context.go('/meetings'),
          ),
        ]),
        const PinnedReports(),
      ],
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard(this.d);
  final ReportData d;

  @override
  Widget build(BuildContext context) {
    final values = _weeklyValues(d);
    final goal = ReportData.nn(d.goals['requests_closed']);
    final perWeek = goal == null ? null : goal / 4.33;
    final first = d.weekly.isEmpty ? null : DateTime.tryParse('${d.weekly.first['week']}');
    final last = d.weekly.isEmpty ? null : DateTime.tryParse('${d.weekly.last['week']}');
    return ReportCard(
      title: tr('المنجز أسبوعيًا · آخر ١٢ أسبوعًا'),
      trailing: perWeek == null ? null : Legend([(tr('الهدف الأسبوعي'), ChartColors.amber)]),
      child: values.every((v) => v == 0)
          ? mutedText(tr('لا توجد طلبات منجزة في هذه الأسابيع'))
          : Column(
              children: [
                AreaChart(
                  values: values,
                  target: perWeek,
                  height: 150,
                  gridColor: AppColors.line,
                  tooltipBuilder: (i) {
                    final w = DateTime.tryParse('${d.weekly[i]['week']}');
                    final range = w == null ? '' : tr('{0} – {1}', [formatShortDate(w), formatShortDate(w.add(const Duration(days: 6)))]);
                    return [
                      range,
                      tr('منجز: {0}', [values[i]]),
                      if (perWeek != null) tr('الهدف: {0}', [perWeek.toStringAsFixed(1)]),
                    ].join('\n');
                  },
                  semanticLabel: tr('الطلبات المنجزة أسبوعيًا: {0}', [values.join(tr('، '))]),
                ),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(first == null ? '' : formatShortDate(first), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      Text(tr('هذا الأسبوع: {0}', [values.isEmpty ? 0 : values.last]),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentText)),
                      Text(last == null ? '' : formatShortDate(last), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = requestLabels(ref);
    final entries = d.byStatus.entries.toList()..sort((a, b) => ReportData.n(b.value).compareTo(ReportData.n(a.value)));
    final total = entries.fold<num>(0, (a, e) => a + ReportData.n(e.value));
    return ReportCard(
      title: tr('المفتوحة حسب الحالة'),
      trailing: Text(fmtNum(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      child: total == 0
          ? mutedText(tr('لا توجد طلبات مفتوحة'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StackedBar(
                  parts: [for (final e in entries) (ReportData.n(e.value), statusColor(e.key, labels))],
                  tips: [for (final e in entries) shareTip(statusName(e.key, labels), ReportData.n(e.value), total)],
                  height: 18,
                ),
                const SizedBox(height: 10),
                for (final e in entries)
                  ReportRowTile(
                    leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor(e.key, labels), shape: BoxShape.circle)),
                    title: statusName(e.key, labels),
                    trailing: Text(fmtNum(ReportData.n(e.value)), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => openDrill(context, 'open', f),
                  ),
              ],
            ),
    );
  }
}

class _OnTimeCard extends StatelessWidget {
  const _OnTimeCard(this.d);
  final ReportData d;

  @override
  Widget build(BuildContext context) {
    final v = ReportData.nn(d.kpi['on_time']);
    final color = v == null ? ChartColors.slate : (v >= 85 ? ChartColors.green : v >= 70 ? ChartColors.amber : ChartColors.coral);
    return ReportCard(
      title: tr('التسليم في الموعد'),
      subtitle: tr('من الطلبات المنجزة ذات موعد'),
      child: Center(
        child: DonutChart(
          size: 150,
          thickness: 18,
          trackColor: AppColors.divider,
          semanticLabel: tr('التسليم في الموعد {0}', [fmtPct(v)]),
          tooltip: [kpiInfo('on_time'), tr('الفترة السابقة: {0}', [fmtPct(ReportData.nn(d.kpi['on_time_prev']))])].join('\n'),
          parts: [((v ?? 0), color), (100 - (v ?? 0), Colors.transparent)],
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fmtPct(v), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              Text(tr('في الموعد'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- الأرقام ----------------
enum _Cmp { previous, lastYear, custom }

class _Numbers extends ConsumerStatefulWidget {
  const _Numbers(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  ConsumerState<_Numbers> createState() => _NumbersState();
}

class _NumbersState extends ConsumerState<_Numbers> {
  _Cmp _cmp = _Cmp.previous;
  DateTimeRange? _range;

  static DateTime _yearBack(DateTime d) => DateTime(d.year - 1, d.month, d.day.clamp(1, DateTime(d.year - 1, d.month + 1, 0).day));

  Future<void> _pick() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 4),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: _yearBack(widget.f.from), end: _yearBack(widget.f.to)),
    );
    if (r != null) {
      setState(() {
        _range = DateTimeRange(start: dateOnly(r.start), end: dateOnly(r.end));
        _cmp = _Cmp.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d, f = widget.f;
    final k = d.kpi;
    final fin = d.finance;
    final (DateTime, DateTime)? cr = switch (_cmp) {
      _Cmp.lastYear => (_yearBack(f.from), _yearBack(f.to)),
      _Cmp.custom => _range == null ? null : (_range!.start, _range!.end),
      _Cmp.previous => null,
    };
    final cmpAsync = cr == null ? null : ref.watch(reportDashboardProvider((cr.$1, cr.$2, f.member)));
    final cmp = cmpAsync?.valueOrNull;
    final cmpLabel = cr == null ? tr('السابقة') : tr('{0} – {1}', [formatShortDate(cr.$1), formatShortDate(cr.$2)]);

    num? prevOf(Map<String, dynamic>? cur, Map<String, dynamic>? other, String key, {bool snapshot = false}) {
      if (cr == null) return ReportData.nn(cur?['${key}_prev']);
      if (snapshot) return null;
      return ReportData.nn(other?[key]);
    }

    final rows = <(String, String, num?, num?, String Function(num?), bool, bool, String?)>[
      (tr('طلبات منجزة'), 'closed', ReportData.nn(k['closed']), prevOf(k, cmp?.kpi, 'closed'), _n, false, false, 'closed'),
      (tr('طلبات جديدة'), 'new', ReportData.nn(k['new']), prevOf(k, cmp?.kpi, 'new'), _n, false, false, 'new'),
      (tr('الالتزام بالمواعيد'), 'on_time', ReportData.nn(k['on_time']), prevOf(k, cmp?.kpi, 'on_time'), fmtPct, false, true, null),
      (tr('متوسط زمن الإنجاز'), 'avg_days', ReportData.nn(k['avg_days']), prevOf(k, cmp?.kpi, 'avg_days'), fmtDays, true, false, null),
      (tr('مهام منجزة'), 'tasks_done', ReportData.nn(k['tasks_done']), prevOf(k, cmp?.kpi, 'tasks_done'), _n, false, false, null),
      (tr('اجتماعات منعقدة'), 'meetings_held', ReportData.nn(k['meetings_held']), prevOf(k, cmp?.kpi, 'meetings_held'), _n, false, false, null),
      if (f.member == null)
        (tr('عملاء جدد'), 'new_clients', ReportData.nn(k['new_clients']), prevOf(k, cmp?.kpi, 'new_clients'), _n, false, false, null),
      if (fin != null) ...[
        (tr('المحصّل'), 'collected', ReportData.nn(fin['collected']), prevOf(fin, cmp?.finance, 'collected'), _m, false, false, null),
        (tr('المفوتر'), 'billed', ReportData.nn(fin['billed']), cr == null ? null : ReportData.nn(cmp?.finance?['billed']), _m, false, false, null),
        (tr('المستحق على العملاء'), 'due', ReportData.nn(fin['due']), null, _m, false, false, 'late_invoices'),
      ],
    ];
    final a = d.alerts;
    final now = <(String, num, String)>[
      (tr('مفتوحة الآن'), ReportData.n(k['open']), 'open'),
      (tr('متأخرة'), ReportData.n(a['overdue']), 'overdue'),
      (tr('بانتظار العميل أكثر من أسبوع'), ReportData.n(a['waiting_long']), 'waiting_long'),
      if (a['quotes_no_reply'] != null) (tr('عروض بلا رد'), ReportData.n(a['quotes_no_reply']), 'quotes_no_reply'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportCard(
          title: tr('المقارنة'),
          subtitle: tr('{0} مقابل {1}', [f.label, cmpLabel]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(tr('الفترة السابقة')),
                    selected: _cmp == _Cmp.previous,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _cmp = _Cmp.previous),
                  ),
                  ChoiceChip(
                    label: Text(tr('نفس الفترة العام الماضي')),
                    selected: _cmp == _Cmp.lastYear,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _cmp = _Cmp.lastYear),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.date_range, size: 16),
                    label: Text(tr('فترة أخرى')),
                    selected: _cmp == _Cmp.custom,
                    showCheckmark: false,
                    onSelected: (_) => _pick(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (cmpAsync != null && cmpAsync.isLoading && cmp == null) const LinearProgressIndicator(minHeight: 2),
              Row(
                children: [
                  Expanded(flex: 5, child: Text(tr('المؤشر'), style: _head)),
                  Expanded(flex: 3, child: Text(tr('الحالية'), style: _head, textAlign: TextAlign.end)),
                  Expanded(flex: 3, child: Text(cr == null ? tr('السابقة') : tr('المقارنة'), style: _head, textAlign: TextAlign.end)),
                  Expanded(flex: 3, child: Text(tr('التغير'), style: _head, textAlign: TextAlign.end)),
                ],
              ),
              const Divider(height: 18),
              for (final r in rows)
                ChartTip(
                  message: [
                    kpiInfo(r.$2),
                    tr('الحالية: {0}', [r.$5(r.$3)]),
                    tr('المقارنة: {0}', [r.$4 == null ? '—' : r.$5(r.$4)]),
                  ].join('\n'),
                  child: InkWell(
                    onTap: r.$8 == null ? null : () => openDrill(context, r.$8!, f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: Text(r.$1, style: const TextStyle(fontSize: 14))),
                          Expanded(
                            flex: 3,
                            child: Text(r.$5(r.$3),
                                textAlign: TextAlign.end, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(r.$4 == null ? '—' : r.$5(r.$4),
                                textAlign: TextAlign.end, style: TextStyle(fontSize: 14, color: AppColors.muted)),
                          ),
                          Expanded(flex: 3, child: _ChangeText(changeOf(r.$3, r.$4, lowerIsBetter: r.$6, points: r.$7))),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(
          height: 92,
          children: [
            for (final (label, n, kind) in now)
              KpiCard(label: label, value: fmtNum(n), info: kpiInfo(kind), onTap: () => openDrill(context, kind, f)),
          ],
        ),
      ],
    );
  }

  static String _n(num? v) => v == null ? '—' : fmtNum(v);
  static String _m(num? v) => v == null ? '—' : moneyCompact(v);
  static TextStyle get _head => TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600);
}

class _ChangeText extends StatelessWidget {
  const _ChangeText(this.c);
  final (String, bool)? c;

  @override
  Widget build(BuildContext context) => Text(
        c?.$1 ?? '—',
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c == null ? AppColors.muted : (c!.$2 ? AppColors.done : AppColors.urgent),
        ),
      );
}

// ---------------- التفصيلي ----------------
class _Detail extends StatelessWidget {
  const _Detail(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StuckCard(d),
        const SizedBox(height: 14),
        _ServicesCard(d),
        if (d.team.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TeamTable(d, f),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in ['closed', 'new', 'open', 'overdue', 'waiting_long'])
              ActionChip(
                avatar: const Icon(Icons.list_alt, size: 16),
                label: Text(drillTitle(kind)),
                onPressed: () => openDrill(context, kind, f),
              ),
          ],
        ),
      ],
    );
  }
}

class _StuckCard extends ConsumerWidget {
  const _StuckCard(this.d);
  final ReportData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = requestLabels(ref);
    return ReportCard(
      title: tr('الأطول تعطلًا'),
      subtitle: tr('المتأخرة أولًا ثم الأقدم تحديثًا'),
      child: d.stuck.isEmpty
          ? mutedText(tr('لا توجد طلبات مفتوحة'))
          : Column(
              children: [
                for (final s in d.stuck)
                  ReportRowTile(
                    title: '#${s['number']} · ${s['title']}',
                    subtitle: [
                      if (s['client'] != null) '${s['client']}',
                      if (s['assignee'] != null) '${s['assignee']}',
                      statusName('${s['status']}', labels),
                    ].join(' · '),
                    trailing: s['overdue_days'] != null
                        ? Pill.urgent(tr('متأخر {0} يوم', [s['overdue_days']]))
                        : Pill.neutral(tr('بلا تحديث {0} يوم', [s['idle_days']])),
                    onTap: () => context.go('/requests/${s['id']}'),
                  ),
              ],
            ),
    );
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard(this.d);
  final ReportData d;

  @override
  Widget build(BuildContext context) {
    final s = d.services;
    final maxDays = s.fold<num>(1, (a, e) => ReportData.n(e['avg_days']) > a ? ReportData.n(e['avg_days']) : a);
    return ReportCard(
      title: tr('حسب نوع الخدمة'),
      subtitle: tr('الطلبات الجديدة في الفترة ومتوسط مدة الإنجاز (آخر ٦ أشهر)'),
      child: s.isEmpty
          ? mutedText(tr('لا توجد بيانات'))
          : Column(
              children: [
                for (final e in s)
                  ChartTip(
                    message: [
                      serviceName('${e['name']}'),
                      tr('طلبات جديدة في الفترة: {0}', [fmtNum(ReportData.n(e['count']))]),
                      if (ReportData.n(e['value']) > 0) tr('القيمة التقديرية: {0}', [moneyLabel(ReportData.n(e['value']))]),
                      tr('متوسط الإنجاز (آخر ٦ أشهر): {0}', [fmtDays(ReportData.nn(e['avg_days']))]),
                    ].join('\n'),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(serviceName('${e['name']}'),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(fmtNum(ReportData.n(e['count'])),
                              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          flex: 4,
                          child: ProgressBar(
                            ratio: ReportData.n(e['avg_days']) / maxDays,
                            color: ChartColors.blue,
                            trackColor: AppColors.divider,
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(fmtDays(ReportData.nn(e['avg_days'])),
                              textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                      ],
                    ),
                  ),
                  ),
              ],
            ),
    );
  }
}

// =====================================================================
// الطلبات
// =====================================================================
class _RequestsTab extends StatelessWidget {
  const _RequestsTab(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context) {
    final k = d.kpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(height: 100, children: [
          KpiCard(label: tr('مفتوحة الآن'), info: kpiInfo('open'), value: fmtNum(ReportData.n(k['open'])), onTap: () => openDrill(context, 'open', f)),
          KpiCard(
            label: tr('طلبات جديدة'), info: kpiInfo('new'), prev: fmtNum(ReportData.n(k['new_prev'])),
            value: fmtNum(ReportData.n(k['new'])),
            change: changeOf(ReportData.nn(k['new']), ReportData.nn(k['new_prev'])),
            onTap: () => openDrill(context, 'new', f),
          ),
          KpiCard(
            label: tr('طلبات منجزة'), info: kpiInfo('closed'), prev: fmtNum(ReportData.n(k['closed_prev'])),
            value: fmtNum(ReportData.n(k['closed'])),
            change: changeOf(ReportData.nn(k['closed']), ReportData.nn(k['closed_prev'])),
            onTap: () => openDrill(context, 'closed', f),
          ),
          KpiCard(
            label: tr('متأخرة'), info: kpiInfo('overdue'),
            value: fmtNum(ReportData.n(d.alerts['overdue'])),
            color: ChartColors.coral,
            onTap: () => openDrill(context, 'overdue', f),
          ),
        ]),
        const SizedBox(height: 14),
        TwoUp(_StatusCard(d, f), _OnTimeCard(d)),
        const SizedBox(height: 14),
        _ServicesCard(d),
        const SizedBox(height: 14),
        _StuckCard(d),
      ],
    );
  }
}

// =====================================================================
// الفريق
// =====================================================================
class _TeamTab extends StatelessWidget {
  const _TeamTab(this.d, this.f, {required this.onMember});
  final ReportData d;
  final ReportFilter f;
  final ValueChanged<String> onMember;

  @override
  Widget build(BuildContext context) {
    final team = d.team.where((t) => ReportData.n(t['open_tasks']) + ReportData.n(t['done_tasks']) + ReportData.n(t['open_requests']) > 0).toList();
    final maxLoad = team.fold<num>(1, (a, t) {
      final v = ReportData.n(t['open_tasks']) + ReportData.n(t['open_requests']);
      return v > a ? v : a;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WorkloadCard(),
        const SizedBox(height: 14),
        ReportCard(
          title: tr('توزيع العمل الحالي'),
          subtitle: tr('المهام والطلبات المفتوحة لكل عضو'),
          trailing: Legend([(tr('مهام'), ChartColors.green), (tr('متأخرة'), ChartColors.coral), (tr('طلبات'), ChartColors.blue)]),
          child: team.isEmpty
              ? mutedText(tr('لا توجد بيانات'))
              : Column(
                  children: [
                    for (final t in team)
                      InkWell(
                        onTap: () => openDrill(context, 'member_tasks', f, member: '${t['id']}', title: tr('مهام {0}', [t['name']])),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Avatar(_initial('${t['name']}'), size: 30, imageUrl: t['avatar_url'] as String?),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 90,
                                child: Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              ),
                              Expanded(
                                child: LayoutBuilder(builder: (context, c) {
                                  final open = ReportData.n(t['open_tasks']);
                                  final late = ReportData.n(t['overdue_tasks']);
                                  final req = ReportData.n(t['open_requests']);
                                  final w = c.maxWidth * (open + req) / maxLoad;
                                  return Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: SizedBox(
                                      width: w < 6 ? 6 : w,
                                      child: StackedBar(
                                        height: 14,
                                        trackColor: AppColors.divider,
                                        parts: [(open - late, ChartColors.green), (late, ChartColors.coral), (req, ChartColors.blue)],
                                        tips: [
                                          tr('{0} مهام مفتوحة في موعدها', [fmtNum(open - late)]),
                                          tr('{0} مهام متأخرة', [fmtNum(late)]),
                                          tr('{0} طلبات مفتوحة', [fmtNum(req)]),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(width: 8),
                              Text(fmtNum(ReportData.n(t['open_tasks']) + ReportData.n(t['open_requests'])),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _TeamTable(d, f, onMember: onMember),
      ],
    );
  }
}

String _initial(String name) => name.isEmpty ? '؟' : name.characters.first;

class _TeamTable extends StatelessWidget {
  const _TeamTable(this.d, this.f, {this.onMember});
  final ReportData d;
  final ReportFilter f;
  final ValueChanged<String>? onMember;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600);
    Widget cell(String s, {Color? color, bool bold = false}) => Expanded(
          flex: 2,
          child: Text(s,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        );
    return ReportCard(
      title: tr('أداء الفريق في الفترة'),
      child: d.team.isEmpty
          ? mutedText(tr('لا توجد بيانات'))
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(flex: 4, child: Text(tr('العضو'), style: head)),
                    Expanded(flex: 2, child: Text(tr('منجزة'), style: head, textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(tr('في الموعد'), style: head, textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(tr('متأخرة'), style: head, textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(tr('متوسط المدة'), style: head, textAlign: TextAlign.center)),
                    if (onMember != null) const SizedBox(width: 40),
                  ],
                ),
                const Divider(height: 16),
                for (final t in d.team)
                  InkWell(
                    onTap: () => openDrill(context, 'member_tasks', f, member: '${t['id']}', title: tr('مهام {0}', [t['name']])),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          cell(fmtNum(ReportData.n(t['done_tasks'])), bold: true),
                          () {
                            final v = ReportData.nn(t['on_time']);
                            return cell(fmtPct(v),
                                color: v == null ? AppColors.muted : (v >= 85 ? AppColors.done : v >= 70 ? AppColors.waiting : AppColors.urgent),
                                bold: true);
                          }(),
                          cell(fmtNum(ReportData.n(t['overdue_tasks'])),
                              color: ReportData.n(t['overdue_tasks']) > 0 ? AppColors.urgent : AppColors.muted),
                          cell(fmtDays(ReportData.nn(t['avg_days'])), color: AppColors.muted),
                          if (onMember != null)
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                tooltip: tr('تقرير العضو'),
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.insights_outlined, size: 20, color: AppColors.accentText),
                                onPressed: () => onMember!('${t['id']}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// =====================================================================
// المالية
// =====================================================================
class _FinanceTab extends StatelessWidget {
  const _FinanceTab(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context) {
    final fin = d.finance;
    if (fin == null) return EmptyState(tr('ليست لديك صلاحية المالية'), icon: Icons.lock_outline);
    final monthly = d.listOf(fin, 'monthly');
    final aging = fin['aging'] is Map ? Map<String, dynamic>.from(fin['aging'] as Map) : const <String, dynamic>{};
    final q = fin['quotes'] is Map ? Map<String, dynamic>.from(fin['quotes'] as Map) : const <String, dynamic>{};
    final qTotal = ReportData.n(q['total']), qAcc = ReportData.n(q['accepted']);
    final late = d.listOf(fin, 'late');
    final agingParts = [
      (tr('٠–٣٠ يومًا'), ReportData.n(aging['a0_30']), ChartColors.green),
      (tr('٣١–٦٠ يومًا'), ReportData.n(aging['a31_60']), ChartColors.amber),
      (tr('أكثر من ٦٠'), ReportData.n(aging['a60']), ChartColors.coral),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(height: 104, wide: 3, children: [
          KpiCard(
            label: tr('المحصّل في الفترة'), info: kpiInfo('collected'), prev: moneyLabel(ReportData.n(fin['collected_prev'])),
            value: moneyCompact(ReportData.n(fin['collected'])),
            change: changeOf(ReportData.nn(fin['collected']), ReportData.nn(fin['collected_prev'])),
            color: ChartColors.blue,
            spark: [for (final m in monthly) ReportData.n(m['collected'])],
          ),
          KpiCard(label: tr('المفوتر في الفترة'), info: kpiInfo('billed'), value: moneyCompact(ReportData.n(fin['billed'])), note: tr('ر.س')),
          KpiCard(
            label: tr('المستحق على العملاء'), info: kpiInfo('due'),
            value: moneyCompact(ReportData.n(fin['due'])),
            note: tr('ر.س'),
            color: ChartColors.coral,
            onTap: () => openDrill(context, 'late_invoices', f),
          ),
        ]),
        const SizedBox(height: 14),
        ReportCard(
          title: tr('المفوتر والمحصّل · آخر ٦ أشهر'),
          trailing: Legend([(tr('مفوتر'), ChartColors.slate), (tr('محصّل'), ChartColors.blue)]),
          child: monthly.isEmpty
              ? mutedText(tr('لا توجد بيانات'))
              : PairedColumns(
                  height: 140,
                  labels: [for (final m in monthly) _monthLabel('${m['month']}')],
                  a: [for (final m in monthly) ReportData.n(m['collected'])],
                  b: [for (final m in monthly) ReportData.n(m['billed'])],
                  colorA: ChartColors.blue,
                  colorB: ChartColors.slate.withValues(alpha: 0.55),
                  labelStyle: TextStyle(fontSize: 11, color: AppColors.muted),
                  tooltipBuilder: (i) {
                    final b = ReportData.n(monthly[i]['billed']), c = ReportData.n(monthly[i]['collected']);
                    return [
                      formatPattern('MMMM y', DateTime.tryParse('${monthly[i]['month']}') ?? DateTime.now()),
                      tr('مفوتر: {0}', [moneyLabel(b)]),
                      tr('محصّل: {0}', [moneyLabel(c)]),
                      if (b > 0) tr('نسبة التحصيل: {0}', [fmtPct(c * 100 / b)]),
                    ].join('\n');
                  },
                ),
        ),
        const SizedBox(height: 14),
        FunnelCard(filter: f),
        const SizedBox(height: 14),
        TwoUp(
          ReportCard(
            title: tr('أعمار المستحقات'),
            child: Row(
              children: [
                DonutChart(
                  size: 120,
                  thickness: 16,
                  trackColor: AppColors.divider,
                  parts: [for (final p in agingParts) (p.$2, p.$3)],
                  tooltip: [
                    for (final p in agingParts)
                      shareTip(p.$1, p.$2, agingParts.fold<num>(0, (a, q) => a + q.$2), fmt: moneyLabel),
                  ].join('\n'),
                  center: Text(moneyCompact(agingParts.fold<num>(0, (a, p) => a + p.$2)),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in agingParts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 6),
                              Expanded(child: Text(p.$1, style: const TextStyle(fontSize: 12))),
                              Text(moneyCompact(p.$2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ReportCard(
            title: tr('تحويل عروض الأسعار'),
            subtitle: tr('آخر ٩٠ يومًا'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(qTotal == 0 ? '—' : fmtPct(qAcc * 100 / qTotal), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ProgressBar(ratio: qTotal == 0 ? 0 : qAcc / qTotal, color: ChartColors.green, height: 10, trackColor: AppColors.divider),
                const SizedBox(height: 6),
                Text(tr('{0} مقبول من {1} عرض', [fmtNum(qAcc), fmtNum(qTotal)]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                if (d.alerts['quotes_no_reply'] != null && ReportData.n(d.alerts['quotes_no_reply']) > 0)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => openDrill(context, 'quotes_no_reply', f),
                    icon: const Icon(Icons.hourglass_bottom, size: 16),
                    label: Text(tr('{0} بلا رد', [fmtNum(ReportData.n(d.alerts['quotes_no_reply']))])),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        ReportCard(
          title: tr('الأكثر تأخرًا في السداد'),
          trailing: late.isEmpty ? null : TextButton(onPressed: () => openDrill(context, 'late_invoices', f), child: Text(tr('عرض الكل'))),
          child: late.isEmpty
              ? mutedText(tr('لا توجد فواتير متأخرة'))
              : Column(
                  children: [
                    for (final l in late)
                      ReportRowTile(
                        title: '${l['client']}',
                        subtitle: '${l['number']}',
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(moneyLabel(ReportData.n(l['remaining'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(tr('متأخرة {0} يوم', [l['days']]), style: TextStyle(fontSize: 11, color: AppColors.urgent)),
                          ],
                        ),
                        onTap: () => context.go('/more/finance'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _monthLabel(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : formatPattern('MMM', d);
}

// =====================================================================
// العملاء والاجتماعات
// =====================================================================
class _ClientsTab extends StatelessWidget {
  const _ClientsTab(this.d, this.f);
  final ReportData d;
  final ReportFilter f;

  @override
  Widget build(BuildContext context) {
    final c = d.clients ?? const <String, dynamic>{};
    final top = d.listOf(c, 'top');
    final idle = d.listOf(c, 'idle');
    final k = d.kpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(height: 100, wide: 3, children: [
          KpiCard(label: tr('عملاء نشطون'), info: kpiInfo('active_clients'), value: fmtNum(ReportData.n(c['active'])), note: tr('تعامل خلال ٦٠ يومًا'), onTap: () => context.go('/more/clients')),
          KpiCard(
            label: tr('عملاء جدد'), info: kpiInfo('new_clients'), prev: fmtNum(ReportData.n(k['new_clients_prev'])),
            value: fmtNum(ReportData.n(k['new_clients'])),
            change: changeOf(ReportData.nn(k['new_clients']), ReportData.nn(k['new_clients_prev'])),
          ),
          KpiCard(label: tr('بلا تواصل +٦٠ يومًا'), info: kpiInfo('idle_clients'), value: fmtNum(idle.length), color: ChartColors.amber),
        ]),
        const SizedBox(height: 14),
        const ClientTiersCard(),
        const SizedBox(height: 14),
        TwoUp(
          ReportCard(
            title: d.canFinance ? tr('أعلى العملاء قيمة · ١٢ شهرًا') : tr('أكثر العملاء طلبات'),
            child: top.isEmpty
                ? mutedText(tr('لا توجد بيانات'))
                : Column(
                    children: [
                      for (final t in top)
                        ReportRowTile(
                          title: '${t['name']}',
                          subtitle: tr('{0} طلب', [t['requests']]),
                          trailing: t['value'] == null
                              ? null
                              : Text(moneyCompact(ReportData.n(t['value'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => context.go('/more/clients/${t['id']}'),
                        ),
                    ],
                  ),
          ),
          ReportCard(
            title: tr('عملاء يحتاجون تواصلًا'),
            subtitle: tr('لا طلبات ولا اجتماعات منذ أكثر من ٦٠ يومًا'),
            child: idle.isEmpty
                ? mutedText(tr('كل العملاء على تواصل'))
                : Column(
                    children: [
                      for (final i in idle.take(8))
                        ReportRowTile(
                          title: '${i['name']}',
                          trailing: Pill.waiting(tr('منذ {0} يوم', [i['days']])),
                          onTap: () => context.go('/more/clients/${i['id']}'),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        _MeetingsBlock(d),
      ],
    );
  }
}

class _MeetingsBlock extends StatelessWidget {
  const _MeetingsBlock(this.d);
  final ReportData d;

  @override
  Widget build(BuildContext context) {
    final m = d.meetings;
    final parts = [
      (tr('عُقد'), ReportData.n(m['done']), ChartColors.green),
      (tr('مجدول'), ReportData.n(m['scheduled']), ChartColors.blue),
      (tr('مؤجل'), ReportData.n(m['postponed']), ChartColors.amber),
      (tr('أُلغي'), ReportData.n(m['cancelled']), ChartColors.coral),
    ];
    final total = parts.fold<num>(0, (a, p) => a + p.$2);
    final dt = d.decisionTasks, pr = d.promises;
    final dtTotal = ReportData.n(dt['total']), dtDone = ReportData.n(dt['done']);
    final prTotal = ReportData.n(pr['total']), prOk = ReportData.n(pr['on_time']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportCard(
          title: tr('الاجتماعات في الفترة'),
          trailing: Text(fmtNum(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          child: total == 0
              ? mutedText(tr('لا توجد اجتماعات في هذه الفترة'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StackedBar(
                      parts: [for (final p in parts) (p.$2, p.$3)],
                      tips: [for (final p in parts) shareTip(p.$1, p.$2, total)],
                      height: 18,
                      trackColor: AppColors.divider,
                    ),
                    const SizedBox(height: 10),
                    Legend([for (final p in parts) ('${p.$1} ${fmtNum(p.$2)}', p.$3)]),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        TwoUp(
          _RatioCard(
            title: tr('تنفيذ قرارات الاجتماعات'),
            done: dtDone,
            total: dtTotal,
            caption: tr('{0} من {1} مهمة من المحاضر أُنجزت', [fmtNum(dtDone), fmtNum(dtTotal)]),
            onTap: () => context.go('/tasks'),
          ),
          _RatioCard(
            title: tr('الوفاء بالوعود للعملاء'),
            done: prOk,
            total: prTotal,
            caption: tr('{0} من {1} وعدًا نُفّذ في موعده', [fmtNum(prOk), fmtNum(prTotal)]),
            onTap: () => context.go('/more/followups'),
          ),
        ),
      ],
    );
  }
}

class _RatioCard extends StatelessWidget {
  const _RatioCard({required this.title, required this.done, required this.total, required this.caption, this.onTap});
  final String title;
  final num done;
  final num total;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = total == 0 ? null : done * 100 / total;
    final color = r == null ? ChartColors.slate : (r >= 85 ? ChartColors.green : r >= 65 ? ChartColors.amber : ChartColors.coral);
    return CardBox(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(fmtPct(r), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ProgressBar(ratio: r == null ? 0 : r / 100, color: color, height: 10, trackColor: AppColors.divider),
          const SizedBox(height: 6),
          Text(total == 0 ? tr('لا توجد بيانات') : caption, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

// =====================================================================
// الأهداف الشهرية
// =====================================================================
class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(DateTime.now());
    final start = DateTime(today.year, today.month);
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final pace = today.day / daysInMonth;
    final data = ref.watch(reportDashboardProvider((start, today, null)));
    return AsyncBody<ReportData>(
      value: data,
      onRetry: () => ref.invalidate(reportDashboardProvider((start, today, null))),
      builder: (d) {
        num? actual(GoalMetric g) => switch (g.key) {
              'requests_closed' => ReportData.nn(d.kpi['closed']),
              'collected' => ReportData.nn(d.finance?['collected']),
              'on_time' => ReportData.nn(d.kpi['on_time']),
              'new_clients' => ReportData.nn(d.kpi['new_clients']),
              'tasks_done' => ReportData.nn(d.kpi['tasks_done']),
              'meetings_held' => ReportData.nn(d.kpi['meetings_held']),
              _ => null,
            };
        String fmt(GoalMetric g, num? v) => v == null ? '—' : g.percent ? fmtPct(v) : g.money ? moneyLabel(v) : fmtNum(v);
        final metrics = GoalMetric.all.where((g) => g.key != 'collected' || d.canFinance).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReportCard(
              title: tr('أهداف {0}', [formatPattern('MMMM y', today)]),
              subtitle: tr('مضى {0}٪ من الشهر', [(pace * 100).round()]),
              child: Column(
                children: [
                  for (final g in metrics)
                    () {
                      final target = ReportData.nn(d.goals[g.key]);
                      final v = actual(g);
                      final ratio = target == null || v == null ? 0.0 : (v / target).toDouble();
                      final onTrack = g.percent ? ratio >= 1 : ratio >= pace;
                      return InkWell(
                        onTap: () => _editGoal(context, ref, start, g, target),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(tr(g.labelAr), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                  if (target == null)
                                    Text(tr('أضف هدفًا'), style: TextStyle(fontSize: 12, color: AppColors.accentText, fontWeight: FontWeight.w600))
                                  else ...[
                                    Text(fmt(g, v), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                    Text(tr(' / {0}', [fmt(g, target)]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                  ],
                                ],
                              ),
                              if (target != null) ...[
                                const SizedBox(height: 8),
                                ProgressBar(
                                  ratio: ratio,
                                  height: 10,
                                  trackColor: AppColors.divider,
                                  color: ratio >= 1 ? ChartColors.green : onTrack ? ChartColors.blue : ChartColors.amber,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ratio >= 1
                                      ? tr('تحقق الهدف 🎯')
                                      : onTrack
                                          ? tr('على المسار · {0}٪', [(ratio * 100).round()])
                                          : tr('أبطأ من وتيرة الشهر · {0}٪', [(ratio * 100).round()]),
                                  style: TextStyle(fontSize: 11, color: onTrack || ratio >= 1 ? AppColors.done : AppColors.waiting, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(tr('اضغط على أي مؤشر لتعديل هدفه. تظهر الأهداف أيضًا على شاشة المكتب.'),
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        );
      },
    );
  }

  Future<void> _editGoal(BuildContext context, WidgetRef ref, DateTime month, GoalMetric g, num? current) async {
    final repo = ref.read(sectionRepoProvider);
    if (current != null) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('تعديل الهدف')), onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text(tr('حذف الهدف'), style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      );
      if (action == null || !context.mounted) return;
      if (action == 'delete') {
        if (await runAction(context, () => repo.deleteGoal(month, g.key), success: tr('حُذف الهدف'))) {
          ref.invalidate(reportDashboardProvider);
        }
        return;
      }
    }
    if (!context.mounted) return;
    final v = await promptNumber(
      context,
      tr('هدف {0}', [tr(g.labelAr)]),
      label: g.percent ? tr('النسبة المستهدفة ٪') : g.money ? tr('المبلغ المستهدف (ر.س)') : tr('العدد المستهدف هذا الشهر'),
      initial: current,
    );
    if (v == null || v <= 0 || !context.mounted) return;
    if (await runAction(context, () => repo.saveGoal(month, g.key, v), success: tr('حُفظ الهدف'))) {
      ref.invalidate(reportDashboardProvider);
    }
  }
}
