import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';

/// ٥ · ملف العميل
class ClientScreen extends ConsumerWidget {
  const ClientScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clientDetailProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: const Text('ملف العميل'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientDetailProvider(clientId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<ClientDetail>(
              value: detail,
              onRetry: () => ref.invalidate(clientDetailProvider(clientId)),
              builder: (d) => _ClientBody(d),
            ),
          ],
        ),
      ),
    );
  }
}

final _money = NumberFormat.decimalPattern('ar');

class _ClientBody extends StatelessWidget {
  const _ClientBody(this.d);
  final ClientDetail d;

  @override
  Widget build(BuildContext context) {
    final contact = d.primaryContact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Avatar(d.client.initial, size: 64, radius: 20),
              const SizedBox(height: 10),
              Text(d.client.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              if (contact != null)
                Text(
                  'جهة التواصل: ${contact.name}${contact.position != null ? ' · ${contact.position}' : ''}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Action(icon: Icons.call_outlined, label: 'اتصال', enabled: contact?.phone != null)),
                  const SizedBox(width: 8),
                  Expanded(child: _Action(icon: Icons.mail_outline, label: 'بريد', enabled: contact?.email != null)),
                  const SizedBox(width: 8),
                  const Expanded(child: _Action(icon: Icons.event_outlined, label: 'موعد', enabled: true)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _Metric(value: '${d.openRequests}', label: 'طلبات مفتوحة')),
            const SizedBox(width: 8),
            Expanded(child: _Metric(value: _money.format(d.contractsValue), label: 'قيمة العقود')),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(
                value: _money.format(d.amountDue),
                label: 'مستحق الدفع',
                warn: d.amountDue > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ClientRequests(clientId: d.client.id),
        const SizedBox(height: 18),
        const SectionHeader('السجل'),
        if (d.activity.isEmpty)
          const EmptyState('لا يوجد نشاط مسجّل بعد', icon: Icons.history)
        else
          for (var i = 0; i < d.activity.length; i++)
            _TimelineEntry(entry: d.activity[i], first: i == 0, last: i == d.activity.length - 1),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.enabled});

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled ? () {} : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.warn = false});

  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final fg = warn ? AppColors.waiting : AppColors.ink;
    return CardBox(
      radius: 14,
      padding: const EdgeInsets.all(12),
      color: warn ? AppColors.waitingSoft : AppColors.surface,
      borderColor: warn ? const Color(0xFFF2DFA6) : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: warn ? AppColors.waiting : AppColors.muted)),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.first, required this.last});

  final ActivityEntry entry;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: first ? AppColors.primary : const Color(0xFF9AA2AE),
                  shape: BoxShape.circle,
                ),
              ),
              if (!last) Expanded(child: Container(width: 2, color: AppColors.line)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.action, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${relativeDay(entry.at)} · ${formatTime(entry.at)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// طلبات العميل مجمّعة في ملفه.
class _ClientRequests extends ConsumerWidget {
  const _ClientRequests({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(clientRequestsProvider(clientId));
    final list = requests.valueOrNull ?? const <RequestItem>[];
    final open = list.where((r) => r.status.isOpen).toList();
    final closed = list.where((r) => !r.status.isOpen).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('الطلبات${list.isEmpty ? '' : ' · ${open.length} مفتوح'}'),
        AsyncBody<List<RequestItem>>(
          value: requests,
          onRetry: () => ref.invalidate(clientRequestsProvider(clientId)),
          builder: (_) => list.isEmpty
              ? const CardBox(child: Text('لا توجد طلبات لهذا العميل', style: TextStyle(color: AppColors.muted)))
              : CardBox(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < [...open, ...closed].length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: AppColors.divider),
                        _row(context, [...open, ...closed][i]),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, RequestItem r) {
    return InkWell(
      onTap: () => context.go('/requests/${r.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('#${r.number} · ${r.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: r.status.isOpen ? AppColors.ink : AppColors.muted,
                      )),
                ),
                const SizedBox(width: 8),
                Pill.forRequest(r),
              ],
            ),
            if (r.status.isOpen) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: ProgressLine(r.progress, color: r.isOverdue ? const Color(0xFFC2410C) : AppColors.accent)),
                  const SizedBox(width: 8),
                  Text('${r.progress}٪', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
