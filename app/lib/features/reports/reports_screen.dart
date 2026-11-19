import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

enum _Period { week, month, quarter }

/// ١٣ · التقارير
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.month;

  (DateTime, DateTime) get _range {
    final today = dateOnly(DateTime.now());
    final days = switch (_period) {
      _Period.week => 7,
      _Period.month => 30,
      _Period.quarter => 90,
    };
    return (today.subtract(Duration(days: days - 1)), today);
  }

  String get _prevLabel => switch (_period) {
        _Period.week => 'عن الأسبوع الماضي',
        _Period.month => 'عن الشهر الماضي',
        _Period.quarter => 'عن الربع الماضي',
      };

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    if (me != null && !me.can(Permissions.reportsView)) {
      return Scaffold(appBar: sectionAppBar('التقارير'), body: const EmptyState('ليست لديك صلاحية التقارير', icon: Icons.lock_outline));
    }
    final report = ref.watch(reportProvider(_range));
    return Scaffold(
      appBar: sectionAppBar('التقارير'),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SegmentedButton<_Period>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Period.week, label: Text('الأسبوع')),
                ButtonSegment(value: _Period.month, label: Text('الشهر')),
                ButtonSegment(value: _Period.quarter, label: Text('الربع')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 14),
            AsyncBody<ReportSummary>(
              value: report,
              onRetry: () => ref.invalidate(reportProvider(_range)),
              builder: (r) => _Body(r, prevLabel: _prevLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.r, {required this.prevLabel});
  final ReportSummary r;
  final String prevLabel;

  @override
  Widget build(BuildContext context) {
    final change = r.changePct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _Kpi(
              'طلبات مُغلقة',
              '${r.closedRequests}',
              change == null ? null : '${change >= 0 ? '▲' : '▼'} ${change.abs()}٪ $prevLabel',
              good: change == null ? null : change >= 0,
            ),
            _Kpi('متوسط زمن الإنجاز', r.avgDays == null ? '—' : '${r.avgDays} يوم', null),
            _Kpi('الالتزام بالمواعيد', r.onTimePct == null ? '—' : '${r.onTimePct}٪', null,
                good: r.onTimePct == null ? null : r.onTimePct! >= 80),
            _Kpi('مهام منجزة', '${r.tasksDone}', r.tasksTotal > 0 ? 'من ${r.tasksTotal} مهمة' : null),
          ],
        ),
        const SizedBox(height: 14),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الطلبات المُغلقة أسبوعيًا', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (r.weekly.isEmpty)
                const Text('لا توجد طلبات مُغلقة في هذه الفترة', style: TextStyle(color: AppColors.muted, fontSize: 13))
              else
                _WeeklyBars(r.weekly),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('أداء الفريق · الالتزام بالمواعيد', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (r.team.isEmpty)
                const Text('لا توجد مهام منجزة في هذه الفترة', style: TextStyle(color: AppColors.muted, fontSize: 13))
              else
                for (final t in r.team)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 90, child: Text(t.$1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                        Expanded(
                          child: ProgressLine(
                            t.$3 ?? 0,
                            height: 8,
                            color: (t.$3 ?? 0) >= 90
                                ? AppColors.done
                                : (t.$3 ?? 0) >= 75
                                    ? const Color(0xFF8FE3C6)
                                    : const Color(0xFFC2410C),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 70,
                          child: Text('${t.$3 ?? 0}٪ · ${t.$2}',
                              textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.note, {this.good});
  final String label;
  final String value;
  final String? note;
  final bool? good;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          if (note != null)
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: good == null ? AppColors.muted : (good! ? AppColors.done : AppColors.urgent),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars(this.weeks);
  final List<(DateTime, int)> weeks;

  @override
  Widget build(BuildContext context) {
    final max = weeks.map((w) => w.$2).fold<int>(1, (a, b) => b > a ? b : a);
    return Semantics(
      label: 'الطلبات المغلقة أسبوعيًا: ${weeks.map((w) => w.$2).join('، ')}',
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${weeks[i].$2}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == weeks.length - 1 ? FontWeight.w700 : FontWeight.w400,
                            color: i == weeks.length - 1 ? AppColors.accentText : AppColors.muted,
                          )),
                      const SizedBox(height: 4),
                      Container(
                        height: 70 * weeks[i].$2 / max + 4,
                        decoration: BoxDecoration(
                          color: i == weeks.length - 1 ? AppColors.accent : const Color(0xFFC6F0E1),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(formatShortDate(weeks[i].$1), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
