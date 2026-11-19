import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../data/section_models.dart';
import 'common.dart';

final _money = NumberFormat.decimalPattern('ar');
String money(num v) => '${_money.format(v)} ر.س';
String moneyShort(num v) => _money.format(v);

Future<DateTime?> pickDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 5),
  );
}

Future<String?> promptText(
  BuildContext context,
  String title, {
  String? initial,
  String? label,
  bool multiline = false,
  String confirmLabel = 'حفظ',
}) async {
  final c = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirmLabel)),
      ],
    ),
  );
  c.dispose();
  return (result == null || result.isEmpty) ? null : result;
}

Future<num?> promptNumber(BuildContext context, String title, {String? label, num? initial}) async {
  final text = await promptText(context, title, label: label, initial: initial?.toString());
  if (text == null) return null;
  return num.tryParse(_toLatinDigits(text).replaceAll(',', ''));
}

String _toLatinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : (ch == '٫' ? '.' : ch));
  }
  return b.toString();
}

num? parseNumber(String s) => num.tryParse(_toLatinDigits(s.trim()).replaceAll(',', ''));

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFFC2410C)) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// تشغيل عملية مع رسالة نجاح أو خطأ.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, 'تعذّر التنفيذ: ${_friendly(e)}');
    return false;
  }
}

String _friendly(Object e) {
  final s = e.toString();
  if (s.contains('row-level security') || s.contains('42501')) return 'ليست لديك صلاحية لهذه العملية';
  final m = RegExp(r'message: ([^,]+)').firstMatch(s);
  return m?.group(1) ?? s.replaceFirst('Exception: ', '');
}

/// هيكل موحّد للنوافذ السفلية.
Future<T?> showFormSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => child,
  );
}

class SheetBody extends StatelessWidget {
  const SheetBody({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'حفظ',
    this.busy = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSubmit;
  final String submitLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: busy ? null : onSubmit,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(submitLabel, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف قابل للضغط داخل بطاقة الحقول.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.value, this.onTap, this.muted = false});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: muted ? const Color(0xFF9AA2AE) : AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormDropdown<T> extends StatelessWidget {
  const FormDropdown({
    super.key,
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
    final safeValue = items.containsKey(value) ? value : null;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T?>(
                value: safeValue,
                isDense: true,
                hint: Text(emptyLabel, style: const TextStyle(color: AppColors.muted)),
                style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFamily: 'IBM Plex Sans Arabic'),
                items: [
                  if (allowEmpty) DropdownMenuItem<T?>(value: null, child: Text(emptyLabel)),
                  for (final e in items.entries)
                    DropdownMenuItem<T?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة تجمع صفوف النموذج مع فواصل.
class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, color: AppColors.divider));
      rows.add(children[i]);
    }
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: rows),
    );
  }
}

/// حقول مخصصة يضيفها المالك من لوحة التحكم.
List<Widget> customFieldRows({
  required BuildContext context,
  required List<FieldSetting> fields,
  required Map<String, dynamic> values,
  required void Function(String key, dynamic value) onChanged,
}) {
  return [
    for (final f in fields)
      switch (f.type) {
        FieldType.list => FormDropdown<String>(
            label: f.required ? '${f.label} *' : f.label,
            value: values[f.key] as String?,
            items: {for (final o in f.options) o: o},
            onChanged: (v) => onChanged(f.key, v),
          ),
        FieldType.boolean => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.label, style: const TextStyle(fontSize: 14)),
            value: values[f.key] == true,
            onChanged: (v) => onChanged(f.key, v),
          ),
        FieldType.date => FormRow(
            label: f.required ? '${f.label} *' : f.label,
            value: values[f.key] == null ? 'اختر' : formatShortDate(DateTime.parse(values[f.key] as String)),
            onTap: () async {
              final d = await pickDate(context);
              if (d != null) onChanged(f.key, d.toIso8601String().substring(0, 10));
            },
          ),
        _ => FormRow(
            label: f.required ? '${f.label} *' : f.label,
            value: values[f.key]?.toString() ?? 'أدخل',
            muted: values[f.key] == null,
            onTap: () async {
              if (f.type == FieldType.text) {
                final v = await promptText(context, f.label, initial: values[f.key]?.toString());
                if (v != null) onChanged(f.key, v);
              } else {
                final v = await promptNumber(context, f.label, initial: values[f.key] as num?);
                if (v != null) onChanged(f.key, v);
              }
            },
          ),
      },
  ];
}

/// التحقق من الحقول المخصصة الإلزامية.
String? missingRequired(List<FieldSetting> fields, Map<String, dynamic> values) {
  for (final f in fields) {
    final v = values[f.key];
    if (f.required && f.type != FieldType.boolean && (v == null || (v is String && v.isEmpty))) {
      return 'الحقل «${f.label}» مطلوب';
    }
  }
  return null;
}

/// شارة بلون الحالة كما حُدد في لوحة التحكم.
Pill statusPill(String label, String color) {
  switch (color) {
    case 'info':
      return Pill.info(label);
    case 'waiting':
      return Pill.waiting(label);
    case 'done':
      return Pill.done(label);
    case 'urgent':
      return Pill.urgent(label);
    default:
      return Pill.neutral(label);
  }
}

/// عنوان صفحة فرعية مع زر رجوع (يعمل تلقائيًا من AppBar).
PreferredSizeWidget sectionAppBar(String title, {String? subtitle, List<Widget>? actions}) {
  return AppBar(
    toolbarHeight: subtitle == null ? 56 : 68,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (subtitle != null)
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w400)),
      ],
    ),
    actions: [...?actions, const SizedBox(width: 8)],
  );
}
