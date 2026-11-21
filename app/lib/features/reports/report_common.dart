import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/report_models.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// فترة التقرير ومن يخصه.
class ReportFilter {
  const ReportFilter({required this.from, required this.to, this.member});
  final DateTime from;
  final DateTime to;
  final String? member;

  (DateTime, DateTime, String?) get key => (from, to, member);

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get label => tr('{0} – {1}', [formatShortDate(from), formatShortDate(to)]);
}

final _int = NumberFormat('#,##0');
String fmtNum(num v) => _int.format(v);
String fmtPct(num? v) => v == null ? '—' : tr('{0}٪', [v.round()]);
String fmtDays(num? v) => v == null ? '—' : tr('{0} يوم', [v]);

/// التغير عن الفترة السابقة: (النص، هل هو جيد؟)
(String, bool)? changeOf(num? cur, num? prev, {bool lowerIsBetter = false, bool points = false}) {
  if (cur == null || prev == null) return null;
  if (points) {
    final d = (cur - prev).round();
    if (d == 0) return (tr('بلا تغيير'), true);
    return (tr('{0} {1} نقطة', [d > 0 ? '▲' : '▼', d.abs()]), lowerIsBetter ? d < 0 : d > 0);
  }
  if (prev == 0) return null;
  final p = ((cur - prev) / prev * 100).round();
  if (p == 0) return (tr('بلا تغيير'), true);
  return (tr('{0} {1}٪', [p > 0 ? '▲' : '▼', p.abs()]), lowerIsBetter ? p < 0 : p > 0);
}

// ---------------- حالات الطلبات ----------------
Map<String, StatusLabel> requestLabels(WidgetRef ref) => {
      for (final l in ref.watch(statusLabelsProvider(ConfigEntity.request)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };

Map<String, StatusLabel> requestLabelsNow(WidgetRef ref) => {
      for (final l in ref.read(statusLabelsProvider(ConfigEntity.request)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };

String statusName(String code, Map<String, StatusLabel> labels) =>
    labels[code]?.label ?? RequestStatus.from(code).label;

Color toneColor(String tone) => switch (tone) {
      'info' => ChartColors.blue,
      'waiting' => ChartColors.amber,
      'done' => ChartColors.green,
      'urgent' => ChartColors.coral,
      _ => ChartColors.slate,
    };

Color statusColor(String code, Map<String, StatusLabel> labels) {
  final c = labels[code]?.color;
  if (c != null) return toneColor(c);
  return switch (code) {
    'new' => ChartColors.blue,
    'in_progress' => ChartColors.green,
    'waiting_client' => ChartColors.amber,
    _ => ChartColors.slate,
  };
}

String serviceName(String s) => s == 'غير محدد' ? tr('غير محدد') : s;

/// ترجمة الشارة القادمة من report_list
String rowBadge(ReportRow r, Map<String, StatusLabel> labels) {
  final b = r.badge;
  if (RegExp(r'^[a-z_]+$').hasMatch(b)) return statusName(b, labels);
  if (L.isAr) return b;
  final pats = <RegExp, String>{
    RegExp(r'^متأخر (\d+) يوم$'): 'متأخر {0} يوم',
    RegExp(r'^(\d+) يوم بانتظار العميل$'): '{0} يوم بانتظار العميل',
    RegExp(r'^متبقٍ (.+)$'): 'متبقٍ {0}',
    RegExp(r'^منذ (\d+) يوم$'): 'منذ {0} يوم',
    RegExp(r'^متأخرة (\d+) يوم$'): 'متأخرة {0} يوم',
  };
  for (final e in pats.entries) {
    final m = e.key.firstMatch(b);
    if (m != null) return tr(e.value, [m.group(1)]);
  }
  return tr(b);
}

Pill tonePill(String tone, String label) => switch (tone) {
      'urgent' => Pill.urgent(label),
      'waiting' => Pill.waiting(label),
      'done' => Pill.done(label),
      _ => Pill.neutral(label),
    };

// ---------------- القوائم التفصيلية ----------------
/// عناوين أنواع القوائم
String drillTitle(String kind) => switch (kind) {
      'overdue' => tr('طلبات متأخرة'),
      'waiting_long' => tr('بانتظار العميل أكثر من أسبوع'),
      'closed' => tr('طلبات منجزة'),
      'open' => tr('طلبات مفتوحة'),
      'new' => tr('طلبات جديدة'),
      'unpaid_closed' => tr('منجزة ولم تُحصّل'),
      'quotes_no_reply' => tr('عروض أسعار بلا رد'),
      'late_invoices' => tr('فواتير متأخرة السداد'),
      'member_tasks' => tr('مهام العضو'),
      _ => tr('التفاصيل'),
    };

void openDrill(BuildContext context, String kind, ReportFilter f, {String? member, String? title}) {
  final m = member ?? f.member;
  context.push(Uri(path: '/more/reports/list', queryParameters: {
    'kind': kind,
    'from': ReportFilter.iso(f.from),
    'to': ReportFilter.iso(f.to),
    if (m != null) 'member': m,
    if (title != null) 'title': title,
  }).toString());
}

void openRow(BuildContext context, String kind, String id) {
  switch (kind) {
    case 'request':
      context.go('/requests/$id');
    case 'quote':
    case 'invoice':
      context.go('/more/finance');
    case 'client':
      context.go('/more/clients/$id');
    case 'task':
      context.go('/tasks');
  }
}

// ---------------- عناصر مشتركة ----------------
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.title, required this.child, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// بطاقة مؤشر: الرقم، التغير، وخط اتجاه — والضغط يفتح القائمة خلفه.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.change,
    this.spark,
    this.note,
    this.onTap,
    this.color = ChartColors.green,
  });
  final String label;
  final String value;
  final (String, bool)? change;
  final List<num>? spark;
  final String? note;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
              if (onTap != null) Icon(AppIcons.forward, size: 16, color: AppColors.faint),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ),
              ),
              if (spark != null && spark!.length > 1) Sparkline(spark!, color: color, width: 56, height: 22),
            ],
          ),
          Text(
            change?.$1 ?? note ?? ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: change == null ? AppColors.muted : (change!.$2 ? AppColors.done : AppColors.urgent),
            ),
          ),
        ],
      ),
    );
  }
}

/// شبكة متجاوبة: عمودان على الجوال، أربعة على الشاشات الواسعة.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.height = 112, this.wide = 4, this.narrow = 2});
  final List<Widget> children;
  final double height;
  final int wide;
  final int narrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? wide : narrow;
      const gap = 10.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, height: height, child: ch)],
      );
    });
  }
}

/// عمودان على الشاشات الواسعة، وفوق بعض على الجوال.
class TwoUp extends StatelessWidget {
  const TwoUp(this.a, this.b, {super.key});
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 720) return Column(children: [a, const SizedBox(height: 12), b]);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );
    });
  }
}

/// مفتاح لون صغير
class Legend extends StatelessWidget {
  const Legend(this.items, {super.key});
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.subtle)),
            ],
          ),
      ],
    );
  }
}

/// صف قابل للضغط: عنوان، وصف، وقيمة
class ReportRowTile extends StatelessWidget {
  const ReportRowTile({super.key, required this.title, this.subtitle, this.trailing, this.onTap, this.leading});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

Widget mutedText(String s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(s, style: TextStyle(color: AppColors.muted, fontSize: 13)),
    );

/// تنبيهات «تحتاج قرارك»: (العدد، النص، نوع القائمة، اللون)
List<(int, String, String, String)> decisionAlerts(ReportData d) {
  final a = d.alerts;
  final out = <(int, String, String, String)>[];
  final overdue = ReportData.n(a['overdue']).toInt();
  if (overdue > 0) {
    final maxD = ReportData.n(a['overdue_max_days']).toInt();
    out.add((overdue, tr('طلبات متأخرة · أقدمها {0} يوم', [maxD]), 'overdue', 'urgent'));
  }
  final waiting = ReportData.n(a['waiting_long']).toInt();
  if (waiting > 0) out.add((waiting, tr('بانتظار العميل أكثر من أسبوع'), 'waiting_long', 'waiting'));
  final unpaid = ReportData.n(a['unpaid_closed']).toInt();
  if (unpaid > 0) {
    out.add((unpaid, tr('منجزة ولم تُحصّل · {0}', [moneyLabel(ReportData.n(a['unpaid_closed_amount']))]), 'unpaid_closed', 'waiting'));
  }
  final quotes = ReportData.n(a['quotes_no_reply']).toInt();
  if (quotes > 0) out.add((quotes, tr('عروض أسعار بلا رد منذ ٣ أيام أو أكثر'), 'quotes_no_reply', 'neutral'));
  return out;
}

String moneyLabel(num v) => tr('{0} ر.س', [fmtNum(v)]);

/// اختصار المبالغ الكبيرة: ١٢٫٥ ألف
String moneyCompact(num v) {
  if (v.abs() >= 1000000) return tr('{0} مليون', [(v / 1000000).toStringAsFixed(1)]);
  if (v.abs() >= 10000) return tr('{0} ألف', [(v / 1000).toStringAsFixed(v.abs() >= 100000 ? 0 : 1)]);
  return fmtNum(v);
}

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key, required this.data, required this.filter});
  final ReportData data;
  final ReportFilter filter;

  @override
  Widget build(BuildContext context) {
    final items = decisionAlerts(data);
    return CardBox(
      padding: const EdgeInsets.all(16),
      borderColor: items.isEmpty ? AppColors.line : AppColors.urgentBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(items.isEmpty ? Icons.check_circle_outline : Icons.priority_high_rounded,
                  size: 20, color: items.isEmpty ? AppColors.done : AppColors.urgent),
              const SizedBox(width: 8),
              Text(tr('تحتاج قرارك'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty) mutedText(tr('لا شيء عالق الآن — كل شيء في مساره'))
          else
            for (final (n, text, kind, tone) in items)
              ReportRowTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: toneColor(tone).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                  child: Text(fmtNum(n), style: TextStyle(fontWeight: FontWeight.w700, color: toneColor(tone) == ChartColors.slate ? AppColors.subtle : toneColor(tone))),
                ),
                title: text,
                trailing: Icon(AppIcons.forward, color: AppColors.faint),
                onTap: () => openDrill(context, kind, filter),
              ),
        ],
      ),
    );
  }
}
