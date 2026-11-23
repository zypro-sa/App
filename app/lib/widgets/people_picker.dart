import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

/// اختيار عدة أعضاء من الفريق. يعيد المجموعة المختارة أو null عند الإلغاء.
Future<List<String>?> pickPeople(
  BuildContext context, {
  required List<Profile> team,
  required List<String> selected,
  required String title,
  String? hint,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PeopleSheet(team: team, selected: selected, title: title, hint: hint),
  );
}

/// أسماء المختارين للعرض في صف النموذج
String peopleNames(List<Profile> team, List<String> ids, {required String empty}) {
  if (ids.isEmpty) return empty;
  final names = [for (final id in ids) team.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? '؟'];
  if (names.length <= 2) return names.join(tr('، '));
  return tr('{0} و{1} آخرين', [names.take(2).join(tr('، ')), names.length - 2]);
}

class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.team, required this.selected, required this.title, this.hint});
  final List<Profile> team;
  final List<String> selected;
  final String title;
  final String? hint;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late final List<String> _sel = [...widget.selected];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (widget.hint != null) ...[
              const SizedBox(height: 4),
              Text(widget.hint!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in widget.team)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _sel.contains(p.id),
                      secondary: Avatar(p.name.isEmpty ? '؟' : p.name.characters.first, size: 34, imageUrl: p.avatarUrl),
                      title: Text(p.name),
                      subtitle: _sel.isNotEmpty && _sel.first == p.id && _sel.length > 1
                          ? Text(tr('المسؤول الأول'), style: TextStyle(fontSize: 11, color: AppColors.accentText))
                          : null,
                      onChanged: (on) => setState(() => on == true ? _sel.add(p.id) : _sel.remove(p.id)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(context, _sel),
              child: Text(_sel.isEmpty ? tr('تم') : tr('تم ({0})', [_sel.length])),
            ),
          ],
        ),
      ),
    );
  }
}
