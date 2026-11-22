import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/web/web_tools.dart';
import '../../data/report_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import 'report_common.dart';
import 'report_export.dart';

/// (النوع، من، إلى، العضو)
final reportListProvider = FutureProvider.autoDispose.family<List<ReportRow>, (String, DateTime, DateTime, String?)>(
  (ref, k) => ref.watch(sectionRepoProvider).reportList(k.$1, k.$2, k.$3, member: k.$4),
);

/// القائمة خلف أي رقم في التقارير.
class ReportListScreen extends ConsumerWidget {
  const ReportListScreen({super.key, required this.kind, required this.from, required this.to, this.member, this.title});
  final String kind;
  final DateTime from;
  final DateTime to;
  final String? member;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (kind, from, to, member);
    final rows = ref.watch(reportListProvider(key));
    final labels = requestLabels(ref);
    final f = ReportFilter(from: from, to: to, member: member);
    final heading = title ?? drillTitle(kind);
    final list = rows.valueOrNull;
    return AmountsScope(child: Scaffold(
      appBar: sectionAppBar(
        heading,
        subtitle: list == null ? f.label : tr('{0} · {1} عنصر', [f.label, list.length]),
        actions: [
          const AmountsToggle(),
          IconButton(
            tooltip: tr('تنزيل Excel (CSV)'),
            icon: const Icon(Icons.download_outlined),
            onPressed: list == null || list.isEmpty
                ? null
                : () => downloadText(
                      'zypro-$kind-${ReportFilter.iso(from)}_${ReportFilter.iso(to)}.csv',
                      toCsv([
                        [tr('العنوان'), tr('التفاصيل'), tr('الحالة'), tr('العميل'), tr('المسؤول'), tr('التاريخ'), tr('المبلغ')],
                        for (final r in list) [r.title, r.subtitle, rowBadge(r, labels), r.client, r.assignee, r.date, r.amount == 0 ? '' : r.amount],
                      ]),
                    ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportListProvider(key)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            AsyncBody<List<ReportRow>>(
              value: rows,
              onRetry: () => ref.invalidate(reportListProvider(key)),
              builder: (items) {
                if (items.isEmpty) return EmptyState(tr('لا توجد عناصر'), icon: Icons.check_circle_outline);
                final total = items.fold<num>(0, (a, r) => a + r.amount);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (total > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CardBox(
                          color: AppColors.primarySoft,
                          borderColor: AppColors.primarySoft,
                          child: Row(
                            children: [
                              Expanded(child: Text(tr('الإجمالي'), style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text(moneyLabel(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    CardBox(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.divider),
                            ReportRowTile(
                              title: items[i].title,
                              subtitle: items[i].subtitle,
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  tonePill(items[i].tone, rowBadge(items[i], labels)),
                                  if (items[i].amount > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(moneyLabel(items[i].amount), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                  ],
                                ],
                              ),
                              onTap: () => openRow(context, items[i].kind, items[i].id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ));
  }
}
