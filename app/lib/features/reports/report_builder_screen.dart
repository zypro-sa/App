import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/web/web_tools.dart';
import '../../data/models.dart';
import '../../data/report_models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import 'custom_report.dart';
import 'report_common.dart';
import 'report_export.dart';

/// منشئ التقارير حسب المدخلات — معاينة حيّة لكل تغيير.
class ReportBuilderScreen extends ConsumerStatefulWidget {
  const ReportBuilderScreen({super.key, this.reportId});
  final String? reportId;

  @override
  ConsumerState<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _ReportBuilderScreenState extends ConsumerState<ReportBuilderScreen> {
  CustomConfig _c = const CustomConfig();
  SavedReport? _saved;
  bool _loaded = false;
  final _service = TextEditingController();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _set(CustomConfig c) => setState(() => _c = c);

  void _setSource(String s) {
    final groups = CustomDefs.groups(s).map((e) => e.$1);
    final metrics = CustomDefs.metrics(s).map((e) => e.$1);
    _set(_c.copyWith(
      source: s,
      groupBy: groups.contains(_c.groupBy) ? _c.groupBy : 'status',
      metric: metrics.contains(_c.metric) ? _c.metric : 'count',
      dateBasis: CustomDefs.bases(s).first.$1,
      status: const [],
      priority: const [],
      client: s == 'clients' || s == 'followups' ? null : _c.client,
      service: s == 'requests' ? _c.service : null,
    ));
    if (s != 'requests') _service.clear();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final (f, t) = _c.range;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: f, end: t),
    );
    if (r != null) _set(_c.copyWith(period: 'custom', from: dateOnly(r.start), to: dateOnly(r.end)));
  }

  Future<void> _save() async {
    final me = ref.read(profileProvider).valueOrNull;
    final mine = _saved != null && _saved!.ownerId == me?.id;
    final res = await showFormSheet<bool>(
      context,
      _SaveSheet(
        initialName: _saved?.name ?? customSummary(_c),
        shared: _saved?.shared ?? false,
        pinned: _saved?.pinned ?? false,
        onTv: _saved?.onTv ?? false,
        canShare: me?.can(Permissions.reportsView) ?? false,
        onSave: (name, shared, pinned, onTv) => ref.read(sectionRepoProvider).saveReport(
              id: mine ? _saved!.id : null,
              name: name,
              config: _c,
              shared: shared,
              pinned: pinned,
              onTv: onTv,
            ),
      ),
    );
    if (res == true && mounted) {
      ref.invalidate(savedReportsProvider);
      showSnack(context, tr('حُفظ التقرير'));
      context.pop();
    }
  }

  void _export(CustomResult r) {
    final labels = requestLabelsNow(ref);
    final rows = r.rows;
    downloadText(
      'zypro-custom-${DateTime.now().millisecondsSinceEpoch}.csv',
      toCsv([
        [customSummary(_c)],
        [],
        [tr('البند'), tr('القيمة'), tr('السجلات')],
        for (final row in rows) [customRowLabel(_c, row, labels), row.value, row.count],
        [tr('الإجمالي'), r.totalValue, r.totalCount],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    if (!_loaded && widget.reportId != null) {
      final list = ref.watch(savedReportsProvider).valueOrNull;
      final s = list?.where((r) => r.id == widget.reportId).firstOrNull;
      if (s != null) {
        _saved = s;
        _c = s.config;
        final svc = s.config.service ?? '';
        WidgetsBinding.instance.addPostFrameCallback((_) => _service.text = svc);
        _loaded = true;
      }
    } else {
      _loaded = true;
    }
    final finance = me?.can(Permissions.financeView) ?? false;
    final result = ref.watch(customReportProvider(_c.key));

    final preview = CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(customSummary(_c),
                    style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: tr('تنزيل Excel (CSV)'),
                icon: const Icon(Icons.download_outlined, size: 20),
                onPressed: result.valueOrNull == null ? null : () => _export(result.requireValue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncBody<CustomResult>(
            value: result,
            onRetry: () => ref.invalidate(customReportProvider(_c.key)),
            builder: (r) => CustomResultView(config: _c, result: r),
          ),
        ],
      ),
    );

    final form = _form(finance);

    return AmountsScope(child: Scaffold(
      appBar: sectionAppBar(
        _saved == null ? tr('تقرير جديد') : _saved!.name,
        subtitle: tr('اختر ما تريد قياسه وسيظهر التقرير مباشرة'),
        actions: [
          const AmountsToggle(),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: Text(tr('حفظ'))),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 400,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: form),
              ),
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [preview])),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [preview, const SizedBox(height: 16), ...form],
        );
      }),
    ));
  }

  List<Widget> _form(bool finance) {
    final labels = requestLabels(ref);
    final members = (ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[])
        .where((m) => m.isActive && !m.pending)
        .toList();
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final statuses = CustomDefs.statuses(_c.source, labels);
    final hasClient = !{'clients', 'followups'}.contains(_c.source);
    return [
      _Section(
        tr('١ · المصدر'),
        _Chips(
          options: CustomDefs.sources(finance: finance),
          selected: _c.source,
          onSelected: _setSource,
        ),
      ),
      _Section(
        tr('٢ · الفترة'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Chips(
              options: CustomDefs.periods(),
              selected: _c.period,
              onSelected: (p) => p == 'custom' ? _pickRange() : _set(_c.copyWith(period: p)),
            ),
            if (_c.period == 'custom')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('{0} – {1}', [formatShortDate(_c.range.$1), formatShortDate(_c.range.$2)]),
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            if (CustomDefs.bases(_c.source).length > 1) ...[
              const SizedBox(height: 10),
              Text(tr('حسب'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 4),
              _Chips(
                options: CustomDefs.bases(_c.source),
                selected: _c.dateBasis,
                onSelected: (b) => _set(_c.copyWith(dateBasis: b)),
              ),
            ],
          ],
        ),
      ),
      _Section(
        tr('٣ · التجميع'),
        _Chips(
          options: CustomDefs.groups(_c.source),
          selected: _c.groupBy,
          onSelected: (g) => _set(_c.copyWith(
            groupBy: g,
            view: CustomDefs.isTime(g) && _c.view != 'table' ? 'line' : (_c.view == 'line' && !CustomDefs.isTime(g) ? 'bar' : _c.view),
          )),
        ),
      ),
      _Section(
        tr('٤ · المقياس'),
        _Chips(
          options: CustomDefs.metrics(_c.source),
          selected: _c.metric,
          onSelected: (m) => _set(_c.copyWith(metric: m)),
        ),
      ),
      _Section(
        tr('٥ · طريقة العرض'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (v, label, icon) in CustomDefs.views())
              ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: _c.view == v,
                showCheckmark: false,
                onSelected: (_) => _set(_c.copyWith(view: v)),
              ),
          ],
        ),
      ),
      _Section(
        tr('٦ · التصفية (اختياري)'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('الحالة'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (code, label) in statuses)
                  FilterChip(
                    label: Text(label),
                    selected: _c.status.contains(code),
                    onSelected: (on) => _set(_c.copyWith(
                      status: on ? [..._c.status, code] : _c.status.where((s) => s != code).toList(),
                    )),
                  ),
              ],
            ),
            if (_c.source == 'requests' || _c.source == 'tasks') ...[
              const SizedBox(height: 10),
              Text(tr('الأولوية'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in Priority.values)
                    FilterChip(
                      label: Text(p.label),
                      selected: _c.priority.contains(p.db),
                      onSelected: (on) => _set(_c.copyWith(
                        priority: on ? [..._c.priority, p.db] : _c.priority.where((s) => s != p.db).toList(),
                      )),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FormCard(children: [
              FormDropdown<String>(
                label: CustomDefs.personLabel(_c.source),
                value: _c.person,
                emptyLabel: tr('الكل'),
                items: {for (final m in members) m.id: m.name},
                onChanged: (v) => _set(_c.copyWith(person: v)),
              ),
              if (hasClient)
                FormDropdown<String>(
                  label: tr('العميل'),
                  value: _c.client,
                  emptyLabel: tr('كل العملاء'),
                  items: {for (final x in clients) x.id: x.name},
                  onChanged: (v) => _set(_c.copyWith(client: v)),
                ),
            ]),
            if (_c.source == 'requests') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _service,
                decoration: InputDecoration(
                  labelText: tr('نوع الخدمة (مطابق تمامًا)'),
                  suffixIcon: IconButton(
                    tooltip: tr('تطبيق'),
                    icon: const Icon(Icons.check),
                    onPressed: () => _set(_c.copyWith(service: _service.text.trim().isEmpty ? null : _service.text.trim())),
                  ),
                ),
                onSubmitted: (v) => _set(_c.copyWith(service: v.trim().isEmpty ? null : v.trim())),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onSelected});
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, label) in options)
          ChoiceChip(label: Text(label), selected: selected == v, showCheckmark: false, onSelected: (_) => onSelected(v)),
      ],
    );
  }
}

class _SaveSheet extends StatefulWidget {
  const _SaveSheet({
    required this.initialName,
    required this.shared,
    required this.pinned,
    required this.onTv,
    required this.canShare,
    required this.onSave,
  });
  final String initialName;
  final bool shared;
  final bool pinned;
  final bool onTv;
  final bool canShare;
  final Future<void> Function(String name, bool shared, bool pinned, bool onTv) onSave;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late bool _shared = widget.shared;
  late bool _pinned = widget.pinned;
  late bool _onTv = widget.onTv;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => widget.onSave(name, _shared, _pinned, _onTv));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: tr('حفظ التقرير'),
      busy: _busy,
      onSubmit: _submit,
      children: [
        TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('اسم التقرير'))),
        const SizedBox(height: 8),
        if (widget.canShare)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
            title: Text(tr('مشاركة مع الفريق')),
            subtitle: Text(tr('يراه الجميع، وكلٌّ يرى فيه البيانات المسموحة له فقط')),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
          title: Text(tr('تثبيت في «نظرة عامة»')),
        ),
        if (widget.canShare)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _onTv,
            onChanged: (v) => setState(() => _onTv = v),
            title: Text(tr('عرضه على شاشة المكتب')),
            subtitle: Text(tr('يظهر كشريحة إضافية')),
          ),
      ],
    );
  }
}
