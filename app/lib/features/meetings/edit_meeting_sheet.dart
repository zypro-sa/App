import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// تعديل الاجتماع: العنوان والموعد والمدة والنوع والعميل والمكان والمشاركون.
Future<void> editMeeting(BuildContext context, WidgetRef ref, Meeting m) async {
  final saved = await showFormSheet<bool>(context, EditMeetingSheet(meeting: m));
  if (saved == true && context.mounted) {
    refreshAll(ref);
    showSnack(context, tr('حُفظت تعديلات الاجتماع'));
  }
}

class EditMeetingSheet extends ConsumerStatefulWidget {
  const EditMeetingSheet({super.key, required this.meeting});
  final Meeting meeting;

  @override
  ConsumerState<EditMeetingSheet> createState() => _EditMeetingSheetState();
}

class _EditMeetingSheetState extends ConsumerState<EditMeetingSheet> {
  late final _title = TextEditingController(text: widget.meeting.title);
  late final _location = TextEditingController(text: widget.meeting.location ?? '');
  late DateTime _start = widget.meeting.startAt;
  late int _duration = widget.meeting.durationMinutes <= 0 ? 30 : widget.meeting.durationMinutes;
  late MeetingType _type = widget.meeting.type;
  late String? _clientId = widget.meeting.clientId;
  Set<String>? _attendees;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(repositoryProvider).meetingAttendeeIds(widget.meeting.id).then((ids) {
      if (mounted) setState(() => _attendees = ids.toSet());
    }).catchError((_) {
      if (mounted) setState(() => _attendees = <String>{});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, tr('اكتب عنوان الاجتماع'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).updateMeeting(
            widget.meeting,
            title: title,
            startAt: _start,
            durationMinutes: _duration,
            type: _type,
            clientId: _clientId,
            location: _location.text,
            attendeeIds: (_attendees ?? const <String>{}).toList(),
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meeting;
    final team = ref.watch(teamProvider).valueOrNull ?? const <Profile>[];
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final moved = !_start.isAtSameMomentAs(m.startAt);
    final durations = {15: tr('١٥ دقيقة'), 30: tr('٣٠ دقيقة'), 45: tr('٤٥ دقيقة'), 60: tr('ساعة'), 90: tr('ساعة ونصف'), 120: tr('ساعتان')};
    if (!durations.containsKey(_duration)) durations[_duration] = tr('{0} دقيقة', [_duration]);

    return SheetBody(
      title: tr('تعديل الاجتماع'),
      busy: _busy || _attendees == null,
      onSubmit: _save,
      children: [
        TextField(controller: _title, decoration: InputDecoration(labelText: tr('عنوان الاجتماع'))),
        const SizedBox(height: 12),
        FormCard(children: [
          FormRow(label: tr('التاريخ'), value: formatDay(_start), onTap: _pickDate),
          FormRow(label: tr('الوقت'), value: formatTime(_start), onTap: _pickTime),
          FormDropdown<int>(
            label: tr('المدة'),
            value: _duration,
            items: durations,
            allowEmpty: false,
            onChanged: (v) => setState(() => _duration = v ?? 30),
          ),
          FormDropdown<MeetingType>(
            label: tr('النوع'),
            value: _type,
            items: {for (final t in MeetingType.values) t: t.label},
            allowEmpty: false,
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          FormDropdown<String>(
            label: tr('العميل'),
            value: clients.any((c) => c.id == _clientId) ? _clientId : null,
            emptyLabel: tr('بدون عميل'),
            items: {for (final c in clients) c.id: c.name},
            onChanged: (v) => setState(() => _clientId = v),
          ),
        ]),
        if (moved && (m.status == MeetingStatus.postponed || m.status == MeetingStatus.cancelled))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('سيعود الاجتماع إلى «مجدول» بالموعد الجديد'),
                style: TextStyle(fontSize: 12, color: AppColors.accentText, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          decoration: InputDecoration(
            labelText: _type == MeetingType.online ? tr('رابط الاجتماع أو المكان') : tr('المكان'),
            prefixIcon: Icon(_type == MeetingType.online ? Icons.link : Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text(tr('المشاركون من الفريق'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_attendees == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (team.isEmpty)
          Text(tr('لا يوجد أعضاء'), style: TextStyle(color: AppColors.muted))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in team)
                FilterChip(
                  avatar: Avatar(p.name.isEmpty ? '؟' : p.name.characters.first, size: 22, imageUrl: p.avatarUrl),
                  label: Text(p.name),
                  selected: _attendees!.contains(p.id),
                  onSelected: (on) => setState(() => on ? _attendees!.add(p.id) : _attendees!.remove(p.id)),
                ),
            ],
          ),
      ],
    );
  }
}
