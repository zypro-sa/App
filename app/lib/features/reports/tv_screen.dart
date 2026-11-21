import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../core/web/web_tools.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
import 'custom_report.dart';
import 'report_common.dart';

/// ألوان شاشة المكتب (داكنة دائمًا)
class _Tv {
  static const bg = Color(0xFF14141A);
  static const card = Color(0xFF1E1E26);
  static const line = Color(0xFF2C2C36);
  static const text = Color(0xFFECECF1);
  static const muted = Color(0xFFA3A6B3);
  static const accent = Color(0xFF18C894);
  static const amber = Color(0xFFF2CC6B);
  static const coral = Color(0xFFF4A582);
  static const blue = Color(0xFF7FB3E6);
}

/// شاشة المكتب: شريحتان تتبدلان كل ٣٠ ثانية وتتحدث البيانات كل ٥ دقائق.
class TvScreen extends ConsumerStatefulWidget {
  const TvScreen({super.key});

  @override
  ConsumerState<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends ConsumerState<TvScreen> {
  int _slides = 1;
  int _interval = 30;
  Set<String> _hidden = {};
  List<(String, String)> _allSlides = const [];
  int _slide = 0;
  bool _paused = false;
  bool _full = false;
  DateTime _now = DateTime.now();
  late (DateTime, DateTime, String?) _key = _makeKey();
  Timer? _rotate;
  Timer? _clock;
  Timer? _refresh;

  late (DateTime, DateTime, String?) _monthKey = _makeMonthKey();

  static (DateTime, DateTime, String?) _makeMonthKey() {
    final today = dateOnly(DateTime.now());
    return (DateTime(today.year, today.month), today, null);
  }

  void _next() => setState(() => _slide = (_slide + 1) % _slides);

  static (DateTime, DateTime, String?) _makeKey() {
    final today = dateOnly(DateTime.now());
    return (today.subtract(const Duration(days: 29)), today, null);
  }

  void _startRotation() {
    _rotate?.cancel();
    _rotate = Timer.periodic(Duration(seconds: _interval), (_) {
      if (!_paused) _next();
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _hidden = (p.getStringList('tv_hidden_slides') ?? const []).toSet();
        _interval = p.getInt('tv_interval') ?? 30;
      });
      _startRotation();
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('tv_hidden_slides', _hidden.toList());
      await p.setInt('tv_interval', _interval);
    } catch (_) {}
  }

  /// وضع الاجتماع: اختيار الشرائح ومدة كل شريحة
  Future<void> _configure() async {
    final hidden = {..._hidden};
    var interval = _interval;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('شرائح العرض')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (id, title) in _allSlides)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: !hidden.contains(id),
                      title: Text(title),
                      onChanged: (v) => set(() => v == true ? hidden.remove(id) : hidden.add(id)),
                    ),
                  const SizedBox(height: 12),
                  Text(tr('مدة كل شريحة')),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final sec in const [15, 30, 60, 120])
                        ChoiceChip(
                          label: Text(sec < 60 ? tr('{0} ثانية', [sec]) : tr('{0} دقيقة', [sec ~/ 60])),
                          selected: interval == sec,
                          showCheckmark: false,
                          onSelected: (_) => set(() => interval = sec),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تطبيق'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _hidden = hidden;
      _interval = interval;
      _slide = 0;
    });
    _startRotation();
    _savePrefs();
  }

  @override
  void initState() {
    super.initState();
    _startRotation();
    _loadPrefs();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) {
      final k = _makeKey();
      if (k != _key) {
        setState(() {
          _key = k;
          _monthKey = _makeMonthKey();
        });
      } else {
        ref.invalidate(reportDashboardProvider(_key));
        ref.invalidate(reportDashboardProvider(_monthKey));
        ref.invalidate(savedReportsProvider);
        ref.invalidate(customReportProvider);
      }
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _clock?.cancel();
    _refresh?.cancel();
    if (_full) setFullscreen(false);
    super.dispose();
  }

  void _close() {
    if (_full) setFullscreen(false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/more/reports');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    final allowed = me?.can(Permissions.reportsView) ?? false;
    final data = ref.watch(reportDashboardProvider(_key));
    final d = data.valueOrNull;
    final month = allowed ? ref.watch(reportDashboardProvider(_monthKey)).valueOrNull : null;

    // الشرائح المتاحة حسب البيانات والصلاحيات
    final tvReports = allowed
        ? (ref.watch(savedReportsProvider).valueOrNull ?? const <SavedReport>[]).where((r) => r.onTv).toList()
        : const <SavedReport>[];
    final all = <(String, String, Widget Function(ReportData, double))>[
      ('overview', tr('نظرة عامة · آخر ٣٠ يومًا'), (d, s) => _OverviewSlide(d, s)),
      ('requests', tr('الطلبات · الحالات والتعطل'), (d, s) => _RequestsSlide(d, s)),
      ('team', tr('الفريق · العمل المفتوح والالتزام'), (d, s) => _TeamSlide(d, s)),
      if (d?.finance != null) ('finance', tr('المالية · التحصيل والمستحقات'), (d, s) => _FinanceSlide(d, s)),
      ('clients', tr('العملاء والاجتماعات'), (d, s) => _ClientsSlide(d, s)),
      if (month != null && month.goals.isNotEmpty)
        ('goals', tr('أهداف {0}', [formatPattern('MMMM', DateTime.now())]), (_, s) => _GoalsSlide(month, s)),
      for (final r in tvReports) ('r:${r.id}', r.name, (_, s) => _CustomSlide(r, s)),
    ];
    _allSlides = [for (final x in all) (x.$1, x.$2)];
    final visible = all.where((x) => !_hidden.contains(x.$1)).toList();
    final slides = [for (final x in (visible.isEmpty ? all : visible)) (x.$2, x.$3)];
    _slides = slides.length;
    if (_slide >= _slides) _slide = 0;

    return Scaffold(
      backgroundColor: _Tv.bg,
      body: DefaultTextStyle.merge(
        style: const TextStyle(color: _Tv.text),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final s = (c.maxWidth / 1280).clamp(0.62, 1.8).toDouble();
            return Padding(
              padding: EdgeInsets.all(28 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(s, slides[_slide].$1),
                  SizedBox(height: 20 * s),
                  Expanded(
                    child: me == null
                        ? const Center(child: CircularProgressIndicator(color: _Tv.accent))
                        : !allowed
                            ? Center(child: Text(tr('ليست لديك صلاحية التقارير'), style: TextStyle(fontSize: 22 * s, color: _Tv.muted)))
                            : d == null
                                ? Center(
                                    child: data.hasError
                                        ? Text(tr('تعذّر تحميل البيانات'), style: TextStyle(fontSize: 22 * s, color: _Tv.muted))
                                        : const CircularProgressIndicator(color: _Tv.accent),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _next,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 600),
                                      child: KeyedSubtree(
                                        key: ValueKey(_slide),
                                        child: slides[_slide].$2(d, s),
                                      ),
                                    ),
                                  ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _header(double s, String title) {
    return Row(
      children: [
        Text('Zypro', style: TextStyle(fontSize: 30 * s, fontWeight: FontWeight.w800, color: _Tv.accent, letterSpacing: 0.5)),
        SizedBox(width: 16 * s),
        Container(width: 1, height: 28 * s, color: _Tv.line),
        SizedBox(width: 16 * s),
        Expanded(
          child: Text(title, style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        for (var i = 0; i < _slides; i++)
          Container(
            margin: EdgeInsets.symmetric(horizontal: 3 * s),
            width: (i == _slide ? 26 : 10) * s,
            height: 10 * s,
            decoration: BoxDecoration(color: i == _slide ? _Tv.accent : _Tv.line, borderRadius: BorderRadius.circular(5 * s)),
          ),
        SizedBox(width: 18 * s),
        Text(formatTime(_now), style: TextStyle(fontSize: 26 * s, fontWeight: FontWeight.w700)),
        SizedBox(width: 8 * s),
        Text(formatDay(_now), style: TextStyle(fontSize: 15 * s, color: _Tv.muted)),
        SizedBox(width: 12 * s),
        _iconBtn(Icons.tune, tr('شرائح العرض'), s, _configure),
        _iconBtn(_paused ? Icons.play_arrow : Icons.pause, _paused ? tr('تشغيل التبديل') : tr('تثبيت الشريحة الحالية'), s,
            () => setState(() => _paused = !_paused)),
        _iconBtn(_full ? Icons.fullscreen_exit : Icons.fullscreen, tr('ملء الشاشة'), s, () {
          setState(() => _full = !_full);
          setFullscreen(_full);
        }),
        _iconBtn(Icons.close, tr('إغلاق'), s, _close),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tip, double s, VoidCallback onTap) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        iconSize: 24 * s,
        color: _Tv.muted,
        icon: Icon(icon),
      );
}

// ---------------- عناصر الشاشة ----------------
class _Box extends StatelessWidget {
  const _Box({required this.s, required this.child, this.title, this.trailing});
  final double s;
  final Widget child;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20 * s),
      decoration: BoxDecoration(color: _Tv.card, borderRadius: BorderRadius.circular(20 * s), border: Border.all(color: _Tv.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w700, color: _Tv.muted))),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: 14 * s),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BigKpi extends StatelessWidget {
  const _BigKpi({required this.s, required this.label, required this.value, this.change, this.color = _Tv.text});
  final double s;
  final String label;
  final String value;
  final (String, bool)? change;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 18 * s),
      decoration: BoxDecoration(color: _Tv.card, borderRadius: BorderRadius.circular(20 * s), border: Border.all(color: _Tv.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 17 * s, color: _Tv.muted)),
          SizedBox(height: 4 * s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TextStyle(fontSize: 54 * s, fontWeight: FontWeight.w800, color: color, height: 1.1)),
          ),
          if (change != null)
            Text(change!.$1, style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700, color: change!.$2 ? _Tv.accent : _Tv.coral)),
        ],
      ),
    );
  }
}

class _OverviewSlide extends StatelessWidget {
  const _OverviewSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context) {
    final k = d.kpi;
    final weekly = [for (final w in d.weekly) ReportData.n(w['count'])];
    final goal = ReportData.nn(d.goals['requests_closed']);
    final alerts = decisionAlerts(d);
    final overdue = ReportData.n(d.alerts['overdue']);
    final gap = 16 * s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150 * s,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BigKpi(
                  s: s,
                  label: tr('طلبات منجزة'),
                  value: fmtNum(ReportData.n(k['closed'])),
                  change: changeOf(ReportData.nn(k['closed']), ReportData.nn(k['closed_prev'])),
                  color: _Tv.accent,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _BigKpi(
                  s: s,
                  label: tr('الالتزام بالمواعيد'),
                  value: fmtPct(ReportData.nn(k['on_time'])),
                  change: changeOf(ReportData.nn(k['on_time']), ReportData.nn(k['on_time_prev']), points: true),
                ),
              ),
              SizedBox(width: gap),
              Expanded(child: _BigKpi(s: s, label: tr('مفتوحة الآن'), value: fmtNum(ReportData.n(k['open'])), color: _Tv.blue)),
              SizedBox(width: gap),
              Expanded(
                child: _BigKpi(
                  s: s,
                  label: tr('متأخرة'),
                  value: fmtNum(overdue),
                  color: overdue > 0 ? _Tv.coral : _Tv.accent,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _Box(
                  s: s,
                  title: tr('المنجز أسبوعيًا · آخر ١٢ أسبوعًا'),
                  trailing: goal == null
                      ? null
                      : Text(tr('— الهدف الأسبوعي'), style: TextStyle(fontSize: 14 * s, color: _Tv.amber, fontWeight: FontWeight.w600)),
                  child: LayoutBuilder(
                    builder: (context, c) => AreaChart(
                      values: weekly,
                      target: goal == null ? null : goal / 4.33,
                      height: c.maxHeight,
                      color: _Tv.accent,
                      gridColor: _Tv.line,
                      strokeWidth: 4 * s,
                      tooltipBuilder: (i) {
                        final w = DateTime.tryParse('${d.weekly[i]['week']}');
                        return [
                          if (w != null) formatShortDate(w),
                          tr('منجز: {0}', [weekly[i]]),
                        ].join('\n');
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('تحتاج قرارك'),
                  child: alerts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, color: _Tv.accent, size: 56 * s),
                              SizedBox(height: 8 * s),
                              Text(tr('كل شيء في مساره'), style: TextStyle(fontSize: 20 * s, color: _Tv.muted)),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (n, text, _, tone) in alerts)
                              Padding(
                                padding: EdgeInsets.only(bottom: 14 * s),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 58 * s,
                                      height: 58 * s,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _toneTv(tone).withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(14 * s),
                                      ),
                                      child: Text(fmtNum(n),
                                          style: TextStyle(fontSize: 26 * s, fontWeight: FontWeight.w800, color: _toneTv(tone))),
                                    ),
                                    SizedBox(width: 14 * s),
                                    Expanded(child: Text(text, style: TextStyle(fontSize: 18 * s), maxLines: 2)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _toneTv(String tone) => switch (tone) {
      'urgent' => _Tv.coral,
      'waiting' => _Tv.amber,
      'done' => _Tv.accent,
      _ => _Tv.blue,
    };

class _TeamSlide extends StatelessWidget {
  const _TeamSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context) {
    final team = d.team
        .where((t) => ReportData.n(t['open_tasks']) + ReportData.n(t['done_tasks']) + ReportData.n(t['open_requests']) > 0)
        .take(7)
        .toList();
    final maxLoad = team.fold<num>(1, (a, t) {
      final v = ReportData.n(t['open_tasks']) + ReportData.n(t['open_requests']);
      return v > a ? v : a;
    });
    final gap = 16 * s;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _Box(
            s: s,
            title: tr('الفريق · العمل المفتوح والالتزام'),
            child: team.isEmpty
                ? Center(child: Text(tr('لا توجد بيانات'), style: TextStyle(fontSize: 20 * s, color: _Tv.muted)))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final t in team)
                        Row(
                          children: [
                            SizedBox(
                              width: 170 * s,
                              child: Text('${t['name']}', style: TextStyle(fontSize: 19 * s, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                                    width: w < 8 ? 8 : w,
                                    child: StackedBar(
                                      height: 20 * s,
                                      trackColor: _Tv.line,
                                      parts: [(open - late, _Tv.accent), (late, _Tv.coral), (req, _Tv.blue)],
                                    ),
                                  ),
                                );
                              }),
                            ),
                            SizedBox(width: 14 * s),
                            SizedBox(
                              width: 54 * s,
                              child: Text(fmtNum(ReportData.n(t['open_tasks']) + ReportData.n(t['open_requests'])),
                                  textAlign: TextAlign.end, style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w700)),
                            ),
                            SizedBox(
                              width: 90 * s,
                              child: () {
                                final v = ReportData.nn(t['on_time']);
                                return Text(
                                  fmtPct(v),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 20 * s,
                                    fontWeight: FontWeight.w700,
                                    color: v == null ? _Tv.muted : (v >= 85 ? _Tv.accent : v >= 70 ? _Tv.amber : _Tv.coral),
                                  ),
                                );
                              }(),
                            ),
                          ],
                        ),
                      Row(
                        children: [
                          _legend(tr('مهام'), _Tv.accent),
                          _legend(tr('متأخرة'), _Tv.coral),
                          _legend(tr('طلبات'), _Tv.blue),
                          const Spacer(),
                          Text(tr('النسبة: المهام المنجزة في موعدها'), style: TextStyle(fontSize: 13 * s, color: _Tv.muted)),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BigKpi(
                  s: s,
                  label: tr('مهام منجزة'),
                  value: fmtNum(ReportData.n(d.kpi['tasks_done'])),
                  change: changeOf(ReportData.nn(d.kpi['tasks_done']), ReportData.nn(d.kpi['tasks_done_prev'])),
                  color: _Tv.accent,
                ),
              ),
              SizedBox(height: gap),
              Expanded(
                child: _BigKpi(
                  s: s,
                  label: tr('متوسط زمن الإنجاز'),
                  value: fmtDays(ReportData.nn(d.kpi['avg_days'])),
                  change: changeOf(ReportData.nn(d.kpi['avg_days']), ReportData.nn(d.kpi['avg_days_prev']), lowerIsBetter: true),
                  color: _Tv.blue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(String label, Color c) => Padding(
        padding: EdgeInsetsDirectional.only(end: 16 * s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12 * s, height: 12 * s, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3 * s))),
            SizedBox(width: 6 * s),
            Text(label, style: TextStyle(fontSize: 13 * s, color: _Tv.muted)),
          ],
        ),
      );
}

String _tvMonth(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : formatPattern('MMM', d);
}

/// سطر في قوائم الشاشة: عنوان، وصف، وقيمة على الطرف
class _Line extends StatelessWidget {
  const _Line({required this.s, required this.title, this.subtitle, this.value, this.valueColor = _Tv.text});
  final double s;
  final String title;
  final String? subtitle;
  final String? value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * s),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19 * s, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14 * s, color: _Tv.muted)),
              ],
            ),
          ),
          if (value != null) ...[
            SizedBox(width: 12 * s),
            Text(value!, style: TextStyle(fontSize: 19 * s, fontWeight: FontWeight.w700, color: valueColor)),
          ],
        ],
      ),
    );
  }
}

Widget _empty(double s) => Center(child: Text(tr('لا توجد بيانات'), style: TextStyle(fontSize: 20 * s, color: _Tv.muted)));

Widget _kpiRow(double s, List<Widget> kpis) => SizedBox(
      height: 150 * s,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kpis.length; i++) ...[
            if (i > 0) SizedBox(width: 16 * s),
            Expanded(child: kpis[i]),
          ],
        ],
      ),
    );

// ---------------- الطلبات ----------------
class _RequestsSlide extends ConsumerWidget {
  const _RequestsSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = requestLabels(ref);
    final k = d.kpi;
    final entries = d.byStatus.entries.toList()..sort((a, b) => ReportData.n(b.value).compareTo(ReportData.n(a.value)));
    final total = entries.fold<num>(0, (a, e) => a + ReportData.n(e.value));
    final services = d.services.take(5).toList();
    final gap = 16 * s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpiRow(s, [
          _BigKpi(
            s: s,
            label: tr('طلبات جديدة'),
            value: fmtNum(ReportData.n(k['new'])),
            change: changeOf(ReportData.nn(k['new']), ReportData.nn(k['new_prev'])),
            color: _Tv.blue,
          ),
          _BigKpi(
            s: s,
            label: tr('طلبات منجزة'),
            value: fmtNum(ReportData.n(k['closed'])),
            change: changeOf(ReportData.nn(k['closed']), ReportData.nn(k['closed_prev'])),
            color: _Tv.accent,
          ),
          _BigKpi(
            s: s,
            label: tr('بانتظار العميل أكثر من أسبوع'),
            value: fmtNum(ReportData.n(d.alerts['waiting_long'])),
            color: _Tv.amber,
          ),
        ]),
        SizedBox(height: gap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('المفتوحة حسب الحالة'),
                  trailing: Text(fmtNum(total), style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w800)),
                  child: total == 0
                      ? _empty(s)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StackedBar(
                              height: 24 * s,
                              trackColor: _Tv.line,
                              parts: [for (final e in entries) (ReportData.n(e.value), statusColor(e.key, labels))],
                            ),
                            SizedBox(height: 12 * s),
                            for (final e in entries.take(5))
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 6 * s),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 14 * s,
                                      height: 14 * s,
                                      decoration: BoxDecoration(color: statusColor(e.key, labels), shape: BoxShape.circle),
                                    ),
                                    SizedBox(width: 10 * s),
                                    Expanded(child: Text(statusName(e.key, labels), style: TextStyle(fontSize: 19 * s))),
                                    Text(fmtNum(ReportData.n(e.value)), style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('الأطول تعطلًا'),
                  child: d.stuck.isEmpty
                      ? _empty(s)
                      : Column(
                          children: [
                            for (final r in d.stuck)
                              _Line(
                                s: s,
                                title: '#${r['number']} · ${r['title']}',
                                subtitle: [if (r['client'] != null) '${r['client']}', if (r['assignee'] != null) '${r['assignee']}'].join(' · '),
                                value: r['overdue_days'] != null
                                    ? tr('متأخر {0} يوم', [r['overdue_days']])
                                    : tr('بلا تحديث {0} يوم', [r['idle_days']]),
                                valueColor: r['overdue_days'] != null ? _Tv.coral : _Tv.muted,
                              ),
                          ],
                        ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('حسب نوع الخدمة'),
                  child: services.isEmpty
                      ? _empty(s)
                      : Column(
                          children: [
                            for (final e in services)
                              _Line(
                                s: s,
                                title: serviceName('${e['name']}'),
                                subtitle: tr('متوسط الإنجاز {0}', [fmtDays(ReportData.nn(e['avg_days']))]),
                                value: fmtNum(ReportData.n(e['count'])),
                                valueColor: _Tv.blue,
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- المالية ----------------
class _FinanceSlide extends StatelessWidget {
  const _FinanceSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context) {
    final fin = d.finance ?? const <String, dynamic>{};
    final monthly = d.listOf(fin, 'monthly');
    final late = d.listOf(fin, 'late');
    final aging = fin['aging'] is Map ? Map<String, dynamic>.from(fin['aging'] as Map) : const <String, dynamic>{};
    final agingParts = [
      (tr('٠–٣٠ يومًا'), ReportData.n(aging['a0_30']), _Tv.accent),
      (tr('٣١–٦٠ يومًا'), ReportData.n(aging['a31_60']), _Tv.amber),
      (tr('أكثر من ٦٠'), ReportData.n(aging['a60']), _Tv.coral),
    ];
    final gap = 16 * s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpiRow(s, [
          _BigKpi(
            s: s,
            label: tr('المحصّل · ر.س'),
            value: moneyCompact(ReportData.n(fin['collected'])),
            change: changeOf(ReportData.nn(fin['collected']), ReportData.nn(fin['collected_prev'])),
            color: _Tv.blue,
          ),
          _BigKpi(s: s, label: tr('المفوتر · ر.س'), value: moneyCompact(ReportData.n(fin['billed']))),
          _BigKpi(s: s, label: tr('المستحق · ر.س'), value: moneyCompact(ReportData.n(fin['due'])), color: _Tv.amber),
        ]),
        SizedBox(height: gap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _Box(
                  s: s,
                  title: tr('المفوتر والمحصّل · ٦ أشهر'),
                  child: monthly.isEmpty
                      ? _empty(s)
                      : LayoutBuilder(
                          builder: (context, c) => PairedColumns(
                            height: (c.maxHeight - 26 * s).clamp(40, 600).toDouble(),
                            labels: [for (final m in monthly) _tvMonth('${m['month']}')],
                            a: [for (final m in monthly) ReportData.n(m['collected'])],
                            b: [for (final m in monthly) ReportData.n(m['billed'])],
                            colorA: _Tv.blue,
                            colorB: _Tv.line,
                            labelStyle: TextStyle(fontSize: 13 * s, color: _Tv.muted),
                            tooltipBuilder: (i) => tr('مفوتر: {0}', [moneyLabel(ReportData.n(monthly[i]['billed']))]) +
                                '\n' +
                                tr('محصّل: {0}', [moneyLabel(ReportData.n(monthly[i]['collected']))]),
                          ),
                        ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: _Box(
                  s: s,
                  title: tr('أعمار المستحقات'),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final size = (c.maxHeight < c.maxWidth ? c.maxHeight : c.maxWidth).clamp(60, 400).toDouble();
                            return Center(
                              child: DonutChart(
                                size: size,
                                thickness: size / 8,
                                trackColor: _Tv.line,
                                parts: [for (final p in agingParts) (p.$2, p.$3)],
                                center: Text(moneyCompact(agingParts.fold<num>(0, (a, p) => a + p.$2)),
                                    style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w800)),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 10 * s),
                      for (final p in agingParts)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 3 * s),
                          child: Row(
                            children: [
                              Container(width: 12 * s, height: 12 * s, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3 * s))),
                              SizedBox(width: 8 * s),
                              Expanded(child: Text(p.$1, style: TextStyle(fontSize: 15 * s, color: _Tv.muted))),
                              Text(moneyCompact(p.$2), style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: _Box(
                  s: s,
                  title: tr('الأكثر تأخرًا في السداد'),
                  child: late.isEmpty
                      ? _empty(s)
                      : Column(
                          children: [
                            for (final l in late)
                              _Line(
                                s: s,
                                title: '${l['client']}',
                                subtitle: tr('متأخرة {0} يوم', [l['days']]),
                                value: moneyCompact(ReportData.n(l['remaining'])),
                                valueColor: _Tv.coral,
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- العملاء والاجتماعات ----------------
class _ClientsSlide extends StatelessWidget {
  const _ClientsSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context) {
    final c = d.clients ?? const <String, dynamic>{};
    final idle = d.listOf(c, 'idle');
    final top = d.listOf(c, 'top');
    final m = d.meetings;
    final parts = [
      (tr('عُقد'), ReportData.n(m['done']), _Tv.accent),
      (tr('مجدول'), ReportData.n(m['scheduled']), _Tv.blue),
      (tr('مؤجل'), ReportData.n(m['postponed']), _Tv.amber),
      (tr('أُلغي'), ReportData.n(m['cancelled']), _Tv.coral),
    ];
    final mTotal = parts.fold<num>(0, (a, p) => a + p.$2);
    final dt = d.decisionTasks, pr = d.promises;
    final dtTotal = ReportData.n(dt['total']), prTotal = ReportData.n(pr['total']);
    final gap = 16 * s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpiRow(s, [
          _BigKpi(s: s, label: tr('عملاء نشطون'), value: fmtNum(ReportData.n(c['active'])), color: _Tv.accent),
          _BigKpi(
            s: s,
            label: tr('عملاء جدد'),
            value: fmtNum(ReportData.n(d.kpi['new_clients'])),
            change: changeOf(ReportData.nn(d.kpi['new_clients']), ReportData.nn(d.kpi['new_clients_prev'])),
          ),
          _BigKpi(
            s: s,
            label: tr('تنفيذ قرارات الاجتماعات'),
            value: dtTotal == 0 ? '—' : fmtPct(ReportData.n(dt['done']) * 100 / dtTotal),
            color: _Tv.blue,
          ),
          _BigKpi(
            s: s,
            label: tr('الوفاء بالوعود للعملاء'),
            value: prTotal == 0 ? '—' : fmtPct(ReportData.n(pr['on_time']) * 100 / prTotal),
            color: _Tv.amber,
          ),
        ]),
        SizedBox(height: gap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('الاجتماعات في الفترة'),
                  trailing: Text(fmtNum(mTotal), style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w800)),
                  child: mTotal == 0
                      ? _empty(s)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StackedBar(height: 24 * s, trackColor: _Tv.line, parts: [for (final p in parts) (p.$2, p.$3)]),
                            SizedBox(height: 12 * s),
                            for (final p in parts)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 6 * s),
                                child: Row(
                                  children: [
                                    Container(width: 14 * s, height: 14 * s, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
                                    SizedBox(width: 10 * s),
                                    Expanded(child: Text(p.$1, style: TextStyle(fontSize: 19 * s))),
                                    Text(fmtNum(p.$2), style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _Box(
                  s: s,
                  title: d.canFinance ? tr('أعلى العملاء قيمة · ١٢ شهرًا') : tr('أكثر العملاء طلبات'),
                  child: top.isEmpty
                      ? _empty(s)
                      : Column(
                          children: [
                            for (final t in top)
                              _Line(
                                s: s,
                                title: '${t['name']}',
                                subtitle: tr('{0} طلب', [t['requests']]),
                                value: t['value'] == null ? null : moneyCompact(ReportData.n(t['value'])),
                                valueColor: _Tv.blue,
                              ),
                          ],
                        ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _Box(
                  s: s,
                  title: tr('عملاء يحتاجون تواصلًا'),
                  child: idle.isEmpty
                      ? Center(child: Text(tr('كل العملاء على تواصل'), style: TextStyle(fontSize: 20 * s, color: _Tv.muted)))
                      : Column(
                          children: [
                            for (final i in idle.take(5))
                              _Line(s: s, title: '${i['name']}', value: tr('منذ {0} يوم', [i['days']]), valueColor: _Tv.amber),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- الأهداف ----------------
class _GoalsSlide extends StatelessWidget {
  const _GoalsSlide(this.d, this.s);
  final ReportData d;
  final double s;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final pace = today.day / DateTime(today.year, today.month + 1, 0).day;
    num? actual(String key) => switch (key) {
          'requests_closed' => ReportData.nn(d.kpi['closed']),
          'collected' => ReportData.nn(d.finance?['collected']),
          'on_time' => ReportData.nn(d.kpi['on_time']),
          'new_clients' => ReportData.nn(d.kpi['new_clients']),
          'tasks_done' => ReportData.nn(d.kpi['tasks_done']),
          'meetings_held' => ReportData.nn(d.kpi['meetings_held']),
          _ => null,
        };
    final goals = GoalMetric.all.where((g) => d.goals[g.key] != null && (g.key != 'collected' || d.canFinance)).toList();
    String fmt(GoalMetric g, num? v) => v == null ? '—' : g.percent ? fmtPct(v) : g.money ? moneyCompact(v) : fmtNum(v);
    return _Box(
      s: s,
      title: tr('مضى {0}٪ من الشهر', [(pace * 100).round()]),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final g in goals)
            () {
              final target = ReportData.n(d.goals[g.key]);
              final v = actual(g.key);
              final ratio = v == null || target == 0 ? 0.0 : (v / target).toDouble();
              final onTrack = g.percent ? ratio >= 1 : ratio >= pace;
              final color = ratio >= 1 ? _Tv.accent : onTrack ? _Tv.blue : _Tv.amber;
              return Row(
                children: [
                  SizedBox(width: 230 * s, child: Text(tr(g.labelAr), style: TextStyle(fontSize: 21 * s, fontWeight: FontWeight.w600))),
                  Expanded(child: ProgressBar(ratio: ratio, color: color, height: 22 * s, trackColor: _Tv.line)),
                  SizedBox(width: 16 * s),
                  SizedBox(
                    width: 230 * s,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: fmt(g, v), style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w800, color: color)),
                        TextSpan(text: ' / ${fmt(g, target)}', style: TextStyle(fontSize: 17 * s, color: _Tv.muted)),
                      ]),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              );
            }(),
        ],
      ),
    );
  }
}

// ---------------- تقرير مخصص ----------------
class _CustomSlide extends ConsumerWidget {
  const _CustomSlide(this.r, this.s);
  final SavedReport r;
  final double s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(customReportProvider(r.config.key));
    return _Box(
      s: s,
      title: customSummary(r.config),
      child: res.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _Tv.accent)),
        error: (_, __) => Center(child: Text(tr('تعذّر تحميل البيانات'), style: TextStyle(fontSize: 20 * s, color: _Tv.muted))),
        data: (data) => LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: CustomResultView(
              config: r.config,
              result: data,
              dark: true,
              height: (c.maxHeight * 0.8).clamp(150, 900).toDouble(),
            ),
          ),
        ),
      ),
    );
  }
}
