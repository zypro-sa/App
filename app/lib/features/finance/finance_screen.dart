import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../daftra/daftra_screen.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

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
    final me = ref.watch(profileProvider).valueOrNull;
    if (me != null && !me.can(Permissions.financeManage)) {
      return Scaffold(
        appBar: sectionAppBar(tr('المالية')),
        body: EmptyState(tr('ليست لديك صلاحية المالية'), icon: Icons.lock_outline),
      );
    }
    final summary = ref.watch(financeSummaryProvider);
    final invoices = ref.watch(invoicesProvider);
    final quotes = ref.watch(quotesProvider);
    final linked = ref.watch(daftraStateProvider).valueOrNull?.enabled ?? false;
    final now = DateTime.now();

    return Scaffold(
      appBar: sectionAppBar(
        tr('المالية'),
        subtitle: DateFormat('MMMM y', L.code).format(now),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Pill.neutral(tr('صلاحية خاصة')),
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
            if (linked) ...[
              const SizedBox(height: 10),
              const DaftraSyncLine(),
            ],
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr('الفواتير {0}', [invoices.valueOrNull?.length ?? '']))),
                ButtonSegment(value: true, label: Text(tr('عروض الأسعار {0}', [quotes.valueOrNull?.length ?? '']))),
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
                    ? EmptyState(tr('لا توجد فواتير بعد'), icon: Icons.receipt_long_outlined)
                    : _InvoiceList(list),
              )
            else
              AsyncBody<List<Quote>>(
                value: quotes,
                onRetry: () => ref.invalidate(quotesProvider),
                builder: (list) => list.isEmpty
                    ? EmptyState(tr('لا توجد عروض أسعار بعد'), icon: Icons.request_quote_outlined)
                    : _QuoteList(list),
              ),
            const SizedBox(height: 14),
            if (!linked)
            Row(
              children: [
                if (!_quotes) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _recordPayment(context, ref, invoices.valueOrNull ?? const []),
                      child: Text(tr('تسجيل دفعة')),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showFormSheet(context, _NewDocSheet(quote: _quotes)),
                    child: Text(_quotes ? tr('عرض سعر جديد') : tr('فاتورة جديدة')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              linked
                  ? tr('الفواتير والدفعات تُضاف وتُعدّل في دفترة، وتظهر هنا تلقائيًا')
                  : tr('الفوترة الرسمية تبقى في نظام المحاسبة · هنا للمتابعة فقط'),
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
      showSnack(context, tr('لا توجد فواتير مفتوحة'));
      return;
    }
    target = await showModalBottomSheet<Invoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('اختر الفاتورة'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final i in open)
              ListTile(
                title: Text('${i.number} · ${i.clientName ?? ''}'),
                subtitle: Text(tr('المتبقي {0}', [money(i.remaining)])),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
  }
  if (target == null || !context.mounted) return;
  final amount = await promptNumber(context, tr('دفعة على {0}', [target.number]), label: tr('المبلغ (المتبقي {0})', [moneyShort(target.remaining)]));
  if (amount == null || amount <= 0 || !context.mounted) return;
  final inv = target;
  if (await runAction(context, () => ref.read(sectionRepoProvider).recordPayment(inv.id, amount), success: tr('سُجّلت الدفعة'))) {
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
      decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('مستحق التحصيل'), style: TextStyle(fontSize: 13, color: Color(0xFFC9CED6))),
          Text(money(s.due), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mini(tr('متأخر'), money(s.overdue), const Color(0xFFF7B79A))),
              const SizedBox(width: 10),
              Expanded(child: _mini(tr('محصّل هذا الشهر'), money(s.collectedThisMonth), const Color(0xFF9FE0B8))),
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
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            InkWell(
              onTap: () => showFormSheet(context, InvoiceSheet(invoiceId: list[i].id)),
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
                        Text(moneyShort(list[i].net), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
    if (i.isVoid) return tr('ملغاة · لا تُحسب في المستحق');
    final parts = <String>[];
    if (i.returned > 0) parts.add(tr('مرتجع {0}', [moneyShort(i.returned)]));
    if (i.status == InvoiceStatus.paid) return [...parts, tr('مدفوعة بالكامل')].join(' · ');
    if (i.paid > 0) parts.add(tr('دُفع {0} · المتبقي {1}', [moneyShort(i.paid), moneyShort(i.remaining)]));
    if (i.isOverdue) {
      parts.add(tr('متأخرة {0} يومًا', [DateTime.now().difference(i.dueDate).inDays]));
    } else {
      parts.add(tr('تستحق {0}', [formatShortDate(i.dueDate)]));
    }
    return parts.join(' · ');
  }

  Pill _pill(Invoice i) {
    if (i.isVoid) return Pill.neutral(tr('ملغاة'));
    if (i.isOverdue && i.paid > 0) return Pill.urgent(tr('جزئية · متأخرة'));
    if (i.isOverdue) return Pill.urgent(tr('متأخرة'));
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
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            InkWell(
              onTap: () => showFormSheet(context, QuoteSheet(quote: list[i])),
              child: Padding(
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
                          list[i].sentAt == null ? tr('لم يُرسل بعد') : tr('أُرسل {0}', [relativeDay(list[i].sentAt!)]),
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(moneyShort(list[i].total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (list[i].fromDaftra)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: _quotePill(list[i].status),
                    )
                  else
                  PopupMenuButton<QuoteStatus>(
                    tooltip: tr('تغيير الحالة'),
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
      showSnack(context, tr('اختر العميل وأدخل المبلغ'));
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
      title: widget.quote ? tr('عرض سعر جديد') : tr('فاتورة جديدة'),
      busy: _busy,
      onSubmit: _save,
      children: [
        FormCard(children: [
          FormDropdown<String>(
            label: tr('العميل *'),
            value: _clientId,
            items: {for (final c in clients) c.id: c.name},
            onChanged: (v) => setState(() => _clientId = v),
          ),
          FormRow(
            label: widget.quote ? tr('المبلغ قبل الضريبة *') : tr('الإجمالي شامل الضريبة *'),
            value: _amount == null ? tr('أدخل') : money(_amount!),
            muted: _amount == null,
            onTap: () async {
              final v = await promptNumber(context, tr('المبلغ'), label: tr('بالريال'));
              if (v != null) setState(() => _amount = v);
            },
          ),
          if (widget.quote)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('إضافة ضريبة ١٥٪'), style: TextStyle(fontSize: 14)),
              value: _vat,
              onChanged: (v) => setState(() => _vat = v),
            )
          else
            FormRow(
              label: tr('تاريخ الاستحقاق'),
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


/// تفاصيل الفاتورة وتعديلها: البيانات، الدفعات، الإلغاء، الحذف.
class InvoiceSheet extends ConsumerWidget {
  const InvoiceSheet({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(invoicesProvider).valueOrNull?.where((i) => i.id == invoiceId).firstOrNull;
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final canDelete = ref.watch(profileProvider).valueOrNull?.can(Permissions.dataDelete) ?? false;
    final repo = ref.read(sectionRepoProvider);
    if (inv == null) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    // فواتير دفترة: للعرض فقط، عدا ربطها بطلب ووصفها
    final locked = inv.fromDaftra;

    Future<void> save(Map<String, dynamic> changes, {String? success}) async {
      if (await runAction(context, () => repo.updateInvoice(inv.id, changes), success: success ?? tr('حُفظ التعديل'))) {
        refreshSections(ref);
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr('فاتورة {0}', [inv.number]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('إغلاق'))),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              inv.isVoid
                  ? tr('ملغاة')
                  : tr('المدفوع {0} · المتبقي {1}', [money(inv.paid), money(inv.remaining)]),
              style: TextStyle(fontSize: 13, color: inv.isOverdue ? AppColors.urgent : AppColors.muted, fontWeight: FontWeight.w600),
            ),
            if (locked) ...[
              const SizedBox(height: 10),
              _daftraNote(tr('من دفترة · المبالغ والدفعات تُعدّل في دفترة')),
            ],
            const SizedBox(height: 14),
            FormCard(children: [
              FormRow(
                label: tr('رقم الفاتورة'),
                value: inv.number,
                onTap: locked
                    ? null
                    : () async {
                        final v = await promptText(context, tr('رقم الفاتورة'), initial: inv.number);
                        if (v != null) await save({'number': v});
                      },
              ),
              if (locked)
                FormRow(label: tr('العميل'), value: inv.clientName ?? '—')
              else
                FormDropdown<String>(
                  label: tr('العميل'),
                  value: inv.clientId,
                  allowEmpty: false,
                  items: {for (final c in clients) c.id: c.name},
                  onChanged: (v) {
                    if (v != null) save({'client_id': v});
                  },
                ),
              FormDropdown<String>(
                label: tr('الطلب المرتبط'),
                value: inv.requestId,
                emptyLabel: tr('بدون'),
                items: {
                  for (final r in (inv.clientId == null
                      ? const <RequestItem>[]
                      : (ref.watch(clientRequestsProvider(inv.clientId!)).valueOrNull ?? const <RequestItem>[])))
                    r.id: '#${r.number} · ${r.title}',
                },
                onChanged: (v) => save({'request_id': v}, success: v == null ? tr('أُلغي الربط') : tr('رُبطت الفاتورة بالطلب')),
              ),
              FormRow(
                label: inv.returned > 0 ? tr('الإجمالي قبل المرتجع') : tr('الإجمالي شامل الضريبة'),
                value: money(inv.total),
                onTap: locked ? null : () async {
                  final v = await promptNumber(context, tr('الإجمالي'), label: tr('بالريال'), initial: inv.total);
                  if (v != null && v >= 0) await save({'total': v});
                },
              ),
              FormRow(
                label: tr('تاريخ الإصدار'),
                value: formatShortDate(inv.issueDate),
                onTap: locked ? null : () async {
                  final d = await pickDate(context, initial: inv.issueDate);
                  if (d != null) await save({'issue_date': d.toIso8601String().substring(0, 10)});
                },
              ),
              FormRow(
                label: tr('تاريخ الاستحقاق'),
                value: formatShortDate(inv.dueDate),
                onTap: locked ? null : () async {
                  final d = await pickDate(context, initial: inv.dueDate);
                  if (d != null) await save({'due_date': d.toIso8601String().substring(0, 10)});
                },
              ),
              FormRow(
                label: tr('الوصف'),
                value: (inv.notes == null || inv.notes!.isEmpty) ? tr('أضف وصفًا') : inv.notes!,
                muted: inv.notes == null || inv.notes!.isEmpty,
                onTap: () async {
                  final v = await promptText(context, tr('وصف الفاتورة'), initial: inv.notes, multiline: true);
                  if (v != null) await save({'notes': v});
                },
              ),
            ]),
            if (inv.returned > 0) ...[
              const SizedBox(height: 10),
              Text(tr('الصافي بعد المرتجع: {0}', [money(inv.net)]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(tr('المرتجعات'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (!locked && !inv.isVoid && inv.net > 0)
                  TextButton.icon(
                    onPressed: () async {
                      final amount = await promptNumber(context, tr('مرتجع جزئي على {0}', [inv.number]),
                          label: tr('المبلغ (الصافي الحالي {0})', [moneyShort(inv.net)]));
                      if (amount == null || amount <= 0 || !context.mounted) return;
                      if (amount > inv.net) {
                        showSnack(context, tr('المرتجع أكبر من صافي الفاتورة. للمرتجع الكامل استخدم «إلغاء الفاتورة»'));
                        return;
                      }
                      final reason = await promptText(context, tr('سبب المرتجع (اختياري)'), confirmLabel: tr('تسجيل'));
                      if (!context.mounted) return;
                      if (await runAction(context, () => repo.addReturn(inv.id, amount, reason), success: tr('سُجّل المرتجع'))) {
                        refreshSections(ref);
                      }
                    },
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(tr('مرتجع')),
                  ),
              ],
            ),
            if (inv.returns.isEmpty)
              Text(tr('لا توجد مرتجعات'), style: TextStyle(color: AppColors.muted, fontSize: 13))
            else
              CardBox(
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (var i = 0; i < inv.returns.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: AppColors.divider),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${money(inv.returns[i].amount)} · ${formatShortDate(inv.returns[i].date)}',
                                      style: const TextStyle(fontSize: 14)),
                                  if (inv.returns[i].reason != null)
                                    Text(inv.returns[i].reason!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ),
                          if (!locked)
                          IconButton(
                            tooltip: tr('حذف المرتجع'),
                            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.urgent),
                            onPressed: () async {
                              final ok = await confirmAction(context,
                                  title: tr('حذف المرتجع؟'),
                                  message: tr('مرتجع {0} سيُحذف ويعود صافي الفاتورة.', [money(inv.returns[i].amount)]),
                                  confirmLabel: tr('حذف'),
                                  destructive: true);
                              if (!ok || !context.mounted) return;
                              if (await runAction(context, () => repo.deleteReturn(inv.returns[i].id), success: tr('حُذف المرتجع'))) {
                                refreshSections(ref);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(tr('الدفعات'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (!locked && !inv.isVoid && inv.remaining > 0)
                  TextButton.icon(
                    onPressed: () => _recordPayment(context, ref, const [], invoice: inv),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('دفعة')),
                  ),
              ],
            ),
            if (inv.payments.isEmpty)
              Text(tr('لا توجد دفعات مسجلة'), style: TextStyle(color: AppColors.muted, fontSize: 13))
            else
              CardBox(
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (var i = 0; i < inv.payments.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: AppColors.divider),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('${money(inv.payments[i].amount)} · ${formatShortDate(inv.payments[i].paidAt)}',
                                  style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                          if (!locked)
                          IconButton(
                            tooltip: tr('حذف الدفعة'),
                            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.urgent),
                            onPressed: () async {
                              final ok = await confirmAction(context,
                                  title: tr('حذف الدفعة؟'),
                                  message: tr('دفعة {0} ستُحذف وتُعاد حالة الفاتورة تلقائيًا.', [money(inv.payments[i].amount)]),
                                  confirmLabel: tr('حذف'),
                                  destructive: true);
                              if (!ok || !context.mounted) return;
                              if (await runAction(context, () => repo.deletePayment(inv.payments[i].id), success: tr('حُذفت الدفعة'))) {
                                refreshSections(ref);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (!locked) ...[
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: inv.isVoid ? tr('استعادة الفاتورة؟') : tr('إلغاء الفاتورة؟'),
                  message: inv.isVoid
                      ? tr('تعود الفاتورة للحساب في المستحق، وتُحسب حالتها من دفعاتها.')
                      : tr('تبقى الفاتورة ظاهرة بحالة «ملغاة» ولا تُحسب في المستحق. يمكن استعادتها لاحقًا.'),
                  confirmLabel: inv.isVoid ? tr('استعادة') : tr('إلغاء الفاتورة'),
                );
                if (ok) await save({'status': inv.isVoid ? 'issued' : 'void'}, success: inv.isVoid ? tr('استُعيدت الفاتورة') : tr('أُلغيت الفاتورة'));
              },
              child: Text(inv.isVoid ? tr('استعادة الفاتورة') : tr('إلغاء الفاتورة (مرتجع كامل)')),
            ),
            if (canDelete) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirmAction(context,
                      title: tr('حذف الفاتورة {0}؟', [inv.number]),
                      message: tr('تنتقل إلى سلة المحذوفات ويمكن استرجاعها خلال ٣٠ يومًا.'),
                      confirmLabel: tr('حذف'),
                      destructive: true);
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.softDelete('invoices', [inv.id]), success: tr('نُقلت إلى السلة'))) {
                    refreshSections(ref);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: Icon(Icons.delete_outline, color: AppColors.urgent),
                label: Text(tr('حذف الفاتورة'), style: TextStyle(color: AppColors.urgent)),
              ),
            ],
            ],
          ],
        ),
      ),
    );
  }
}

/// تفاصيل عرض السعر وتعديله وتحويله إلى فاتورة.
class QuoteSheet extends ConsumerWidget {
  const QuoteSheet({super.key, required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(quotesProvider).valueOrNull?.where((x) => x.id == quote.id).firstOrNull ?? quote;
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final canDelete = ref.watch(profileProvider).valueOrNull?.can(Permissions.dataDelete) ?? false;
    final repo = ref.read(sectionRepoProvider);

    Future<void> save(Map<String, dynamic> changes, {String? success}) async {
      if (await runAction(context, () => repo.updateQuote(q.id, changes), success: success ?? tr('حُفظ التعديل'))) {
        refreshSections(ref);
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr('عرض سعر {0}', [q.number]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('إغلاق'))),
              ],
            ),
            const SizedBox(height: 12),
            if (q.fromDaftra) ...[
              _daftraNote(tr('من دفترة · يُعدّل ويُحوّل لفاتورة في دفترة')),
              const SizedBox(height: 12),
              FormCard(children: [
                FormRow(label: tr('العميل'), value: q.clientName ?? '—'),
                FormRow(label: tr('الإجمالي شامل الضريبة'), value: money(q.total)),
                FormRow(label: tr('الحالة'), value: q.status.label),
                FormRow(
                  label: tr('الوصف'),
                  value: (q.notes == null || q.notes!.isEmpty) ? tr('أضف وصفًا') : q.notes!,
                  muted: q.notes == null || q.notes!.isEmpty,
                  onTap: () async {
                    final v = await promptText(context, tr('وصف عرض السعر'), initial: q.notes, multiline: true);
                    if (v != null) await save({'notes': v});
                  },
                ),
              ]),
            ] else ...[
            FormCard(children: [
              FormDropdown<String>(
                label: tr('العميل'),
                value: q.clientId,
                allowEmpty: false,
                items: {for (final c in clients) c.id: c.name},
                onChanged: (v) {
                  if (v != null) save({'client_id': v});
                },
              ),
              FormRow(
                label: tr('المبلغ قبل الضريبة'),
                value: money(q.amount),
                onTap: () async {
                  final v = await promptNumber(context, tr('المبلغ قبل الضريبة'), initial: q.amount);
                  if (v != null && v >= 0) await save({'amount': v, 'vat_amount': q.vat > 0 ? v * 0.15 : 0});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('ضريبة ١٥٪ ({0})', [money(q.vat)]), style: const TextStyle(fontSize: 14)),
                value: q.vat > 0,
                onChanged: (v) => save({'vat_amount': v ? q.amount * 0.15 : 0}),
              ),
              FormDropdown<QuoteStatus>(
                label: tr('الحالة'),
                value: q.status,
                allowEmpty: false,
                items: {for (final s in QuoteStatus.values) s: s.label},
                onChanged: (v) {
                  if (v != null) save({'status': v.db, if (v == QuoteStatus.sent && q.sentAt == null) 'sent_at': DateTime.now().toIso8601String().substring(0, 10)});
                },
              ),
              FormRow(
                label: tr('الوصف'),
                value: (q.notes == null || q.notes!.isEmpty) ? tr('أضف وصفًا') : q.notes!,
                muted: q.notes == null || q.notes!.isEmpty,
                onTap: () async {
                  final v = await promptText(context, tr('وصف عرض السعر'), initial: q.notes, multiline: true);
                  if (v != null) await save({'notes': v});
                },
              ),
            ]),
            const SizedBox(height: 10),
            Text(tr('الإجمالي شامل الضريبة: {0}', [money(q.total)]),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: q.clientId == null
                  ? null
                  : () async {
                      final due = await pickDate(context, initial: DateTime.now().add(const Duration(days: 30)));
                      if (due == null || !context.mounted) return;
                      if (await runAction(context, () => repo.quoteToInvoice(q, due), success: tr('أُنشئت فاتورة من عرض السعر'))) {
                        refreshSections(ref);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
              child: Text(tr('تحويل إلى فاتورة')),
            ),
            if (canDelete) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirmAction(context,
                      title: tr('حذف عرض السعر {0}؟', [q.number]),
                      message: tr('ينتقل إلى سلة المحذوفات ويمكن استرجاعه خلال ٣٠ يومًا.'),
                      confirmLabel: tr('حذف'),
                      destructive: true);
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.softDelete('quotes', [q.id]), success: tr('نُقل إلى السلة'))) {
                    refreshSections(ref);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: Icon(Icons.delete_outline, color: AppColors.urgent),
                label: Text(tr('حذف عرض السعر'), style: TextStyle(color: AppColors.urgent)),
              ),
            ],
            ],
          ],
        ),
      ),
    );
  }
}


Widget _daftraNote(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.sync, size: 16, color: AppColors.accentText),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.accentText, fontWeight: FontWeight.w600))),
        ],
      ),
    );
