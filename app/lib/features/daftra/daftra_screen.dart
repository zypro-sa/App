import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// مزامنة صامتة مع دفترة مرة عند فتح التطبيق (الخادم يمنع تكرارها خلال ١٥ دقيقة).
class DaftraAutoSync extends ConsumerStatefulWidget {
  const DaftraAutoSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<DaftraAutoSync> createState() => _DaftraAutoSyncState();
}

class _DaftraAutoSyncState extends ConsumerState<DaftraAutoSync> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _run);
  }

  Future<void> _run() async {
    try {
      final res = await ref.read(sectionRepoProvider).daftraSync(auto: true);
      if (mounted && res['skipped'] == null) refreshSections(ref);
    } catch (_) {
      // تظهر الأخطاء في شاشة «ربط دفترة» فقط
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// سطر صغير يوضح آخر مزامنة، مع زر للمزامنة الآن.
class DaftraSyncLine extends ConsumerStatefulWidget {
  const DaftraSyncLine({super.key});

  @override
  ConsumerState<DaftraSyncLine> createState() => _DaftraSyncLineState();
}

class _DaftraSyncLineState extends ConsumerState<DaftraSyncLine> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(daftraStateProvider).valueOrNull;
    if (state == null || !state.enabled) return const SizedBox.shrink();
    final when = state.lastOkAt == null ? '—' : '${relativeDay(state.lastOkAt!)} ${formatTime(state.lastOkAt!)}';
    return CardBox(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.sync, size: 18, color: AppColors.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('مرتبطة بدفترة · للعرض فقط'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(tr('آخر مزامنة: {0}', [when]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _syncNow,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('مزامنة الآن')),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(sectionRepoProvider).daftraSync(), success: tr('تمت المزامنة مع دفترة'));
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) refreshSections(ref);
  }
}

/// شاشة ربط دفترة: الحالة، التجربة، والمزامنة.
class DaftraScreen extends ConsumerStatefulWidget {
  const DaftraScreen({super.key});

  @override
  ConsumerState<DaftraScreen> createState() => _DaftraScreenState();
}

class _DaftraScreenState extends ConsumerState<DaftraScreen> {
  bool _busy = false;
  Map<String, dynamic>? _result;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    if (me != null && !me.can(Permissions.financeManage)) {
      return Scaffold(
        appBar: sectionAppBar(tr('ربط دفترة')),
        body: EmptyState(tr('ليست لديك صلاحية المالية'), icon: Icons.lock_outline),
      );
    }
    final state = ref.watch(daftraStateProvider);

    return Scaffold(
      appBar: sectionAppBar(tr('ربط دفترة'), subtitle: tr('دفترة هي المصدر · التطبيق للمتابعة')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(daftraStateProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<DaftraSyncState>(
              value: state,
              onRetry: () => ref.invalidate(daftraStateProvider),
              builder: (s) => _statusCard(s),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(dry: true),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: Text(tr('تجربة دون تعديل')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(dry: false),
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(tr('مزامنة الآن')),
                  ),
                ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              _resultCard(_result!),
            ],
            const SizedBox(height: 18),
            _howItWorks(),
          ],
        ),
      ),
    );
  }

  Future<void> _run({required bool dry}) async {
    if (!dry) {
      final ok = await confirmAction(
        context,
        title: tr('مزامنة البيانات من دفترة؟'),
        message: tr('تُحدَّث الفواتير والدفعات والمرتجعات وعروض الأسعار لتطابق دفترة. الدفعات المسجلة في التطبيق على فواتير دفترة تُستبدل بدفعات دفترة.'),
        confirmLabel: tr('مزامنة'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(sectionRepoProvider).daftraSync(dryRun: dry);
      if (!mounted) return;
      setState(() => _result = r);
      if (!dry) {
        refreshSections(ref);
        showSnack(context, tr('تمت المزامنة مع دفترة'));
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('تعذّرت المزامنة: {0}', ['$e'.replaceFirst('Exception: ', '')]));
      ref.invalidate(daftraStateProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statusCard(DaftraSyncState s) {
    final (fg, bg, label) = s.lastError != null
        ? (AppColors.urgent, AppColors.urgentSoft, tr('آخر محاولة فشلت'))
        : s.enabled
            ? (AppColors.done, AppColors.doneSoft, tr('مرتبطة وتعمل'))
            : (AppColors.muted, AppColors.neutralSoft, tr('لم تُربط بعد'));
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('حالة الربط'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              Pill(label, fg: fg, bg: bg),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('آخر مزامنة ناجحة: {0}', [s.lastOkAt == null ? '—' : '${formatShortDate(s.lastOkAt!)} ${formatTime(s.lastOkAt!)}']),
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          if (s.lastError != null) ...[
            const SizedBox(height: 8),
            Text(s.lastError!, style: TextStyle(fontSize: 13, color: AppColors.urgent)),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    Map<String, dynamic> g(String k) => r[k] is Map ? Map<String, dynamic>.from(r[k] as Map) : const {};
    final fetched = g('fetched');
    final clients = g('clients');
    final invoices = g('invoices');
    final payments = g('payments');
    final returns = g('returns');
    final quotes = g('quotes');
    final mismatched = (payments['mismatched'] as List?) ?? const [];
    final warnings = (r['warnings'] as List?) ?? const [];
    final dry = r['dry_run'] == true;

    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
              Text(value, style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dry ? tr('نتيجة التجربة (لم يُعدَّل شيء)') : tr('نتيجة المزامنة'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          line(tr('قُرئ من دفترة'), tr('{0} عميل · {1} فاتورة · {2} دفعة · {3} عرض · {4} مرتجع', [
            fetched['clients'] ?? 0, fetched['invoices'] ?? 0, fetched['payments'] ?? 0, fetched['estimates'] ?? 0,
            fetched['refunds'] ?? 0,
          ])),
          line(tr('العملاء'), tr('جديد {0} · رُبط {1}', [clients['created'] ?? 0, clients['linked'] ?? 0])),
          line(tr('الفواتير'), tr('جديدة {0} · محدّثة {1} · محذوفة {2}', [
            invoices['created'] ?? 0, invoices['updated'] ?? 0, invoices['removed'] ?? 0,
          ])),
          line(tr('تُركت'), tr('مسودات {0} · مرتجعة بالكامل {1}', [
            invoices['skipped_drafts'] ?? 0, invoices['skipped_fully_returned'] ?? 0,
          ])),
          line(tr('الدفعات'), tr('جديدة {0} · محدّثة {1} · محذوفة {2}', [
            payments['added'] ?? 0, payments['updated'] ?? 0, payments['removed'] ?? 0,
          ])),
          line(tr('المرتجعات'), tr('سُجّل {0} · حُذف {1}', [returns['set'] ?? 0, returns['removed'] ?? 0])),
          line(tr('عروض الأسعار'), tr('جديدة {0} · محدّثة {1} · محذوفة {2}', [
            quotes['created'] ?? 0, quotes['updated'] ?? 0, quotes['removed'] ?? 0,
          ])),
          if (mismatched.isNotEmpty || warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('تنبيهات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.waiting)),
            for (final w in [...mismatched, ...warnings])
              Text('• $w', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _howItWorks() {
    TextStyle s = TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('كيف يعمل الربط؟'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(tr('• يقرأ التطبيق من دفترة فقط، ولا يكتب فيها أي شيء.'), style: s),
        Text(tr('• يُزامن العملاء والفواتير والدفعات والمرتجعات وعروض الأسعار تلقائيًا عند فتح التطبيق (مرة كل ١٥ دقيقة كحد أقصى).'), style: s),
        Text(tr('• الفواتير القادمة من دفترة للعرض فقط، ويبقى بإمكانك ربطها بطلب وإضافة وصف لها.'), style: s),
        Text(tr('• أي تعديل على فاتورة أو دفعة يتم في دفترة، ويظهر هنا في المزامنة التالية.'), style: s),
      ],
    );
  }
}
