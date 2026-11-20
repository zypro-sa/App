import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

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
      appBar: sectionAppBar(tr('إعدادات {0}', [widget.entity.label]), subtitle: tr('ما يظهر في نموذج الإضافة وعلى البطاقة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(tr('الحقول'))),
              ButtonSegment(value: 1, label: Text(tr('القوائم'))),
              ButtonSegment(value: 2, label: Text(tr('البيانات'))),
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
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(tr('ليست لديك صلاحية تعديل الحقول'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(tr('الحقل'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                SizedBox(width: 56, child: Text(tr('إلزامي'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                SizedBox(width: 56, child: Text(tr('ظاهر'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
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
                      border: i == 0 ? null : Border(top: BorderSide(color: AppColors.divider)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        if (editable)
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.drag_indicator, color: AppColors.faint, size: 20),
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
                                  Text(list[i].meta, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (list[i].isLocked)
                          SizedBox(
                            width: 112,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
                                SizedBox(width: 4),
                                Text(tr('أساسي'), style: TextStyle(fontSize: 11, color: AppColors.muted)),
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
              label: Text(tr('إضافة حقل مخصص')),
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
  late final _label = TextEditingController(text: widget.field?.labelAr ?? '');
  late final _labelEn = TextEditingController(text: widget.field?.labelEn ?? '');
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
    _labelEn.dispose();
    super.dispose();
  }

  void _done() {
    ref.invalidate(fieldSettingsProvider(widget.entity));
    ref.invalidate(fieldConfigProvider(widget.entity));
    ref.invalidate(fieldCountsProvider);
    Navigator.pop(context);
  }

  Future<void> _save() async {
    final labelEn = _labelEn.text.trim();
    final label = _label.text.trim().isEmpty ? labelEn : _label.text.trim();
    if (label.isEmpty) {
      showSnack(context, tr('اكتب اسم الحقل'));
      return;
    }
    if (_type == FieldType.list && _options.isEmpty) {
      showSnack(context, tr('أضف خيارًا واحدًا على الأقل'));
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
              labelEn: labelEn.isEmpty ? null : labelEn,
              type: _type,
              options: _type == FieldType.list ? _options : const [],
              required: _required,
              showOnCard: _onCard,
              sortOrder: widget.nextOrder,
            )
          : repo.updateField(widget.field!.id, {
              'label': label,
              'label_en': labelEn.isEmpty ? null : labelEn,
              if (!_typeLocked) 'type': _type.db,
              'options': _type == FieldType.list ? _options : <String>[],
              'required': _required,
              if (_required) 'visible': true,
              'show_on_card': _onCard,
            }),
      success: _isNew ? tr('أُضيف الحقل') : tr('حُفظت التغييرات'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _done();
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: tr('حذف الحقل «{0}»؟', [widget.field!.label]),
      message: tr('يختفي من النماذج والبطاقات، والقيم المُدخلة سابقًا تبقى محفوظة.'),
      confirmLabel: tr('حذف'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).deleteField(widget.field!.id), success: tr('حُذف الحقل'))) {
      if (mounted) _done();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: _isNew ? tr('حقل جديد') : tr('تعديل حقل'),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _label, autofocus: _isNew, decoration: InputDecoration(labelText: tr('اسم الحقل بالعربية'))),
        const SizedBox(height: 10),
        TextField(
          controller: _labelEn,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('اسم الحقل بالإنجليزية'), hintText: tr('اختياري · يظهر لمن يستخدم التطبيق بالإنجليزية')),
        ),
        const SizedBox(height: 14),
        Text(tr('نوع الحقل'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
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
                selectedColor: AppColors.inkBlock,
                labelStyle: TextStyle(color: _type == t ? AppColors.onInkBlock : AppColors.ink),
                onSelected: _typeLocked ? null : (_) => setState(() => _type = t),
              ),
          ],
        ),
        if (_type == FieldType.list) ...[
          const SizedBox(height: 14),
          Text(tr('الخيارات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _options)
                InputChip(label: Text(o), onDeleted: () => setState(() => _options.remove(o))),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(tr('خيار')),
                onPressed: () async {
                  final v = await promptText(context, tr('خيار جديد'), confirmLabel: tr('إضافة'));
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
            title: Text(tr('إلزامي عند الإضافة'), style: TextStyle(fontSize: 14)),
            value: _required,
            onChanged: (v) => setState(() => _required = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('يظهر على البطاقة'), style: TextStyle(fontSize: 14)),
            value: _onCard,
            onChanged: (v) => setState(() => _onCard = v),
          ),
        ]),
        if (!_isNew && !widget.field!.isSystem) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.urgent),
            label: Text(tr('حذف الحقل'), style: TextStyle(color: AppColors.urgent)),
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
              EmptyState(tr('لا توجد قوائم قابلة للتعديل في هذا القسم'), icon: Icons.list_alt),
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
                            final v = await promptText(context, tr('خيار جديد في {0}', [f.label]), confirmLabel: tr('إضافة'));
                            if (v != null && !f.options.contains(v)) await saveOptions(f, [...f.options, v]);
                          },
                          child: Text(tr('+ إضافة')),
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
                    Text(tr('الحالات'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(tr('يمكن تغيير الاسم واللون فقط، لأن التنبيهات مبنية عليها'),
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
    final label = await promptText(context, tr('اسم الحالة بالعربية'), initial: s.labelAr);
    if (label == null || !context.mounted) return;
    final labelEn = await promptText(context, tr('اسم الحالة بالإنجليزية'),
        initial: s.labelEn ?? '', label: tr('اختياري · يظهر لمن يستخدم التطبيق بالإنجليزية'), confirmLabel: tr('التالي'));
    if (!context.mounted) return;
    final color = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('لون الحالة'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
    if (await runAction(context, () => ref.read(sectionRepoProvider).updateStatusLabel(entity, s.status, label, color ?? s.color, labelEn: (labelEn ?? '').isEmpty ? s.labelEn : labelEn),
        success: tr('حُفظت الحالة'))) {
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
            title: Text(tr('تعديل وحذف {0}', [entity.label]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(tr('تحديد جماعي، تغيير الحالة، الحذف'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            trailing: Icon(AppIcons.forward),
            onTap: () => context.go('/more/settings/data?table=${entity.table}'),
          ),
        ),
        if (entity == ConfigEntity.request) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.urgent,
              side: BorderSide(color: AppColors.urgentBorder),
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: tr('حذف كل الطلبات الملغاة؟'),
                message: tr('تنتقل إلى سلة المحذوفات، ويمكن استرجاعها خلال ٣٠ يومًا.'),
                confirmLabel: tr('حذف'),
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              var n = 0;
              if (await runAction(context, () async => n = await ref.read(sectionRepoProvider).deleteCancelledRequests())) {
                refreshSections(ref);
                if (context.mounted) showSnack(context, n == 0 ? tr('لا توجد طلبات ملغاة') : tr('نُقل {0} طلبات إلى السلة', [n]));
              }
            },
            child: Text(tr('حذف كل الطلبات الملغاة')),
          ),
        ],
      ],
    );
  }
}
