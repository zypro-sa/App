import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/report_models.dart';
import '../../data/section_models.dart';
import 'report_common.dart';

/// أسطر المؤشرات المشتركة بين التصديرات: (الاسم، الحالية، السابقة)
List<(String, String, String)> _kpiRows(ReportData d) {
  final k = d.kpi;
  String n(Object? v) => v == null ? '—' : fmtNum(ReportData.n(v));
  final rows = <(String, String, String)>[
    (tr('طلبات منجزة'), n(k['closed']), n(k['closed_prev'])),
    (tr('طلبات جديدة'), n(k['new']), n(k['new_prev'])),
    (tr('مفتوحة الآن'), n(k['open']), ''),
    (tr('الالتزام بالمواعيد'), fmtPct(ReportData.nn(k['on_time'])), fmtPct(ReportData.nn(k['on_time_prev']))),
    (tr('متوسط زمن الإنجاز'), fmtDays(ReportData.nn(k['avg_days'])), fmtDays(ReportData.nn(k['avg_days_prev']))),
    (tr('مهام منجزة'), n(k['tasks_done']), n(k['tasks_done_prev'])),
    (tr('اجتماعات منعقدة'), n(k['meetings_held']), n(k['meetings_held_prev'])),
    (tr('عملاء جدد'), n(k['new_clients']), n(k['new_clients_prev'])),
  ];
  final fin = d.finance;
  if (fin != null) {
    rows.addAll([
      (tr('المحصّل'), moneyLabel(ReportData.n(fin['collected'])), moneyLabel(ReportData.n(fin['collected_prev']))),
      (tr('المفوتر'), moneyLabel(ReportData.n(fin['billed'])), ''),
      (tr('المستحق على العملاء'), moneyLabel(ReportData.n(fin['due'])), ''),
    ]);
  }
  return rows;
}

String _title(ReportFilter f, String? memberName) =>
    memberName == null ? tr('تقرير Zypro · {0}', [f.label]) : tr('تقرير {0} · {1}', [memberName, f.label]);

/// نص قصير للمشاركة في واتساب أو البريد
String reportSummaryText(ReportData d, ReportFilter f, {String? memberName}) {
  final b = StringBuffer(_title(f, memberName))..writeln();
  for (final r in _kpiRows(d)) {
    b.writeln('• ${r.$1}: ${r.$2}${r.$3.isEmpty ? '' : tr(' (السابقة {0})', [r.$3])}');
  }
  final alerts = decisionAlerts(d);
  if (alerts.isNotEmpty) {
    b.writeln();
    b.writeln(tr('تحتاج قرارك:'));
    for (final a in alerts) {
      b.writeln('• ${a.$1} — ${a.$2}');
    }
  }
  return b.toString().trim();
}

String _csvCell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String toCsv(List<List<Object?>> rows) => rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');

/// ملف CSV يفتح في Excel: المؤشرات، الفريق، الخدمات، الأطول تعطلًا
String reportCsv(ReportData d, ReportFilter f, Map<String, StatusLabel> labels, {String? memberName}) {
  final rows = <List<Object?>>[
    [_title(f, memberName)],
    [],
    [tr('المؤشر'), tr('الحالية'), tr('السابقة')],
    for (final r in _kpiRows(d)) [r.$1, r.$2, r.$3],
  ];
  if (d.team.isNotEmpty) {
    rows.addAll([
      [],
      [tr('العضو'), tr('مهام مفتوحة'), tr('متأخرة'), tr('منجزة'), tr('في الموعد'), tr('طلبات مفتوحة'), tr('متوسط المدة')],
      for (final t in d.team)
        [t['name'], t['open_tasks'], t['overdue_tasks'], t['done_tasks'], fmtPct(ReportData.nn(t['on_time'])), t['open_requests'], fmtDays(ReportData.nn(t['avg_days']))],
    ]);
  }
  if (d.services.isNotEmpty) {
    rows.addAll([
      [],
      [tr('نوع الخدمة'), tr('طلبات جديدة'), tr('القيمة'), tr('متوسط المدة')],
      for (final s in d.services) [serviceName('${s['name']}'), s['count'], s['value'], fmtDays(ReportData.nn(s['avg_days']))],
    ]);
  }
  if (d.stuck.isNotEmpty) {
    rows.addAll([
      [],
      [tr('الأطول تعطلًا'), tr('العميل'), tr('المسؤول'), tr('الحالة'), tr('أيام التأخير'), tr('أيام بلا تحديث')],
      for (final s in d.stuck)
        ['#${s['number']} ${s['title']}', s['client'], s['assignee'], statusName('${s['status']}', labels), s['overdue_days'], s['idle_days']],
    ]);
  }
  final fin = d.finance;
  if (fin != null) {
    rows.addAll([
      [],
      [tr('الشهر'), tr('مفوتر'), tr('محصّل')],
      for (final m in d.listOf(fin, 'monthly')) [m['month'], m['billed'], m['collected']],
    ]);
  }
  return toCsv(rows);
}

String _esc(Object? v) => '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _table(List<String> head, List<List<Object?>> rows) {
  final b = StringBuffer('<table><thead><tr>');
  for (final h in head) {
    b.write('<th>${_esc(h)}</th>');
  }
  b.write('</tr></thead><tbody>');
  for (final r in rows) {
    b.write('<tr>');
    for (final c in r) {
      b.write('<td>${_esc(c)}</td>');
    }
    b.write('</tr>');
  }
  b.write('</tbody></table>');
  return b.toString();
}

/// صفحة HTML مرتبة للطباعة أو الحفظ PDF
String reportHtml(ReportData d, ReportFilter f, Map<String, StatusLabel> labels, {String? memberName}) {
  final dir = L.isEn ? 'ltr' : 'rtl';
  final b = StringBuffer()
    ..write('<!DOCTYPE html><html lang="${L.code}" dir="$dir"><head><meta charset="utf-8"><title>${_esc(_title(f, memberName))}</title>')
    ..write('<style>'
        "body{font-family:'IBM Plex Sans Arabic',Tahoma,Arial,sans-serif;color:#34343F;margin:28px;font-size:13px}"
        'h1{font-size:22px;margin:0}h2{font-size:15px;margin:22px 0 8px;border-bottom:2px solid #18C894;padding-bottom:4px}'
        '.sub{color:#5B5E6B;margin:4px 0 16px}'
        '.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}'
        '.k{border:1px solid #E4E6EA;border-radius:10px;padding:10px}.k b{display:block;font-size:20px}.k span{color:#5B5E6B;font-size:11px}'
        'table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #EEF0F3;padding:6px;text-align:start}'
        'th{background:#F5F6F7;font-size:11px;color:#5B5E6B}'
        '.alert{background:#FDEEE6;border-radius:8px;padding:6px 10px;margin:4px 0;color:#9A3412}'
        '@page{margin:14mm}'
        '</style></head><body>')
    ..write('<h1>${_esc(_title(f, memberName))}</h1>')
    ..write('<div class="sub">${_esc(tr('أُعدّ في {0}', [formatDay(DateTime.now())]))}</div>')
    ..write('<div class="kpis">');
  for (final r in _kpiRows(d)) {
    b.write('<div class="k"><span>${_esc(r.$1)}</span><b>${_esc(r.$2)}</b>'
        '${r.$3.isEmpty ? '' : '<span>${_esc(tr('السابقة {0}', [r.$3]))}</span>'}</div>');
  }
  b.write('</div>');
  final alerts = decisionAlerts(d);
  if (alerts.isNotEmpty) {
    b.write('<h2>${_esc(tr('تحتاج قرارك'))}</h2>');
    for (final a in alerts) {
      b.write('<div class="alert"><b>${a.$1}</b> — ${_esc(a.$2)}</div>');
    }
  }
  if (d.team.isNotEmpty) {
    b.write('<h2>${_esc(tr('أداء الفريق في الفترة'))}</h2>');
    b.write(_table(
      [tr('العضو'), tr('مهام مفتوحة'), tr('متأخرة'), tr('منجزة'), tr('في الموعد'), tr('متوسط المدة')],
      [
        for (final t in d.team)
          [t['name'], t['open_tasks'], t['overdue_tasks'], t['done_tasks'], fmtPct(ReportData.nn(t['on_time'])), fmtDays(ReportData.nn(t['avg_days']))],
      ],
    ));
  }
  if (d.services.isNotEmpty) {
    b.write('<h2>${_esc(tr('حسب نوع الخدمة'))}</h2>');
    b.write(_table(
      [tr('نوع الخدمة'), tr('طلبات جديدة'), tr('متوسط المدة')],
      [for (final s in d.services) [serviceName('${s['name']}'), s['count'], fmtDays(ReportData.nn(s['avg_days']))]],
    ));
  }
  if (d.stuck.isNotEmpty) {
    b.write('<h2>${_esc(tr('الأطول تعطلًا'))}</h2>');
    b.write(_table(
      [tr('الطلب'), tr('العميل'), tr('المسؤول'), tr('الحالة'), tr('التأخير')],
      [
        for (final s in d.stuck)
          [
            '#${s['number']} ${s['title']}',
            s['client'],
            s['assignee'],
            statusName('${s['status']}', labels),
            s['overdue_days'] == null ? '—' : tr('{0} يوم', [s['overdue_days']]),
          ],
      ],
    ));
  }
  final fin = d.finance;
  if (fin != null) {
    final late = d.listOf(fin, 'late');
    if (late.isNotEmpty) {
      b.write('<h2>${_esc(tr('الأكثر تأخرًا في السداد'))}</h2>');
      b.write(_table(
        [tr('العميل'), tr('الفاتورة'), tr('المتبقي'), tr('التأخير')],
        [for (final l in late) [l['client'], l['number'], moneyLabel(ReportData.n(l['remaining'])), tr('{0} يوم', [l['days']])]],
      ));
    }
  }
  b.write('</body></html>');
  return b.toString();
}
