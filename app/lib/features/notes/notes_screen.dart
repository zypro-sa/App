import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ١٢ · الملاحظات (خاصة بصاحبها)
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

enum _Filter { all, idea, call, pinned }

class _NotesScreenState extends ConsumerState<NotesScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  Future<void> _newNote() async {
    var type = NoteType.general;
    final c = TextEditingController();
    final saved = await showFormSheet<bool>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) => SheetBody(
          title: 'ملاحظة جديدة',
          onSubmit: () => Navigator.pop(ctx, true),
          children: [
            SegmentedButton<NoteType>(
              showSelectedIcon: false,
              segments: [for (final t in NoteType.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {type},
              onSelectionChanged: (s) => setSheet(() => type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(hintText: 'اكتب فكرتك أو ملاحظة المكالمة'),
            ),
          ],
        ),
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (saved != true || text.isEmpty || !mounted) return;
    if (await runAction(context, () => ref.read(sectionRepoProvider).createNote(text, type), success: 'حُفظت الملاحظة')) {
      refreshSections(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    return Scaffold(
      appBar: sectionAppBar('الملاحظات', subtitle: 'خاصة بك · لا يراها غيرك'),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-note',
        tooltip: 'ملاحظة جديدة',
        onPressed: _newNote,
        child: const Icon(Icons.edit_note, size: 28),
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSections(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث في ملاحظاتك'),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(const {
                      _Filter.all: 'الكل',
                      _Filter.idea: 'أفكار',
                      _Filter.call: 'مكالمات',
                      _Filter.pinned: 'مثبتة',
                    }[f]!),
                    selected: _filter == f,
                    showCheckmark: false,
                    selectedColor: AppColors.ink,
                    labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.ink),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AsyncBody<List<NoteItem>>(
              value: notes,
              onRetry: () => ref.invalidate(notesProvider),
              builder: (all) {
                final list = all.where((n) {
                  if (_query.isNotEmpty && !n.content.contains(_query)) return false;
                  return switch (_filter) {
                    _Filter.all => true,
                    _Filter.idea => n.type == NoteType.idea,
                    _Filter.call => n.type == NoteType.call,
                    _Filter.pinned => n.pinned,
                  };
                }).toList();
                if (list.isEmpty) return const EmptyState('لا توجد ملاحظات', icon: Icons.sticky_note_2_outlined);
                return Column(children: [for (final n in list) ...[_NoteCard(n), const SizedBox(height: 10)]]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard(this.n);
  final NoteItem n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sectionRepoProvider);
    final typeColor = switch (n.type) {
      NoteType.idea => AppColors.done,
      NoteType.call => AppColors.primary,
      NoteType.general => AppColors.subtle,
    };
    return CardBox(
      color: n.pinned ? AppColors.waitingSoft : AppColors.surface,
      borderColor: n.pinned ? const Color(0xFFF2DFA6) : AppColors.line,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (n.pinned) const Icon(Icons.push_pin, size: 14, color: AppColors.waiting),
              if (n.pinned) const SizedBox(width: 4),
              Text(
                '${n.pinned ? 'مثبتة · ' : ''}${n.type.label}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: n.pinned ? AppColors.waiting : typeColor),
              ),
              const Spacer(),
              Text(relativeDay(n.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) async {
                  Future<void> Function() action;
                  String msg;
                  switch (v) {
                    case 'pin':
                      action = () => repo.setNotePinned(n.id, !n.pinned);
                      msg = n.pinned ? 'أُلغي التثبيت' : 'ثُبّتت الملاحظة';
                    case 'task':
                      action = () => repo.noteToTask(n);
                      msg = 'تحوّلت إلى مهمة';
                    default:
                      action = () => repo.softDelete('notes', [n.id]);
                      msg = 'نُقلت إلى السلة';
                  }
                  if (await runAction(context, action, success: msg)) refreshSections(ref);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'pin', child: Text(n.pinned ? 'إلغاء التثبيت' : 'تثبيت')),
                  if (n.convertedTaskId == null) const PopupMenuItem(value: 'task', child: Text('تحويل إلى مهمة')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: AppColors.urgent))),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Text(n.content, style: const TextStyle(fontSize: 14, height: 1.7)),
          ),
          if (n.convertedTaskId != null) ...[
            const SizedBox(height: 6),
            Pill.done('تحوّلت إلى مهمة'),
          ],
        ],
      ),
    );
  }
}
