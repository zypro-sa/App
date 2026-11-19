import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ٢٠ · إدارة البيانات: تحديد جماعي، تعديل، تغيير الحالة، حذف
class BulkManageScreen extends ConsumerStatefulWidget {
  const BulkManageScreen({super.key, this.initialTable = 'requests'});
  final String initialTable;

  @override
  ConsumerState<BulkManageScreen> createState() => _BulkManageScreenState();
}

class _Section {
  const _Section(this.table, this.label, this.single, this.titleField, this.statuses);
  final String table;
  final String label;
  final String single; // اسم العنصر المفرد للرسائل
  final String titleField;
  final Map<String, String> statuses;
}

final _sections = [
  _Section('requests', 'الطلبات', 'طلب', 'title', {for (final s in RequestStatus.values) s.db: s.label}),
  _Section('tasks', 'المهام', 'مهمة', 'title', {for (final s in TaskStatus.values) s.db: s.label}),
  const _Section('clients', 'العملاء', 'عميل', 'name', {'lead': 'محتمل', 'active': 'نشط', 'inactive': 'متوقف'}),
  const _Section('meetings', 'الاجتماعات', 'اجتماع', 'title',
      {'scheduled': 'مجدول', 'done': 'منعقد', 'cancelled': 'ملغى', 'postponed': 'مؤجل'}),
  const _Section('notes', 'الملاحظات', 'ملاحظة', 'content', {}),
];

class _BulkManageScreenState extends ConsumerState<BulkManageScreen> {
  late _Section _section = _sections.firstWhere((s) => s.table == widget.initialTable, orElse: () => _sections.first);
  final Set<String> _selected = {};

  String _title(Map<String, dynamic> r) {
    final t = (r[_section.titleField] ?? '') as String;
    return _section.table == 'requests' ? '#${r['number']} · $t' : t;
  }

  String _meta(Map<String, dynamic> r) {
    final parts = <String>[];
    final st = r['status'] as String?;
    if (st != null) parts.add(_section.statuses[st] ?? st);
    if (r['client'] is Map) parts.add(r['client']['name'] as String);
    if (r['city'] != null) parts.add(r['city'] as String);
    final date = r['start_at'] ?? r['due_at'] ?? r['created_at'];
    if (date != null) parts.add(relativeDay(DateTime.parse(date as String).toLocal()));
    return parts.join(' · ');
  }

  void _after() {
    _selected.clear();
    refreshSections(ref);
    setState(() {});
  }

  Future<void> _delete() async {
    final n = _selected.length;
    final ok = await confirmAction(
      context,
      title: 'حذف $n ${n == 1 ? _section.single : 'عناصر'}؟',
      message: 'تنتقل إلى سلة المحذوفات، ويمكنك استرجاعها خلال ٣٠ يومًا. العناصر المرتبطة بها تبقى كما هي.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).softDelete(_section.table, _selected.toList()),
        success: 'نُقل $n إلى السلة')) {
      _after();
    }
  }

  Future<void> _changeStatus() async {
    final status = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('الحالة الجديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final e in _section.statuses.entries)
              ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
          ],
        ),
      ),
    );
    if (status == null || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).setStatus(_section.table, _selected.toList(), status),
        success: 'تم تغيير الحالة')) {
      _after();
    }
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final v = await promptText(
      context,
      'تعديل ${_section.single}',
      initial: (r[_section.titleField] ?? '') as String,
      multiline: _section.table == 'notes',
    );
    if (v == null || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).rename(_section.table, r['id'] as String, _section.titleField, v),
        success: 'حُفظ التعديل')) {
      refreshSections(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(manageRowsProvider(_section.table));
    final all = rows.valueOrNull ?? const <Map<String, dynamic>>[];
    final n = _selected.length;
    final canDelete = ref.watch(profileProvider).valueOrNull?.can(Permissions.dataDelete) ?? false;

    return Scaffold(
      appBar: sectionAppBar(
        'إدارة البيانات',
        subtitle: n > 0 ? 'محدد $n من ${all.length}' : '${all.length} ${_section.label}',
        actions: [
          TextButton(
            onPressed: all.isEmpty
                ? null
                : () => setState(() {
                      if (_selected.length == all.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(all.map((r) => r['id'] as String));
                      }
                    }),
            child: Text(n > 0 && n == all.length ? 'إلغاء التحديد' : 'تحديد الكل'),
          ),
        ],
      ),
      bottomNavigationBar: n == 0
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('$n محدد', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    if (_section.statuses.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: _changeStatus,
                        child: const Text('تغيير الحالة'),
                      ),
                    const SizedBox(width: 6),
                    if (canDelete)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC2410C), minimumSize: const Size(0, 40)),
                      onPressed: _delete,
                      child: const Text('حذف'),
                    ),
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _sections[i];
                final sel = s.table == _section.table;
                return ChoiceChip(
                  label: Text(s.label),
                  selected: sel,
                  showCheckmark: false,
                  selectedColor: AppColors.ink,
                  labelStyle: TextStyle(color: sel ? Colors.white : AppColors.ink),
                  onSelected: (_) => setState(() {
                    _section = s;
                    _selected.clear();
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          AsyncBody<List<Map<String, dynamic>>>(
            value: rows,
            onRetry: () => ref.invalidate(manageRowsProvider(_section.table)),
            builder: (list) => list.isEmpty
                ? const EmptyState('لا توجد بيانات هنا')
                : CardBox(
                    radius: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: AppColors.divider),
                          Row(
                            children: [
                              Checkbox(
                                value: _selected.contains(list[i]['id']),
                                onChanged: (v) => setState(() {
                                  final id = list[i]['id'] as String;
                                  v == true ? _selected.add(id) : _selected.remove(id);
                                }),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_title(list[i]),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      Text(_meta(list[i]), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () => _edit(list[i]),
                                icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.subtle),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
