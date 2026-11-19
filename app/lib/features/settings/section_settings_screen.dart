import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ١٨ · إعدادات قسم: الحقول، القوائم، البيانات
class SectionSettingsScreen extends ConsumerStatefulWidget {
  const SectionSettingsScreen({super.key, required this.entity});
  final ConfigEntity entity;

  @override
  ConsumerState<SectionSettingsScreen> createState() => _SectionSettingsScreenState();
}

class _SectionSettingsScreenState extends ConsumerState<SectionSettingsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).valueOrNull;
    final canFields = me?.can(Permissions.settingsFields) ?? false;
    final canLists = canFields || (me?.can(Permissions.settingsLists) ?? false);
    return Scaffold(
      appBar: sectionAppBar('إعدادات ${widget.entity.label}', subtitle: 'ما يظهر في نموذج الإضافة وعلى البطاقة'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('الحقول')),
              ButtonSegment(value: 1, label: Text('القوائم')),
              ButtonSegment(value: 2, label: Text('البيانات')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 14),
          if (_tab == 0) _FieldsTab(entity: widget.entity, editable: canFields),
          if (_tab == 1) _ListsTab(entity: widget.entity, canEditStatuses: canFields, canEditOptions: canLists),
          if (_tab == 2) _DataTab(entity: widget.entity),
        ],
      ),
    );
  }
}

// ---------------- الحقول ----------------
class _FieldsTab extends ConsumerWidget {
  const _FieldsTab({required this.entity, required this.editable});
  final ConfigEntity entity;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(fieldSettingsProvider(entity));
    final repo = ref.read(sectionRepoProvider);

    Future<void> update(FieldSetting f, Map<String, dynamic> changes) async {
      if (await runAction(context, () => repo.updateField(f.id, changes))) {
        ref.invalidate(fieldSettingsProvider(entity));
        ref.invalidate(fieldConfigProvider(entity));
      }
    }

    return AsyncBody<List<FieldSetting>>(
      value: fields,
      onRetry: () => ref.invalidate(fieldSettingsProvider(entity)),
      builder: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!editable)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('ليست لديك صلاحية تعديل الحقول', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text('الحقل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                SizedBox(width: 56, child: Text('إلزامي', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                SizedBox(width: 56, child: Text('ظاهر', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
              ],
            ),
          ),
          CardBox(
            radius: 16,
            padding: EdgeInsets.zero,
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) async {
                if (!editable) return;
                final items = [...list];
                items.insert(newIndex, items.removeAt(oldIndex));
                if (await runAction(context, () => repo.reorderFields(items))) {
                  ref.invalidate(fieldSettingsProvider(entity));
                  ref.invalidate(fieldConfigProvider(entity));
                }
              },
              children: [
                for (var i = 0; i < list.length; i++)
                  Container(
                    key: ValueKey(list[i].id),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.divider)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        if (editable)
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.drag_indicator, color: Color(0xFF9AA2AE), size: 20),
                            ),
                          )
                        else
                          const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: (editable && !list[i].isLocked)
                                ? () => showFormSheet(context, FieldEditorSheet(entity: entity, field: list[i]))
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(list[i].label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text(list[i].meta, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (list[i].isLocked)
                          const SizedBox(
                            width: 112,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
                                SizedBox(width: 4),
                                Text('أساسي', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                              ],
                            ),
                          )
                        else ...[
                          SizedBox(
                            width: 56,
                            child: Switch(
                              value: list[i].required,
                              onChanged: editable ? (v) => update(list[i], {'required': v, if (v) 'visible': true}) : null,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Switch(
                              value: list[i].visible,
                              onChanged: editable ? (v) => update(list[i], {'visible': v, if (!v) 'required': false}) : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (editable) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showFormSheet(context, FieldEditorSheet(entity: entity, nextOrder: list.length + 1)),
              icon: const Icon(Icons.add),
              label: const Text('إضافة حقل مخصص'),
            ),
          ],
        ],
      ),
    );
  }
}

/// ١٩ · إضافة أو تعديل حقل
class FieldEditorSheet extends ConsumerStatefulWidget {
  const FieldEditorSheet({super.key, required this.entity, this.field, this.nextOrder = 99});
  final ConfigEntity entity;
  final FieldSetting? field;
  final int nextOrder;

  @override
  ConsumerState<FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends ConsumerState<FieldEditorSheet> {
  late final _label = TextEditingController(text: widget.field?.label ?? '');
  late FieldType _type = widget.field?.type ?? FieldType.text;
  late final List<String> _options = [...?widget.field?.options];
  late bool _required = widget.field?.required ?? false;
  late bool _onCard = widget.field?.showOnCard ?? false;
  bool _busy = false;

  bool get _isNew => widget.field == null;
  bool get _typeLocked => widget.field?.isSystem ?? false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _done() {
    ref.invalidate(fieldSettingsProvider(widget.entity));
    ref.invalidate(fieldConfigProvider(widget.entity));
    ref.invalidate(fieldCountsProvider);
    Navigator.pop(context);
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      showSnack(context, 'اكتب اسم الحقل');
      return;
    }
    if (_type == FieldType.list && _options.isEmpty) {
      showSnack(context, 'أضف خيارًا واحدًا على الأقل');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(sectionRepoProvider);
    final ok = await runAction(
      context,
      () => _isNew
          ? repo.createField(
              entity: widget.entity,
              label: label,
              type: _type,
              options: _type == FieldType.list ? _options : const [],
              required: _required,
              showOnCard: _onCard,
              sortOrder: widget.nextOrder,
            )
          : repo.updateField(widget.field!.id, {
              'label': label,
              if (!_typeLocked) 'type': _type.db,
              'options': _type == FieldType.list ? _options : <String>[],
              'required': _required,
              if (_required) 'visible': true,
              'show_on_card': _onCard,
            }),
      success: _isNew ? 'أُضيف الحقل' : 'حُفظت التغييرات',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _done();
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'حذف الحقل «${widget.field!.label}»؟',
      message: 'يختفي من النماذج والبطاقات، والقيم المُدخلة سابقًا تبقى محفوظة.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).deleteField(widget.field!.id), success: 'حُذف الحقل')) {
      if (mounted) _done();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: _isNew ? 'حقل جديد' : 'تعديل حقل',
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _label, autofocus: _isNew, decoration: const InputDecoration(labelText: 'اسم الحقل')),
        const SizedBox(height: 14),
        const Text('نوع الحقل', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in FieldType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: _type == t,
                showCheckmark: false,
                selectedColor: AppColors.ink,
                labelStyle: TextStyle(color: _type == t ? Colors.white : AppColors.ink),
                onSelected: _typeLocked ? null : (_) => setState(() => _type = t),
              ),
          ],
        ),
        if (_type == FieldType.list) ...[
          const SizedBox(height: 14),
          const Text('الخيارات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                InputChip(label: Text(o), onDeleted: () => setState(() => _options.remove(o))),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('خيار'),
                onPressed: () async {
                  final v = await promptText(context, 'خيار جديد', confirmLabel: 'إضافة');
                  if (v != null && !_options.contains(v)) setState(() => _options.add(v));
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        FormCard(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إلزامي عند الإضافة', style: TextStyle(fontSize: 14)),
            value: _required,
            onChanged: (v) => setState(() => _required = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('يظهر على البطاقة', style: TextStyle(fontSize: 14)),
            value: _onCard,
            onChanged: (v) => setState(() => _onCard = v),
          ),
        ]),
        if (!_isNew && !widget.field!.isSystem) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: AppColors.urgent),
            label: const Text('حذف الحقل', style: TextStyle(color: AppColors.urgent)),
          ),
        ],
      ],
    );
  }
}

// ---------------- القوائم ----------------
class _ListsTab extends ConsumerWidget {
  const _ListsTab({required this.entity, required this.canEditStatuses, required this.canEditOptions});
  final ConfigEntity entity;
  final bool canEditStatuses;
  final bool canEditOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(fieldSettingsProvider(entity));
    final statuses = ref.watch(statusLabelsProvider(entity)).valueOrNull ?? const <StatusLabel>[];
    final repo = ref.read(sectionRepoProvider);

    Future<void> saveOptions(FieldSetting f, List<String> options) async {
      if (await runAction(context, () => repo.updateField(f.id, {'options': options}))) {
        ref.invalidate(fieldSettingsProvider(entity));
        ref.invalidate(fieldConfigProvider(entity));
      }
    }

    return AsyncBody<List<FieldSetting>>(
      value: fields,
      builder: (list) {
        final lists = list.where((f) => f.type == FieldType.list && (f.options.isNotEmpty || f.isCustom)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lists.isEmpty && statuses.isEmpty)
              const EmptyState('لا توجد قوائم قابلة للتعديل في هذا القسم', icon: Icons.list_alt),
            for (final f in lists) ...[
              CardBox(
                radius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(f.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                        if (canEditOptions)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
                          onPressed: () async {
                            final v = await promptText(context, 'خيار جديد في ${f.label}', confirmLabel: 'إضافة');
                            if (v != null && !f.options.contains(v)) await saveOptions(f, [...f.options, v]);
                          },
                          child: const Text('+ إضافة'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in f.options)
                          InputChip(
                            label: Text(o),
                            onDeleted: canEditOptions ? () => saveOptions(f, f.options.where((x) => x != o).toList()) : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (statuses.isNotEmpty)
              CardBox(
                radius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الحالات', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const Text('يمكن تغيير الاسم واللون فقط، لأن التنبيهات مبنية عليها',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in statuses)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: canEditStatuses ? () => _editStatus(context, ref, s) : null,
                            child: Padding(padding: const EdgeInsets.all(2), child: statusPill(s.label, s.color)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _editStatus(BuildContext context, WidgetRef ref, StatusLabel s) async {
    final label = await promptText(context, 'اسم الحالة', initial: s.label);
    if (label == null || !context.mounted) return;
    final color = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('لون الحالة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in ['info', 'neutral', 'waiting', 'done', 'urgent'])
                    InkWell(onTap: () => Navigator.pop(ctx, c), child: statusPill(label, c)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).updateStatusLabel(entity, s.status, label, color ?? s.color),
        success: 'حُفظت الحالة')) {
      ref.invalidate(statusLabelsProvider(entity));
    }
  }
}

// ---------------- البيانات ----------------
class _DataTab extends ConsumerWidget {
  const _DataTab({required this.entity});
  final ConfigEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          radius: 16,
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text('تعديل وحذف ${entity.label}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('تحديد جماعي، تغيير الحالة، الحذف', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.go('/more/settings/data?table=${entity.table}'),
          ),
        ),
        if (entity == ConfigEntity.request) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.urgent,
              side: const BorderSide(color: AppColors.urgentBorder),
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: 'حذف كل الطلبات الملغاة؟',
                message: 'تنتقل إلى سلة المحذوفات، ويمكن استرجاعها خلال ٣٠ يومًا.',
                confirmLabel: 'حذف',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              var n = 0;
              if (await runAction(context, () async => n = await ref.read(sectionRepoProvider).deleteCancelledRequests())) {
                refreshSections(ref);
                if (context.mounted) showSnack(context, n == 0 ? 'لا توجد طلبات ملغاة' : 'نُقل $n طلبات إلى السلة');
              }
            },
            child: const Text('حذف كل الطلبات الملغاة'),
          ),
        ],
      ],
    );
  }
}
