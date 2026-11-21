import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../core/web/web_tools.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/charts.dart';
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
  static const _slides = 2;
  int _slide = 0;
  bool _paused = false;
  bool _full = false;
  DateTime _now = DateTime.now();
  late (DateTime, DateTime, String?) _key = _makeKey();
  Timer? _rotate;
  Timer? _clock;
  Timer? _refresh;

  static (DateTime, DateTime, String?) _makeKey() {
    final today = dateOnly(DateTime.now());
    return (today.subtract(const Duration(days: 29)), today, null);
  }

  @override
  void initState() {
    super.initState();
    _rotate = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_paused) setState(() => _slide = (_slide + 1) % _slides);
    });
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) {
      final k = _makeKey();
      if (k != _key) {
        setState(() => _key = k);
      } else {
        ref.invalidate(reportDashboardProvider(_key));
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
                  _header(s),
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
                                    onTap: () => setState(() => _slide = (_slide + 1) % _slides),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 600),
                                      child: KeyedSubtree(
                                        key: ValueKey(_slide),
                                        child: _slide == 0 ? _OverviewSlide(d, s) : _TeamSlide(d, s),
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

  Widget _header(double s) {
    final titles = [tr('نظرة عامة · آخر ٣٠ يومًا'), tr('الفريق والتحصيل')];
    return Row(
      children: [
        Text('Zypro', style: TextStyle(fontSize: 30 * s, fontWeight: FontWeight.w800, color: _Tv.accent, letterSpacing: 0.5)),
        SizedBox(width: 16 * s),
        Container(width: 1, height: 28 * s, color: _Tv.line),
        SizedBox(width: 16 * s),
        Expanded(
          child: Text(titles[_slide], style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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
        _iconBtn(_paused ? Icons.play_arrow : Icons.pause, _paused ? tr('تشغيل التبديل') : tr('إيقاف التبديل'), s,
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
    final fin = d.finance;
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
          child: fin != null ? _financeColumn(fin, gap) : _meetingsColumn(gap),
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

  Widget _financeColumn(Map<String, dynamic> fin, double gap) {
    final monthly = d.listOf(fin, 'monthly');
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
                  label: tr('المحصّل · ر.س'),
                  value: moneyCompact(ReportData.n(fin['collected'])),
                  change: changeOf(ReportData.nn(fin['collected']), ReportData.nn(fin['collected_prev'])),
                  color: _Tv.blue,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _BigKpi(s: s, label: tr('المستحق · ر.س'), value: moneyCompact(ReportData.n(fin['due'])), color: _Tv.amber),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: _Box(
            s: s,
            title: tr('المفوتر والمحصّل · ٦ أشهر'),
            child: LayoutBuilder(
              builder: (context, c) => PairedColumns(
                height: (c.maxHeight - 26 * s).clamp(40, 600).toDouble(),
                labels: [for (final m in monthly) _month('${m['month']}')],
                a: [for (final m in monthly) ReportData.n(m['collected'])],
                b: [for (final m in monthly) ReportData.n(m['billed'])],
                colorA: _Tv.blue,
                colorB: _Tv.line,
                labelStyle: TextStyle(fontSize: 13 * s, color: _Tv.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _meetingsColumn(double gap) {
    final m = d.meetings;
    final dt = d.decisionTasks;
    final dtTotal = ReportData.n(dt['total']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150 * s,
          child: _BigKpi(s: s, label: tr('اجتماعات منعقدة'), value: fmtNum(ReportData.n(m['done'])), color: _Tv.blue),
        ),
        SizedBox(height: gap),
        Expanded(
          child: _BigKpi(
            s: s,
            label: tr('تنفيذ قرارات الاجتماعات'),
            value: dtTotal == 0 ? '—' : fmtPct(ReportData.n(dt['done']) * 100 / dtTotal),
            color: _Tv.accent,
          ),
        ),
      ],
    );
  }

  static String _month(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '' : formatPattern('MMM', d);
  }
}
