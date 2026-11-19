import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/forms.dart' show customFieldRows, missingRequired, promptNumber, money;
import '../../widgets/common.dart';

enum QuickAddType {
  task('مهمة'),
  request('طلب'),
  meeting('اجتماع'),
  followup('متابعة'),
  note('ملاحظة');

  const QuickAddType(this.label);
  final String label;
}

/// ٧ · إضافة سريعة
Future<void> showQuickAdd(BuildContext context, {QuickAddType initial = QuickAddType.task}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => QuickAddSheet(initial: initial),
  );
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.initial = QuickAddType.task});
  final QuickAddType initial;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  late QuickAddType _type = widget.initial;
  final _title = TextEditingController();
  final _counterpart = TextEditingController();
  DateTime? _when;
  Priority _priority = Priority.medium;
  String? _clientId;
  String? _assigneeId;
  int _duration = 30;
  MeetingType _meetingType = MeetingType.inPerson;
  FollowupDirection _direction = FollowupDirection.promised;
  String? _serviceType;
  num? _value;
  final _location = TextEditingController();
  final Map<String, dynamic> _custom = {};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _counterpart.dispose();
    _location.dispose();
    super.dispose();
  }

  ConfigEntity? get _entity => switch (_type) {
        QuickAddType.task => ConfigEntity.task,
        QuickAddType.request => ConfigEntity.request,
        QuickAddType.meeting => ConfigEntity.meeting,
        _ => null,
      };

  FieldConfig _cfg() {
    final e = _entity;
    if (e == null) return FieldConfig(const []);
    return ref.read(fieldConfigProvider(e)).valueOrNull ?? FieldConfig(const []);
  }

  /// يتحقق من الحقول التي جعلها المالك إلزامية.
  String? _missingConfigured() {
    final cfg = _cfg();
    bool req(String k) => cfg.isVisible(k) && cfg.isRequired(k);
    switch (_type) {
      case QuickAddType.request:
        if (req('due_date') && _when == null) return 'حدّد ${cfg.labelOf('due_date', 'الموعد النهائي')}';
        if (req('service_type') && _serviceType == null) return 'اختر ${cfg.labelOf('service_type', 'نوع الخدمة')}';
        if (req('estimated_value') && _value == null) return 'أدخل ${cfg.labelOf('estimated_value', 'القيمة التقديرية')}';
      case QuickAddType.task:
        if (req('due_at') && _when == null) return 'حدّد ${cfg.labelOf('due_at', 'الموعد')}';
        if (req('client_id') && _clientId == null) return 'اختر ${cfg.labelOf('client_id', 'العميل')}';
      case QuickAddType.meeting:
        if (req('client_id') && _clientId == null) return 'اختر ${cfg.labelOf('client_id', 'العميل')}';
        if (req('location') && _location.text.trim().isEmpty) return 'أدخل ${cfg.labelOf('location', 'المكان')}';
      default:
        break;
    }
    return missingRequired(cfg.customVisible, _custom);
  }

  bool get _needsDate =>
      _type == QuickAddType.meeting || _type == QuickAddType.followup;

  String get _hint {
    switch (_type) {
      case QuickAddType.task:
        return 'مثال: إرسال عرض السعر المحدّث';
      case QuickAddType.request:
        return 'مثال: إعداد دراسة جدوى لفرع جديد';
      case QuickAddType.meeting:
        return 'مثال: مراجعة عقد الخدمات السنوي';
      case QuickAddType.followup:
        return 'مثال: الرد على استفسار العميل';
      case QuickAddType.note:
        return 'اكتب فكرتك أو ملاحظة المكالمة';
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _when != null ? TimeOfDay.fromDateTime(_when!) : const TimeOfDay(hour: 10, minute: 0),
    );
    if (!mounted) return;
    setState(() {
      _when = time == null
          ? DateTime(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final problem = title.isEmpty
        ? 'اكتب العنوان أولًا'
        : (_needsDate && _when == null)
            ? 'حدّد الموعد'
            : (_type == QuickAddType.request && _clientId == null)
                ? 'اختر العميل'
                : _missingConfigured();
    if (problem != null) {
      showSnack(context, problem);
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      switch (_type) {
        case QuickAddType.task:
          await repo.createTask(
            title: title,
            priority: _priority,
            dueAt: _when,
            assigneeId: _assigneeId,
            clientId: _clientId,
            custom: Map.of(_custom),
          );
        case QuickAddType.request:
          await repo.createRequest(
            title: title,
            clientId: _clientId!,
            priority: _priority,
            dueDate: _when,
            serviceType: _serviceType,
            estimatedValue: _value,
            custom: Map.of(_custom),
          );
        case QuickAddType.meeting:
          await repo.createMeeting(
            title: title,
            startAt: _when!,
            durationMinutes: _duration,
            type: _meetingType,
            clientId: _clientId,
            location: _location.text.trim(),
            custom: Map.of(_custom),
          );
        case QuickAddType.followup:
          await repo.createFollowup(
            title: title,
            direction: _direction,
            dueAt: _when!,
            counterpart: _counterpart.text.trim(),
          );
        case QuickAddType.note:
          await repo.createNote(title);
      }
      refreshSections(ref);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text('تمت إضافة ${_type.label}')));
      }
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّرت الإضافة: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final team = ref.watch(teamProvider).valueOrNull ?? const <Profile>[];
    final me = ref.watch(profileProvider).valueOrNull;
    final canAssign = me?.can(Permissions.tasksAssign) ?? false;
    final allowedTypes = QuickAddType.values.where((t) => switch (t) {
          QuickAddType.request => me?.can(Permissions.requestsManage) ?? false,
          QuickAddType.meeting => me?.can(Permissions.meetingsManage) ?? false,
          _ => true,
        }).toList();
    if (!allowedTypes.contains(_type)) _type = QuickAddType.task;
    final entity = _entity;
    final cfg = entity == null
        ? FieldConfig(const [])
        : (ref.watch(fieldConfigProvider(entity)).valueOrNull ?? FieldConfig(const []));
    final dueKey = _type == QuickAddType.request ? 'due_date' : (_type == QuickAddType.task ? 'due_at' : 'start_at');
    String star(String key, String label) => cfg.isRequired(key) ? '$label *' : label;
    const divider = Divider(height: 1, color: AppColors.divider);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('إضافة سريعة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final t in allowedTypes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _TypeButton(
                        label: t.label,
                        selected: t == _type,
                        onTap: () => setState(() {
                          _type = t;
                          _custom.clear();
                        }),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              minLines: _type == QuickAddType.note ? 4 : 2,
              maxLines: _type == QuickAddType.note ? 8 : 3,
              decoration: InputDecoration(
                labelText: _type == QuickAddType.note ? 'الملاحظة' : 'العنوان',
                hintText: _hint,
              ),
            ),
            if (_type != QuickAddType.note) ...[
              const SizedBox(height: 16),
              CardBox(
                radius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    if (_type == QuickAddType.followup || cfg.isVisible(dueKey))
                    _FieldRow(
                      label: star(dueKey, cfg.labelOf(dueKey, _type == QuickAddType.request ? 'الموعد النهائي' : 'الموعد')),
                      value: _when == null
                          ? (_needsDate ? 'مطلوب' : 'بدون موعد')
                          : '${relativeDay(_when!)}${_when!.hour != 0 || _when!.minute != 0 ? ' · ${formatTime(_when!)}' : ''}',
                      onTap: _pickDateTime,
                    ),
                    if (_type != QuickAddType.followup && (_type == QuickAddType.request || cfg.isVisible('client_id'))) ...[
                      divider,
                      _DropdownRow<String>(
                        label: _type == QuickAddType.request ? 'العميل (مطلوب)' : star('client_id', cfg.labelOf('client_id', 'مرتبط بعميل')),
                        value: _clientId,
                        items: {for (final c in clients) c.id: c.name},
                        onChanged: (v) => setState(() => _clientId = v),
                      ),
                    ],
                    if (_type == QuickAddType.request && cfg.isVisible('service_type') && cfg.optionsOf('service_type').isNotEmpty) ...[
                      divider,
                      _DropdownRow<String>(
                        label: star('service_type', cfg.labelOf('service_type', 'نوع الخدمة')),
                        value: _serviceType,
                        items: {for (final o in cfg.optionsOf('service_type')) o: o},
                        onChanged: (v) => setState(() => _serviceType = v),
                      ),
                    ],
                    if (_type == QuickAddType.request && cfg.isVisible('estimated_value')) ...[
                      divider,
                      _FieldRow(
                        label: star('estimated_value', cfg.labelOf('estimated_value', 'القيمة التقديرية')),
                        value: _value == null ? 'أدخل' : money(_value!),
                        onTap: () async {
                          final v = await promptNumber(context, cfg.labelOf('estimated_value', 'القيمة التقديرية'));
                          if (v != null) setState(() => _value = v);
                        },
                      ),
                    ],
                    if ((_type == QuickAddType.task || _type == QuickAddType.request) && cfg.isVisible('priority')) ...[
                      divider,
                      _DropdownRow<Priority>(
                        label: cfg.labelOf('priority', 'الأولوية'),
                        value: _priority,
                        items: {for (final p in Priority.values) p: p.label},
                        onChanged: (v) => setState(() => _priority = v ?? Priority.medium),
                        allowEmpty: false,
                      ),
                    ],
                    if (_type == QuickAddType.task && canAssign && team.length > 1 && cfg.isVisible('assignee_id')) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<String>(
                        label: 'المسؤول',
                        value: _assigneeId,
                        emptyLabel: 'أنا',
                        items: {for (final p in team) p.id: p.name},
                        onChanged: (v) => setState(() => _assigneeId = v),
                      ),
                    ],
                    if (_type == QuickAddType.meeting && cfg.isVisible('location')) ...[
                      divider,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: TextField(
                          controller: _location,
                          decoration: InputDecoration(
                            hintText: star('location', cfg.labelOf('location', 'المكان')),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                    if (_type == QuickAddType.meeting) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<int>(
                        label: 'المدة',
                        value: _duration,
                        items: const {15: '١٥ دقيقة', 30: '٣٠ دقيقة', 45: '٤٥ دقيقة', 60: 'ساعة', 90: 'ساعة ونصف', 120: 'ساعتان'},
                        onChanged: (v) => setState(() => _duration = v ?? 30),
                        allowEmpty: false,
                      ),
                      const Divider(height: 1, color: AppColors.divider),
                      if (cfg.isVisible('type'))
                      _DropdownRow<MeetingType>(
                        label: cfg.labelOf('type', 'النوع'),
                        value: _meetingType,
                        items: {for (final t in MeetingType.values) t: t.label},
                        onChanged: (v) => setState(() => _meetingType = v ?? MeetingType.inPerson),
                        allowEmpty: false,
                      ),
                    ],
                    if (_type == QuickAddType.followup) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<FollowupDirection>(
                        label: 'النوع',
                        value: _direction,
                        items: {for (final d in FollowupDirection.values) d: d.label},
                        onChanged: (v) => setState(() => _direction = v ?? FollowupDirection.promised),
                        allowEmpty: false,
                      ),
                      const Divider(height: 1, color: AppColors.divider),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: TextField(
                          controller: _counterpart,
                          decoration: const InputDecoration(
                            hintText: 'الطرف الآخر (اختياري)',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                    for (final row in customFieldRows(
                      context: context,
                      fields: cfg.customVisible,
                      values: _custom,
                      onChanged: (k, v) => setState(() => _custom[k] = v),
                    )) ...[divider, row],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.ink : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : AppColors.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(value, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.allowEmpty = true,
    this.emptyLabel = 'بدون',
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          DropdownButtonHideUnderline(
            child: DropdownButton<T?>(
              value: value,
              hint: Text(emptyLabel, style: const TextStyle(color: AppColors.muted)),
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
              items: [
                if (allowEmpty) DropdownMenuItem<T?>(value: null, child: Text(emptyLabel)),
                for (final e in items.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
