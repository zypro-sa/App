import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ١١ · المالية (للمالك فقط)
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  bool _quotes = false;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(profileProvider).valueOrNull?.role;
    if (role != null && role != UserRole.owner) {
      return Scaffold(
        appBar: sectionAppBar('المالية'),
        body: const EmptyState('هذا القسم للمالك فقط', icon: Icons.lock_outline),
      );
    }
    final summary = ref.watch(financeSummaryProvider);
    final invoices = ref.watch(invoicesProvider);
    final quotes = ref.watch(quotesProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: sectionAppBar(
        'المالية',
        subtitle: DateFormat('MMMM y', 'ar').format(now),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Pill.neutral('للمالك فقط'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSections(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<FinanceSummary>(
              value: summary,
              onRetry: () => ref.invalidate(financeSummaryProvider),
              builder: (s) => _SummaryCard(s),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('الفواتير ${invoices.valueOrNull?.length ?? ''}')),
                ButtonSegment(value: true, label: Text('عروض الأسعار ${quotes.valueOrNull?.length ?? ''}')),
              ],
              selected: {_quotes},
              onSelectionChanged: (s) => setState(() => _quotes = s.first),
            ),
            const SizedBox(height: 14),
            if (!_quotes)
              AsyncBody<List<Invoice>>(
                value: invoices,
                onRetry: () => ref.invalidate(invoicesProvider),
                builder: (list) => list.isEmpty
                    ? const EmptyState('لا توجد فواتير بعد', icon: Icons.receipt_long_outlined)
                    : _InvoiceList(list),
              )
            else
              AsyncBody<List<Quote>>(
                value: quotes,
                onRetry: () => ref.invalidate(quotesProvider),
                builder: (list) => list.isEmpty
                    ? const EmptyState('لا توجد عروض أسعار بعد', icon: Icons.request_quote_outlined)
                    : _QuoteList(list),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!_quotes) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _recordPayment(context, ref, invoices.valueOrNull ?? const []),
                      child: const Text('تسجيل دفعة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showFormSheet(context, _NewDocSheet(quote: _quotes)),
                    child: Text(_quotes ? 'عرض سعر جديد' : 'فاتورة جديدة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'الفوترة الرسمية تبقى في نظام المحاسبة · هنا للمتابعة فقط',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _recordPayment(BuildContext context, WidgetRef ref, List<Invoice> invoices, {Invoice? invoice}) async {
  final open = invoices.where((i) => i.isOpen).toList();
  var target = invoice;
  if (target == null) {
    if (open.isEmpty) {
      showSnack(context, 'لا توجد فواتير مفتوحة');
      return;
    }
    target = await showModalBottomSheet<Invoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('اختر الفاتورة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final i in open)
              ListTile(
                title: Text('${i.number} · ${i.clientName ?? ''}'),
                subtitle: Text('المتبقي ${money(i.remaining)}'),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
  }
  if (target == null || !context.mounted) return;
  final amount = await promptNumber(context, 'دفعة على ${target.number}', label: 'المبلغ (المتبقي ${moneyShort(target.remaining)})');
  if (amount == null || amount <= 0 || !context.mounted) return;
  final inv = target;
  if (await runAction(context, () => ref.read(sectionRepoProvider).recordPayment(inv.id, amount), success: 'سُجّلت الدفعة')) {
    refreshSections(ref);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.s);
  final FinanceSummary s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('مستحق التحصيل', style: TextStyle(fontSize: 13, color: Color(0xFFC9CED6))),
          Text(money(s.due), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mini('متأخر', money(s.overdue), const Color(0xFFF7B79A))),
              const SizedBox(width: 10),
              Expanded(child: _mini('محصّل هذا الشهر', money(s.collectedThisMonth), const Color(0xFF9FE0B8))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color labelColor) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      );
}

class _InvoiceList extends ConsumerWidget {
  const _InvoiceList(this.list);
  final List<Invoice> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            InkWell(
              onTap: list[i].isOpen ? () => _recordPayment(context, ref, list, invoice: list[i]) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${list[i].number} · ${list[i].clientName ?? ''}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(_subtitle(list[i]),
                              style: TextStyle(
                                fontSize: 12,
                                color: list[i].isOverdue ? AppColors.urgent : AppColors.muted,
                                fontWeight: list[i].isOverdue ? FontWeight.w600 : FontWeight.w400,
                              )),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(moneyShort(list[i].total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        _pill(list[i]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(Invoice i) {
    if (i.status == InvoiceStatus.paid) return 'مدفوعة بالكامل';
    if (i.isOverdue) return 'استحقت منذ ${DateTime.now().difference(i.dueDate).inDays} يومًا';
    if (i.status == InvoiceStatus.partiallyPaid) {
      return 'دُفع ${((i.paid / i.total) * 100).round()}٪ · الباقي ${formatShortDate(i.dueDate)}';
    }
    return 'تستحق ${formatShortDate(i.dueDate)}';
  }

  Pill _pill(Invoice i) {
    if (i.isOverdue) return Pill.urgent('متأخرة');
    switch (i.status) {
      case InvoiceStatus.paid:
        return Pill.done(i.status.label);
      case InvoiceStatus.partiallyPaid:
        return Pill.waiting(i.status.label);
      default:
        return Pill.neutral(i.status.label);
    }
  }
}

class _QuoteList extends ConsumerWidget {
  const _QuoteList(this.list);
  final List<Quote> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${list[i].number} · ${list[i].clientName ?? ''}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          list[i].sentAt == null ? 'لم يُرسل بعد' : 'أُرسل ${relativeDay(list[i].sentAt!)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(moneyShort(list[i].total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  PopupMenuButton<QuoteStatus>(
                    tooltip: 'تغيير الحالة',
                    onSelected: (s) async {
                      if (await runAction(context, () => ref.read(sectionRepoProvider).setQuoteStatus(list[i].id, s))) {
                        refreshSections(ref);
                      }
                    },
                    itemBuilder: (_) => [for (final s in QuoteStatus.values) PopupMenuItem(value: s, child: Text(s.label))],
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: _quotePill(list[i].status),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Pill _quotePill(QuoteStatus s) {
    switch (s) {
      case QuoteStatus.sent:
        return Pill.waiting(s.label);
      case QuoteStatus.accepted:
        return Pill.done(s.label);
      case QuoteStatus.rejected:
      case QuoteStatus.expired:
        return Pill.urgent(s.label);
      case QuoteStatus.draft:
        return Pill.neutral(s.label);
    }
  }
}

class _NewDocSheet extends ConsumerStatefulWidget {
  const _NewDocSheet({required this.quote});
  final bool quote;

  @override
  ConsumerState<_NewDocSheet> createState() => _NewDocSheetState();
}

class _NewDocSheetState extends ConsumerState<_NewDocSheet> {
  String? _clientId;
  num? _amount;
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  bool _vat = true;
  bool _busy = false;

  Future<void> _save() async {
    if (_clientId == null || _amount == null) {
      showSnack(context, 'اختر العميل وأدخل المبلغ');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(sectionRepoProvider);
    final ok = await runAction(
      context,
      () => widget.quote
          ? repo.createQuote(clientId: _clientId!, amount: _amount!, withVat: _vat)
          : repo.createInvoice(clientId: _clientId!, total: _amount!, dueDate: _due),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshSections(ref);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    return SheetBody(
      title: widget.quote ? 'عرض سعر جديد' : 'فاتورة جديدة',
      busy: _busy,
      onSubmit: _save,
      children: [
        FormCard(children: [
          FormDropdown<String>(
            label: 'العميل *',
            value: _clientId,
            items: {for (final c in clients) c.id: c.name},
            onChanged: (v) => setState(() => _clientId = v),
          ),
          FormRow(
            label: widget.quote ? 'المبلغ قبل الضريبة *' : 'الإجمالي شامل الضريبة *',
            value: _amount == null ? 'أدخل' : money(_amount!),
            muted: _amount == null,
            onTap: () async {
              final v = await promptNumber(context, 'المبلغ', label: 'بالريال');
              if (v != null) setState(() => _amount = v);
            },
          ),
          if (widget.quote)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إضافة ضريبة ١٥٪', style: TextStyle(fontSize: 14)),
              value: _vat,
              onChanged: (v) => setState(() => _vat = v),
            )
          else
            FormRow(
              label: 'تاريخ الاستحقاق',
              value: formatShortDate(_due),
              onTap: () async {
                final d = await pickDate(context, initial: _due);
                if (d != null) setState(() => _due = d);
              },
            ),
        ]),
      ],
    );
  }
}
