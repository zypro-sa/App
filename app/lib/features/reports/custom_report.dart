import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/report_models.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import 'report_common.dart';

// =====================================================================
// تعريفات المصادر والتجميع والمقاييس
// =====================================================================
class CustomDefs {
  static List<(String, String)> sources({required bool finance}) => [
        ('requests', tr('الطلبات')),
        ('tasks', tr('المهام')),
        ('meetings', tr('الاجتماعات')),
        ('clients', tr('العملاء')),
        ('followups', tr('المتابعات')),
        if (finance) ('invoices', tr('الفواتير')),
        if (finance) ('quotes', tr('عروض الأسعار')),
      ];

  static String sourceName(String s) =>
      sources(finance: true).where((e) => e.$1 == s).map((e) => e.$2).firstOrNull ?? s;

  static String personLabel(String src) => switch (src) {
        'requests' => tr('المسؤول'),
        'tasks' => tr('المسند إليه'),
        'clients' => tr('مدير الحساب'),
        'followups' => tr('صاحب المتابعة'),
        _ => tr('المنشئ'),
      };

  static List<(String, String)> groups(String src) => [
        ('none', tr('بلا تجميع')),
        ('status', tr('الحالة')),
        ('person', personLabel(src)),
        if (!{'clients', 'followups'}.contains(src)) ('client', tr('العميل')),
        if (src == 'requests' || src == 'tasks') ('priority', tr('الأولوية')),
        if (src == 'requests') ('service', tr('نوع الخدمة')),
        if (src == 'requests') ('type', tr('قناة الورود')),
        if (src == 'meetings') ('type', tr('نوع الاجتماع')),
        if (src == 'clients') ('type', tr('نوع العميل')),
        if (src == 'clients') ('city', tr('المدينة')),
        if (src == 'clients') ('sector', tr('القطاع')),
        if (src == 'followups') ('type', tr('الاتجاه')),
        ('day', tr('اليوم')),
        ('week', tr('الأسبوع')),
        ('month', tr('الشهر')),
        ('weekday', tr('يوم الأسبوع')),
      ];

  static List<(String, String)> metrics(String src) => [
        ('count', tr('العدد')),
        if ({'requests', 'invoices', 'quotes'}.contains(src)) ('sum_value', src == 'requests' ? tr('مجموع القيمة التقديرية') : tr('مجموع القيمة')),
        if ({'requests', 'invoices', 'quotes'}.contains(src)) ('avg_value', tr('متوسط القيمة')),
        if (src == 'invoices') ('sum_due', tr('المتبقي للتحصيل')),
        if (src == 'requests' || src == 'tasks') ('avg_days', tr('متوسط مدة الإنجاز')),
        if ({'requests', 'tasks', 'followups'}.contains(src)) ('on_time', tr('نسبة الالتزام بالموعد')),
      ];

  static List<(String, String)> bases(String src) => switch (src) {
        'requests' => [('created', tr('تاريخ الإنشاء')), ('closed', tr('تاريخ الإغلاق')), ('due', tr('موعد التسليم'))],
        'tasks' => [('created', tr('تاريخ الإنشاء')), ('closed', tr('تاريخ الإنجاز')), ('due', tr('الموعد'))],
        'meetings' => [('start', tr('موعد الاجتماع')), ('created', tr('تاريخ الإنشاء'))],
        'invoices' => [('issue', tr('تاريخ الإصدار')), ('due', tr('تاريخ الاستحقاق'))],
        'quotes' => [('sent', tr('تاريخ الإرسال')), ('created', tr('تاريخ الإنشاء'))],
        'followups' => [('due', tr('الموعد')), ('created', tr('تاريخ الإنشاء'))],
        _ => [('created', tr('تاريخ الإضافة'))],
      };

  static List<(String, String)> periods() => [
        ('7', tr('٧ أيام')),
        ('30', tr('٣٠ يومًا')),
        ('90', tr('٩٠ يومًا')),
        ('365', tr('سنة')),
        ('month', tr('هذا الشهر')),
        ('year', tr('هذه السنة')),
        ('custom', tr('فترة مخصصة')),
      ];

  static List<(String, String, IconData)> views() => [
        ('bar', tr('أشرطة'), Icons.bar_chart),
        ('line', tr('خط زمني'), Icons.show_chart),
        ('donut', tr('دائري'), Icons.donut_large),
        ('table', tr('جدول'), Icons.table_rows_outlined),
        ('number', tr('رقم'), Icons.looks_one_outlined),
      ];

  /// قيم الحالة لكل مصدر
  static List<(String, String)> statuses(String src, Map<String, StatusLabel> reqLabels) => switch (src) {
        'requests' => [for (final s in RequestStatus.values) (s.db, statusName(s.db, reqLabels))],
        'tasks' => [for (final s in TaskStatus.values) (s.db, s.label)],
        'meetings' => [for (final s in MeetingStatus.values) (s.db, s.label)],
        'invoices' => [for (final s in InvoiceStatus.values) (s.db, s.label)],
        'quotes' => [for (final s in QuoteStatus.values) (s.db, s.label)],
        'clients' => [('lead', tr('محتمل')), ('active', tr('نشط')), ('inactive', tr('غير نشط'))],
        'followups' => [('open', tr('مفتوحة')), ('done', tr('منجزة')), ('snoozed', tr('مؤجلة'))],
        _ => const [],
      };

  static String typeLabel(String src, String code) => switch (src) {
        'requests' => switch (code) {
            'email' => tr('بريد'),
            'call' => tr('مكالمة'),
            'whatsapp' => tr('واتساب'),
            'meeting' => tr('اجتماع'),
            'website' => tr('الموقع'),
            _ => code,
          },
        'meetings' => MeetingType.from(code).label,
        'clients' => switch (code) {
            'company' => tr('شركة'),
            'government' => tr('جهة حكومية'),
            'individual' => tr('فرد'),
            _ => code,
          },
        'followups' => FollowupDirection.from(code).label,
        _ => code,
      };

  static bool isMoney(String metric) => metric == 'sum_value' || metric == 'sum_due' || metric == 'avg_value';
  static bool isTime(String group) => {'day', 'week', 'month', 'weekday'}.contains(group);
}

/// اسم الصف المعروض
String customRowLabel(CustomConfig c, CustomRow r, Map<String, StatusLabel> reqLabels) {
  if (c.groupBy == 'none') return tr('الإجمالي');
  if (r.key == '—') return tr('غير محدد');
  switch (c.groupBy) {
    case 'status':
      return CustomDefs.statuses(c.source, reqLabels).where((e) => e.$1 == r.key).map((e) => e.$2).firstOrNull ?? r.key;
    case 'priority':
      return Priority.from(r.key).label;
    case 'type':
      return CustomDefs.typeLabel(c.source, r.key);
    case 'day':
      final d = DateTime.tryParse(r.key);
      return d == null ? r.key : formatShortDate(d);
    case 'week':
      final d = DateTime.tryParse(r.key);
      return d == null ? r.key : tr('أسبوع {0}', [formatShortDate(d)]);
    case 'month':
      final d = DateTime.tryParse('${r.key}-01');
      return d == null ? r.key : formatPattern('MMM y', d);
    case 'weekday':
      final n = int.tryParse(r.key) ?? 1;
      return formatPattern('EEEE', DateTime(2024, 1, n)); // ١ يناير ٢٠٢٤ يوم اثنين
  }
  return r.label;
}

String customValue(String metric, num? v) {
  if (v == null) return '—';
  if (CustomDefs.isMoney(metric)) return moneyLabel(v);
  if (metric == 'avg_days') return fmtDays(v);
  if (metric == 'on_time') return fmtPct(v);
  return fmtNum(v);
}

String customValueShort(String metric, num? v) {
  if (v == null) return '—';
  if (CustomDefs.isMoney(metric)) return moneyCompact(v);
  return customValue(metric, v);
}

const customPalette = [
  ChartColors.green,
  ChartColors.blue,
  ChartColors.amber,
  ChartColors.coral,
  Color(0xFF8E7CC3),
  Color(0xFF4FB3BF),
  Color(0xFFD67BA8),
  ChartColors.slate,
];

/// ملخص نصي للإعدادات (يظهر تحت عنوان التقرير)
String customSummary(CustomConfig c) {
  final g = CustomDefs.groups(c.source).where((e) => e.$1 == c.groupBy).map((e) => e.$2).firstOrNull ?? '';
  final m = CustomDefs.metrics(c.source).where((e) => e.$1 == c.metric).map((e) => e.$2).firstOrNull ?? '';
  final p = CustomDefs.periods().where((e) => e.$1 == c.period).map((e) => e.$2).firstOrNull ?? '';
  final (f, t) = c.range;
  final range = c.period == 'custom' ? tr('{0} – {1}', [formatShortDate(f), formatShortDate(t)]) : p;
  return [CustomDefs.sourceName(c.source), m, if (c.groupBy != 'none') tr('حسب {0}', [g]), range].join(' · ');
}

// =====================================================================
// عرض نتيجة التقرير
// =====================================================================
class CustomReportView extends ConsumerWidget {
  const CustomReportView({super.key, required this.config, this.height = 220});
  final CustomConfig config;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(customReportProvider(config.key));
    return AsyncBody<CustomResult>(
      value: res,
      onRetry: () => ref.invalidate(customReportProvider(config.key)),
      builder: (r) => CustomResultView(config: config, result: r, height: height),
    );
  }
}

class CustomResultView extends ConsumerWidget {
  const CustomResultView({super.key, required this.config, required this.result, this.height = 220, this.dark = false});
  final CustomConfig config;
  final CustomResult result;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = requestLabels(ref);
    final rows = result.rows;
    final m = config.metric;
    final muted = dark ? const Color(0xFFA3A6B3) : AppColors.muted;
    final ink = dark ? const Color(0xFFECECF1) : AppColors.ink;
    final track = dark ? const Color(0xFF2C2C36) : AppColors.divider;
    final scale = dark ? height / 220 : 1.0;
    final totalTxt = customValue(m, result.totalValue);

    if (config.view == 'number' || rows.isEmpty) {
      return SizedBox(
        height: config.view == 'number' ? (height * 0.6).clamp(110, 600).toDouble() : 110,
        child: Center(
          child: rows.isEmpty && result.totalCount == 0
              ? Text(tr('لا توجد بيانات في هذه الفترة'), style: TextStyle(color: muted, fontSize: 13 * scale))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(totalTxt, style: TextStyle(fontSize: 44 * scale, fontWeight: FontWeight.w800, color: ink)),
                    ),
                    if (m != 'count') Text(tr('من {0} سجل', [fmtNum(result.totalCount)]), style: TextStyle(color: muted, fontSize: 13 * scale)),
                  ],
                ),
        ),
      );
    }

    final values = [for (final r in rows) r.value ?? 0];
    final names = [for (final r in rows) customRowLabel(config, r, labels)];
    final maxV = values.fold<num>(0, (a, b) => b > a ? b : a);
    final sum = values.fold<num>(0, (a, b) => a + b);
    final additive = m == 'count' || m == 'sum_value' || m == 'sum_due';
    String tip(int i) => [
          names[i],
          customValue(m, rows[i].value),
          if (additive && sum > 0) tr('{0} من الإجمالي', [fmtPct(values[i] * 100 / sum)]),
          if (m != 'count') tr('{0} سجل', [fmtNum(rows[i].count)]),
        ].join('\n');

    switch (config.view) {
      case 'line':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AreaChart(
              values: values,
              height: height,
              gridColor: track,
              color: ChartColors.green,
              strokeWidth: 3 * scale,
              tooltipBuilder: tip,
              semanticLabel: names.join(tr('، ')),
            ),
            SizedBox(height: 6 * scale),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(names.first, style: TextStyle(fontSize: 11 * scale, color: muted)),
                  Text(tr('الإجمالي: {0}', [totalTxt]), style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w700, color: ink)),
                  Text(names.last, style: TextStyle(fontSize: 11 * scale, color: muted)),
                ],
              ),
            ),
          ],
        );
      case 'donut':
        final parts = [for (var i = 0; i < rows.length; i++) (values[i], customPalette[i % customPalette.length])];
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length && i < 8; i++)
              ChartTip(
                message: tip(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 3 * scale),
                  child: Row(
                    children: [
                      Container(
                        width: 10 * scale,
                        height: 10 * scale,
                        decoration: BoxDecoration(color: parts[i].$2, borderRadius: BorderRadius.circular(3)),
                      ),
                      SizedBox(width: 6 * scale),
                      Expanded(
                        child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12 * scale, color: ink)),
                      ),
                      Text(customValueShort(m, values[i]), style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w700, color: ink)),
                    ],
                  ),
                ),
              ),
            if (rows.length > 8) Text(tr('و{0} أخرى', [rows.length - 8]), style: TextStyle(fontSize: 11 * scale, color: muted)),
          ],
        );
        final donut = DonutChart(
          size: (height * 0.75).clamp(100, 500).toDouble(),
          thickness: 18 * scale,
          trackColor: track,
          parts: parts,
          tooltip: [for (var i = 0; i < rows.length && i < 8; i++) '${names[i]}: ${customValueShort(m, values[i])}'].join('\n'),
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(customValueShort(m, result.totalValue), style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w800, color: ink)),
              Text(tr('الإجمالي'), style: TextStyle(fontSize: 11 * scale, color: muted)),
            ],
          ),
        );
        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 420) return Column(children: [donut, SizedBox(height: 12 * scale), legend]);
          return Row(children: [donut, SizedBox(width: 20 * scale), Expanded(child: legend)]);
        });
      case 'table':
        final head = TextStyle(fontSize: 11 * scale, color: muted, fontWeight: FontWeight.w600);
        return Column(
          children: [
            Row(
              children: [
                Expanded(flex: 5, child: Text(tr('البند'), style: head)),
                Expanded(flex: 3, child: Text(tr('القيمة'), style: head, textAlign: TextAlign.end)),
                Expanded(flex: 2, child: Text(tr('السجلات'), style: head, textAlign: TextAlign.end)),
                if (additive) Expanded(flex: 2, child: Text(tr('النسبة'), style: head, textAlign: TextAlign.end)),
              ],
            ),
            Divider(height: 14 * scale, color: track),
            for (var i = 0; i < rows.length; i++)
              ChartTip(
                message: tip(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6 * scale),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13 * scale, color: ink))),
                      Expanded(
                        flex: 3,
                        child: Text(customValue(m, rows[i].value),
                            textAlign: TextAlign.end, style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(fmtNum(rows[i].count), textAlign: TextAlign.end, style: TextStyle(fontSize: 12 * scale, color: muted)),
                      ),
                      if (additive)
                        Expanded(
                          flex: 2,
                          child: Text(sum == 0 ? '—' : fmtPct(values[i] * 100 / sum),
                              textAlign: TextAlign.end, style: TextStyle(fontSize: 12 * scale, color: muted)),
                        ),
                    ],
                  ),
                ),
              ),
            Divider(height: 14 * scale, color: track),
            Row(
              children: [
                Expanded(flex: 5, child: Text(tr('الإجمالي'), style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink))),
                Expanded(
                  flex: 3,
                  child: Text(totalTxt, textAlign: TextAlign.end, style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w800, color: ink)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(fmtNum(result.totalCount), textAlign: TextAlign.end, style: TextStyle(fontSize: 12 * scale, color: muted)),
                ),
                if (additive) const Expanded(flex: 2, child: SizedBox()),
              ],
            ),
          ],
        );
      default: // bar
        final shown = rows.length > 12 && !dark ? 12 : (dark ? 8 : rows.length);
        return Column(
          children: [
            for (var i = 0; i < shown && i < rows.length; i++)
              ChartTip(
                message: tip(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 5 * scale),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110 * scale,
                        child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13 * scale, color: ink)),
                      ),
                      Expanded(
                        child: ProgressBar(
                          ratio: maxV == 0 ? 0 : values[i] / maxV,
                          color: customPalette[i % customPalette.length],
                          height: 14 * scale,
                          trackColor: track,
                        ),
                      ),
                      SizedBox(
                        width: 86 * scale,
                        child: Text(customValueShort(m, rows[i].value),
                            textAlign: TextAlign.end, style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink)),
                      ),
                    ],
                  ),
                ),
              ),
            if (rows.length > shown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('و{0} أخرى — اعرضه كجدول لرؤية الكل', [rows.length - shown]), style: TextStyle(fontSize: 11 * scale, color: muted)),
              ),
          ],
        );
    }
  }
}
