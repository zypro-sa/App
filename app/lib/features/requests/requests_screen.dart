import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart' show statusPill;

/// ٢ · الطلبات
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  RequestStatus? _filter; // null = كل المفتوحة

  static const _filters = <RequestStatus?>[
    null,
    RequestStatus.newRequest,
    RequestStatus.inProgress,
    RequestStatus.waitingClient,
    RequestStatus.onHold,
    RequestStatus.closed,
  ];

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(requestsProvider(_filter));
    final counts = ref.watch(requestCountsProvider).valueOrNull ?? const {};
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final overdue = requests.valueOrNull?.where((r) => r.isOverdue).length ?? 0;
    final labels = {
      for (final l in ref.watch(statusLabelsProvider(ConfigEntity.request)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الطلبات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(
              '$total طلبًا مفتوحًا${overdue > 0 ? ' · $overdue متأخر' : ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _filters[i];
                  final n = f == null ? total : counts[f];
                  final label = f == null ? 'الكل' : (labels[f.db]?.label ?? f.label);
                  return ChoiceChip(
                    label: Text(n == null ? label : '$label $n'),
                    selected: _filter == f,
                    showCheckmark: false,
                    selectedColor: AppColors.ink,
                    labelStyle: TextStyle(
                      color: _filter == f ? Colors.white : AppColors.ink,
                      fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                    ),
                    onSelected: (_) => setState(() => _filter = f),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            AsyncBody<List<RequestItem>>(
              value: requests,
              onRetry: () => ref.invalidate(requestsProvider(_filter)),
              builder: (list) => list.isEmpty
                  ? const EmptyState('لا توجد طلبات هنا')
                  : Column(
                      children: [
                        for (final r in list) ...[
                          _RequestCard(r, label: labels[r.status.db]),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r, {this.label});
  final RequestItem r;
  final StatusLabel? label;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      borderColor: r.isOverdue ? AppColors.urgentBorder : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${r.number}${r.clientName != null ? ' · ${r.clientName}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              (r.isOverdue || label == null) ? Pill.forRequest(r) : statusPill(label!.label, label!.color),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (r.progress > 0) ...[
            const SizedBox(height: 10),
            ProgressLine(r.progress, color: r.isOverdue ? const Color(0xFFC2410C) : AppColors.primary),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (r.progress > 0) '${label?.label ?? r.status.label} · ${r.progress}٪',
                    if (r.progress == 0 && r.dueDate != null) 'التسليم ${formatShortDate(r.dueDate!)}',
                    if (r.priority == Priority.high || r.priority == Priority.urgent) 'أولوية ${r.priority.label}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              if (r.assigneeName != null) ...[
                const Text('المسؤول', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(width: 6),
                Avatar(r.assigneeName!.characters.first),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
