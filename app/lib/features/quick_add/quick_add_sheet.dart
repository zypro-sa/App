import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
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
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _counterpart.dispose();
    super.dispose();
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
                : null;
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
          );
        case QuickAddType.request:
          await repo.createRequest(title: title, clientId: _clientId!, priority: _priority, dueDate: _when);
        case QuickAddType.meeting:
          await repo.createMeeting(
            title: title,
            startAt: _when!,
            durationMinutes: _duration,
            type: _meetingType,
            clientId: _clientId,
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
      refreshAll(ref);
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
    final role = ref.watch(profileProvider).valueOrNull?.role;
    final canAssign = role == UserRole.owner || role == UserRole.manager;

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
                for (final t in QuickAddType.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _TypeButton(
                        label: t.label,
                        selected: t == _type,
                        onTap: () => setState(() => _type = t),
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
                    _FieldRow(
                      label: _type == QuickAddType.request ? 'الموعد النهائي' : 'الموعد',
                      value: _when == null
                          ? (_needsDate ? 'مطلوب' : 'بدون موعد')
                          : '${relativeDay(_when!)}${_when!.hour != 0 || _when!.minute != 0 ? ' · ${formatTime(_when!)}' : ''}',
                      onTap: _pickDateTime,
                    ),
                    if (_type != QuickAddType.followup) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<String>(
                        label: _type == QuickAddType.request ? 'العميل (مطلوب)' : 'مرتبط بعميل',
                        value: _clientId,
                        items: {for (final c in clients) c.id: c.name},
                        onChanged: (v) => setState(() => _clientId = v),
                      ),
                    ],
                    if (_type == QuickAddType.task || _type == QuickAddType.request) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<Priority>(
                        label: 'الأولوية',
                        value: _priority,
                        items: {for (final p in Priority.values) p: p.label},
                        onChanged: (v) => setState(() => _priority = v ?? Priority.medium),
                        allowEmpty: false,
                      ),
                    ],
                    if (_type == QuickAddType.task && canAssign && team.length > 1) ...[
                      const Divider(height: 1, color: AppColors.divider),
                      _DropdownRow<String>(
                        label: 'المسؤول',
                        value: _assigneeId,
                        emptyLabel: 'أنا',
                        items: {for (final p in team) p.id: p.name},
                        onChanged: (v) => setState(() => _assigneeId = v),
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
                      _DropdownRow<MeetingType>(
                        label: 'النوع',
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
