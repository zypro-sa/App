import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _uid => _db.auth.currentUser!.id;

const _openStatuses = ['new', 'in_progress', 'waiting_client', 'on_hold'];

DateTime _startOfToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _iso(DateTime d) => d.toUtc().toIso8601String();
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// كل عمليات القراءة والكتابة مع Supabase في مكان واحد.
class Repository {
  // ---------------- المستخدم ----------------
  Future<Profile?> currentProfile() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null; // لم يسجّل الدخول بعد
    final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<List<Profile>> team() async {
    final rows = await _db.from('profiles').select().eq('is_active', true).order('name', ascending: true);
    return rows.map(Profile.fromMap).toList();
  }

  // ---------------- لوحة اليوم ----------------
  Future<HomeSummary> homeSummary() async {
    final today = _startOfToday();
    final tomorrow = today.add(const Duration(days: 1));

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('meetings')
          .select('id')
          .isFilter('deleted_at', null)
          .neq('status', 'cancelled')
          .gte('start_at', _iso(today))
          .lt('start_at', _iso(tomorrow)),
      _db
          .from('tasks')
          .select('id, mine:task_assignees!inner(user_id)')
          .isFilter('deleted_at', null)
          .eq('mine.user_id', _uid)
          .neq('status', 'done')
          .inFilter('priority', ['high', 'urgent']),
      _db
          .from('requests')
          .select('id')
          .isFilter('deleted_at', null)
          .inFilter('status', _openStatuses)
          .lt('due_date', _isoDate(today)),
      _db
          .from('meetings')
          .select(Meeting.select)
          .isFilter('deleted_at', null)
          .eq('status', 'scheduled')
          .gte('end_at', _iso(DateTime.now()))
          .order('start_at', ascending: true)
          .limit(1),
      _db
          .from('tasks')
          .select('${TaskItem.select}, mine:task_assignees!inner(user_id)')
          .isFilter('deleted_at', null)
          .eq('mine.user_id', _uid)
          .lt('due_at', _iso(tomorrow))
          .order('status', ascending: true)
          .order('due_at', ascending: true)
          .limit(4),
      _db
          .from('followups')
          .select()
          .isFilter('deleted_at', null)
          .eq('owner_id', _uid)
          .eq('status', 'open')
          .order('due_at', ascending: true)
          .limit(2),
    ]);

    final next = results[3];
    return HomeSummary(
      meetingsToday: results[0].length,
      urgentTasks: results[1].length,
      overdueRequests: results[2].length,
      nextMeeting: next.isEmpty ? null : Meeting.fromMap(next.first),
      todayTasks: results[4]
          .map(TaskItem.fromMap)
          .where((t) => !t.isDone || (t.dueAt != null && !t.dueAt!.isBefore(today)))
          .take(3)
          .toList(),
      followups: results[5].map(FollowUp.fromMap).toList(),
    );
  }

  // ---------------- الطلبات ----------------
  Future<List<RequestItem>> requests(RequestStatus? status) async {
    var q = _db.from('requests').select(RequestItem.select).isFilter('deleted_at', null);
    q = status == null ? q.inFilter('status', _openStatuses) : q.eq('status', status.db);
    final rows = await q.order('due_date', ascending: true, nullsFirst: false);
    return rows.map(RequestItem.fromMap).toList();
  }

  Future<Map<RequestStatus, int>> requestCounts() async {
    final rows = await _db
        .from('requests')
        .select('status')
        .isFilter('deleted_at', null)
        .inFilter('status', _openStatuses);
    final counts = <RequestStatus, int>{};
    for (final r in rows) {
      final s = RequestStatus.from(r['status'] as String?);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> createRequest({
    required String title,
    required String clientId,
    required Priority priority,
    DateTime? dueDate,
    String? serviceType,
    String? paymentTerms,
    num? estimatedValue,
    String? description,
    Map<String, dynamic> custom = const {},
  }) =>
      _db.from('requests').insert({
        'title': title,
        'client_id': clientId,
        'priority': priority.db,
        'assignee_id': _uid,
        if (dueDate != null) 'due_date': _isoDate(dueDate),
        if (serviceType != null) 'service_type': serviceType,
        if (paymentTerms != null) 'payment_terms': paymentTerms,
        if (estimatedValue != null) 'estimated_value': estimatedValue,
        if (description != null && description.isNotEmpty) 'description': description,
        if (custom.isNotEmpty) 'custom': custom,
      });

  // ---------------- المهام ----------------
  /// [assignedByMe]: false = مهامي، true = ما أسندته للفريق.
  Future<List<TaskItem>> tasks({required bool assignedByMe}) async {
    var q = assignedByMe
        ? _db.from('tasks').select(TaskItem.select).isFilter('deleted_at', null).eq('assigned_by_id', _uid).neq('assignee_id', _uid)
        // مهامي: كل مهمة أنا ضمن المسندة إليهم (وحدي أو مع غيري)
        : _db.from('tasks').select('${TaskItem.select}, mine:task_assignees!inner(user_id)').isFilter('deleted_at', null).eq('mine.user_id', _uid);
    final weekAgo = _startOfToday().subtract(const Duration(days: 7));
    final rows = await q
        .or('status.neq.done,completed_at.gte.${_iso(weekAgo)}')
        .order('due_at', ascending: true, nullsFirst: false);
    return rows.map(TaskItem.fromMap).toList();
  }

  /// مهامي المنجزة (الأحدث إنجازًا أولًا)
  Future<List<TaskItem>> doneTasks({bool assignedByMe = false, int limit = 300}) async {
    final base = assignedByMe
        ? _db.from('tasks').select(TaskItem.select).isFilter('deleted_at', null).eq('assigned_by_id', _uid).neq('assignee_id', _uid)
        : _db.from('tasks').select('${TaskItem.select}, mine:task_assignees!inner(user_id)').isFilter('deleted_at', null).eq('mine.user_id', _uid);
    final rows = await base
        .eq('status', 'done')
        .order('completed_at', ascending: false, nullsFirst: false)
        .limit(limit);
    return rows.map(TaskItem.fromMap).toList();
  }

  Future<void> setTaskDone(String id, bool done) => _db
      .from('tasks')
      .update({'status': done ? 'done' : 'todo'}).eq('id', id);

  /// [assigneeIds]: المسندة إليهم (فارغة = أنا). الأول هو المسؤول الأول.
  Future<void> createTask({
    required String title,
    required Priority priority,
    DateTime? dueAt,
    List<String> assigneeIds = const [],
    String? clientId,
    Map<String, dynamic> custom = const {},
  }) async {
    final people = assigneeIds.isEmpty ? [_uid] : assigneeIds;
    final t = await _db
        .from('tasks')
        .insert({
          'title': title,
          'priority': priority.db,
          'assignee_id': people.first,
          'assigned_by_id': _uid,
          if (dueAt != null) 'due_at': _iso(dueAt),
          if (clientId != null) 'client_id': clientId,
          if (custom.isNotEmpty) 'custom': custom,
        })
        .select('id')
        .single();
    await _addCoAssignees(t['id'] as String, people);
  }

  /// تغيير المسندة إليهم مهمة موجودة
  Future<void> setTaskAssignees(TaskItem t, List<String> ids) async {
    if (ids.isEmpty) return;
    if (!ids.contains(t.assigneeId)) {
      await _db.from('tasks').update({'assignee_id': ids.first}).eq('id', t.id);
    }
    final current = [for (final p in t.people) p.$1];
    final remove = current.where((u) => !ids.contains(u) && u != (ids.contains(t.assigneeId) ? t.assigneeId : ids.first)).toList();
    if (remove.isNotEmpty) {
      await _db.from('task_assignees').delete().eq('task_id', t.id).inFilter('user_id', remove);
    }
    final add = ids.where((u) => !current.contains(u)).toList();
    if (add.isNotEmpty) {
      await _db.from('task_assignees').upsert(
        [for (final u in add) {'task_id': t.id, 'user_id': u}],
        onConflict: 'task_id,user_id',
        ignoreDuplicates: true,
      );
    }
  }

  /// إضافة بقية المشاركين (الأول يُضاف تلقائيًا من قاعدة البيانات)
  Future<void> _addCoAssignees(String taskId, List<String> people) async {
    final rest = people.skip(1).toSet().where((u) => u != people.first).toList();
    if (rest.isEmpty) return;
    await _db.from('task_assignees').upsert(
      [for (final u in rest) {'task_id': taskId, 'user_id': u}],
      onConflict: 'task_id,user_id',
      ignoreDuplicates: true,
    );
  }

  // ---------------- الاجتماعات ----------------
  Future<List<Meeting>> meetingsOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db
        .from('meetings')
        .select(Meeting.select)
        .isFilter('deleted_at', null)
        .gte('start_at', _iso(start))
        .lt('start_at', _iso(end))
        .order('start_at', ascending: true);
    return rows.map(Meeting.fromMap).toList();
  }

  /// الاجتماعات السابقة (الأحدث أولًا) مع بحث وتصفية
  Future<List<Meeting>> pastMeetings({
    String? query,
    MeetingStatus? status,
    bool withoutMinutes = false,
    int offset = 0,
    int limit = 30,
  }) async {
    var q = _db
        .from('meetings')
        .select(Meeting.select)
        .isFilter('deleted_at', null)
        .lt('start_at', _iso(DateTime.now()));
    if (status != null) q = q.eq('status', status.db);
    if (withoutMinutes) q = q.or('minutes.is.null,minutes.eq.');
    final text = (query ?? '').replaceAll(RegExp(r'[,()%*\\]'), ' ').trim();
    if (text.isNotEmpty) q = q.or('title.ilike.*$text*,location.ilike.*$text*,minutes.ilike.*$text*');
    final rows = await q.order('start_at', ascending: false).range(offset, offset + limit - 1);
    return rows.map(Meeting.fromMap).toList();
  }

  /// مهمة من محضر اجتماع: تُسجَّل كقرار في الاجتماع وتُربط بالمهمة.
  Future<void> createTaskFromMinutes({
    required String meetingId,
    required String title,
    List<String> assigneeIds = const [],
    DateTime? dueAt,
    String? clientId,
  }) async {
    final people = assigneeIds.isEmpty ? [_uid] : assigneeIds;
    final assigneeId = people.first;
    String? decisionId;
    try {
      final d = await _db
          .from('decisions')
          .insert({
            'meeting_id': meetingId,
            'text': title,
            'owner_id': assigneeId,
            if (dueAt != null) 'due_date': dueAt.toIso8601String().substring(0, 10),
          })
          .select('id')
          .single();
      decisionId = d['id'] as String;
    } catch (_) {
      // بدون صلاحية الاجتماعات: نُنشئ المهمة فقط
    }
    final t = await _db
        .from('tasks')
        .insert({
          'title': title,
          'priority': 'medium',
          'assignee_id': assigneeId,
          'assigned_by_id': _uid,
          if (dueAt != null) 'due_at': _iso(dueAt),
          if (clientId != null) 'client_id': clientId,
          if (decisionId != null) 'source_decision_id': decisionId,
        })
        .select('id')
        .single();
    await _addCoAssignees(t['id'] as String, people);
    if (decisionId != null) {
      await _db.from('decisions').update({'task_id': t['id']}).eq('id', decisionId);
    }
  }

  Future<void> setMeetingStatus(String id, MeetingStatus status) =>
      _db.from('meetings').update({'status': status.db}).eq('id', id);

  /// تأجيل لموعد جديد: يبقى «مجدولًا» حتى تصل تذكيراته في الموعد الجديد
  Future<void> rescheduleMeeting(String id, DateTime start, int durationMinutes) => _db.from('meetings').update({
        'start_at': _iso(start),
        'end_at': _iso(start.add(Duration(minutes: durationMinutes))),
        'status': 'scheduled',
      }).eq('id', id);

  /// أعضاء الفريق المشاركون في الاجتماع
  Future<List<String>> meetingAttendeeIds(String meetingId) async {
    final rows = await _db
        .from('meeting_attendees')
        .select('user_id')
        .eq('meeting_id', meetingId)
        .isFilter('deleted_at', null)
        .not('user_id', 'is', null);
    return [for (final r in rows) r['user_id'] as String];
  }

  /// تعديل الاجتماع: البيانات والمكان والمشاركون.
  /// إذا تغيّر موعد اجتماع مؤجل أو ملغى يعود «مجدولًا».
  Future<void> updateMeeting(
    Meeting m, {
    required String title,
    required DateTime startAt,
    required int durationMinutes,
    required MeetingType type,
    String? clientId,
    String? location,
    required List<String> attendeeIds,
  }) async {
    final moved = !startAt.isAtSameMomentAs(m.startAt);
    await _db.from('meetings').update({
      'title': title,
      'start_at': _iso(startAt),
      'end_at': _iso(startAt.add(Duration(minutes: durationMinutes))),
      'type': type.db,
      'client_id': clientId,
      'location': (location == null || location.trim().isEmpty) ? null : location.trim(),
      if (moved && (m.status == MeetingStatus.postponed || m.status == MeetingStatus.cancelled)) 'status': 'scheduled',
    }).eq('id', m.id);

    final current = await meetingAttendeeIds(m.id);
    final remove = current.where((u) => !attendeeIds.contains(u)).toList();
    final add = attendeeIds.where((u) => !current.contains(u)).toSet().toList();
    if (remove.isNotEmpty) {
      await _db.from('meeting_attendees').delete().eq('meeting_id', m.id).inFilter('user_id', remove);
    }
    if (add.isNotEmpty) {
      await _db.from('meeting_attendees').insert([
        for (final u in add) {'meeting_id': m.id, 'user_id': u, 'attendance': u == _uid ? 'confirmed' : 'invited'},
      ]);
    }
  }

  /// حفظ المحضر؛ الاجتماع المجدول يصبح «منعقدًا»
  Future<void> saveMinutes(String meetingId, String minutes) async {
    await _db.from('meetings').update({'minutes': minutes}).eq('id', meetingId);
    await _db.from('meetings').update({'status': 'done'}).eq('id', meetingId).eq('status', 'scheduled');
  }

  Future<void> createMeeting({
    required String title,
    required DateTime startAt,
    required int durationMinutes,
    required MeetingType type,
    String? clientId,
    String? location,
    List<String> attendeeIds = const [],
    Map<String, dynamic> custom = const {},
  }) async {
    final row = await _db
        .from('meetings')
        .insert({
          'title': title,
          'start_at': _iso(startAt),
          'end_at': _iso(startAt.add(Duration(minutes: durationMinutes))),
          'type': type.db,
          if (clientId != null) 'client_id': clientId,
          if (location != null && location.isNotEmpty) 'location': location,
          if (custom.isNotEmpty) 'custom': custom,
        })
        .select('id')
        .single();
    await _db.from('meeting_attendees').insert([
      {'meeting_id': row['id'], 'user_id': _uid, 'attendance': 'confirmed'},
      for (final u in attendeeIds.toSet())
        if (u != _uid) {'meeting_id': row['id'], 'user_id': u, 'attendance': 'invited'},
    ]);
  }

  // ---------------- المتابعات ----------------
  Future<List<FollowUp>> followups(FollowupDirection direction) async {
    final rows = await _db
        .from('followups')
        .select()
        .isFilter('deleted_at', null)
        .eq('owner_id', _uid)
        .eq('direction', direction.db)
        .eq('status', 'open')
        .order('due_at', ascending: true);
    return rows.map(FollowUp.fromMap).toList();
  }

  Future<void> completeFollowup(String id) =>
      _db.from('followups').update({'status': 'done'}).eq('id', id);

  Future<void> snoozeFollowup(String id, Duration by) => _db.from('followups').update({
        'due_at': _iso(DateTime.now().add(by)),
      }).eq('id', id);

  Future<void> followupToTask(FollowUp f) async {
    await createTask(title: f.title, priority: Priority.medium, dueAt: f.dueAt);
    await completeFollowup(f.id);
  }

  Future<void> createFollowup({
    required String title,
    required FollowupDirection direction,
    required DateTime dueAt,
    String? counterpart,
  }) =>
      _db.from('followups').insert({
        'title': title,
        'direction': direction.db,
        'owner_id': _uid,
        'due_at': _iso(dueAt),
        if (counterpart != null && counterpart.isNotEmpty) 'counterpart': counterpart,
      });

  // ---------------- الملاحظات ----------------
  Future<void> createNote(String content) =>
      _db.from('notes').insert({'content': content});

  // ---------------- العملاء ----------------
  Future<List<Client>> clients() async {
    final rows = await _db.from('clients').select().isFilter('deleted_at', null).order('name', ascending: true);
    return rows.map(Client.fromMap).toList();
  }

  Future<ClientDetail> clientDetail(String id) async {
    final client = await _db.from('clients').select().eq('id', id).single();

    List<dynamic> contacts = const [];
    Map<String, dynamic>? summary;
    List<dynamic> activity = const [];
    String? summaryError;
    await Future.wait<void>([
      () async {
        contacts = await _db
            .from('contacts')
            .select()
            .eq('client_id', id)
            .isFilter('deleted_at', null)
            .order('is_primary', ascending: false)
            .order('created_at', ascending: true);
      }(),
      () async {
        try {
          summary = await _db.from('client_summary').select().eq('id', id).maybeSingle();
        } catch (e) {
          summaryError = '$e';
        }
      }(),
      () async {
        try {
          activity = await _db
              .from('activity_log')
              .select('action, created_at')
              .eq('client_id', id)
              .order('created_at', ascending: false)
              .limit(10);
        } catch (_) {}
      }(),
    ]);
    num n(Object? v) => v is num ? v : num.tryParse('${v ?? 0}') ?? 0;
    return ClientDetail(
      client: Client.fromMap(client),
      contacts: contacts.map((m) => Contact.fromMap(Map<String, dynamic>.from(m as Map))).toList(),
      openRequests: n(summary?['open_requests']).toInt(),
      contractsValue: n(summary?['contracts_value']),
      amountDue: n(summary?['amount_due']),
      summaryError: summaryError,
      activity: activity
          .map((m) => ActivityEntry(
                m['action'] as String,
                DateTime.parse(m['created_at'] as String).toLocal(),
              ))
          .toList(),
    );
  }

  Future<void> updateClient(String id, Map<String, dynamic> changes) =>
      _db.from('clients').update(changes).eq('id', id);

  Future<void> saveContact({
    String? id,
    required String clientId,
    required String name,
    String? position,
    String? phone,
    String? email,
    bool isPrimary = false,
  }) async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final row = {
      'client_id': clientId,
      'name': name.trim(),
      'position': clean(position),
      'phone': clean(phone),
      'email': clean(email),
      'is_primary': isPrimary,
    };
    if (isPrimary) {
      await _db.from('contacts').update({'is_primary': false}).eq('client_id', clientId).neq('id', id ?? '00000000-0000-0000-0000-000000000000');
    }
    if (id == null || id.isEmpty) {
      await _db.from('contacts').insert(row);
    } else {
      await _db.from('contacts').update(row).eq('id', id);
    }
  }

  Future<void> deleteContact(String id) =>
      _db.from('contacts').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  Future<String> createClient(
    String name, {
    String? sector,
    String? city,
    String? crNumber,
    String? vatNumber,
    Map<String, dynamic> custom = const {},
  }) async {
    final row = await _db
        .from('clients')
        .insert({
          'name': name,
          'status': 'active',
          if (sector != null) 'sector': sector,
          if (city != null && city.isNotEmpty) 'city': city,
          if (crNumber != null && crNumber.isNotEmpty) 'cr_number': crNumber,
          if (vatNumber != null && vatNumber.isNotEmpty) 'vat_number': vatNumber,
          if (custom.isNotEmpty) 'custom': custom,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }
}

// ---------------- مزوّدات Riverpod ----------------
final repositoryProvider = Provider((_) => Repository());

/// المستخدم الحالي — يتغير عند الدخول والخروج فقط (لا عند تجديد الجلسة)
final authUserIdProvider = StreamProvider<String?>(
  (ref) => _db.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct(),
);

final profileProvider = FutureProvider<Profile?>((ref) {
  // يُعاد تحميل الملف عند تغيّر المستخدم، حتى لا يبقى خطأ محفوظ من شاشة الدخول
  ref.watch(authUserIdProvider);
  return ref.watch(repositoryProvider).currentProfile();
});

final homeSummaryProvider = FutureProvider<HomeSummary>(
  (ref) => ref.watch(repositoryProvider).homeSummary(),
);

final requestsProvider = FutureProvider.family<List<RequestItem>, RequestStatus?>(
  (ref, status) => ref.watch(repositoryProvider).requests(status),
);

final requestCountsProvider = FutureProvider<Map<RequestStatus, int>>(
  (ref) => ref.watch(repositoryProvider).requestCounts(),
);

final doneTasksProvider = FutureProvider.family<List<TaskItem>, bool>(
  (ref, assignedByMe) => ref.watch(repositoryProvider).doneTasks(assignedByMe: assignedByMe),
);

final tasksProvider = FutureProvider.family<List<TaskItem>, bool>(
  (ref, assignedByMe) => ref.watch(repositoryProvider).tasks(assignedByMe: assignedByMe),
);

final meetingsProvider = FutureProvider.family<List<Meeting>, DateTime>(
  (ref, day) => ref.watch(repositoryProvider).meetingsOn(day),
);

final followupsProvider = FutureProvider.family<List<FollowUp>, FollowupDirection>(
  (ref, d) => ref.watch(repositoryProvider).followups(d),
);

final clientsProvider = FutureProvider<List<Client>>(
  (ref) => ref.watch(repositoryProvider).clients(),
);

final clientDetailProvider = FutureProvider.family<ClientDetail, String>(
  (ref, id) => ref.watch(repositoryProvider).clientDetail(id),
);

final teamProvider = FutureProvider<List<Profile>>(
  (ref) => ref.watch(repositoryProvider).team(),
);

/// تحديث كل الشاشات بعد أي إضافة أو تعديل.
void refreshAll(WidgetRef ref) {
  ref.invalidate(homeSummaryProvider);
  ref.invalidate(requestsProvider);
  ref.invalidate(requestCountsProvider);
  ref.invalidate(tasksProvider);
  ref.invalidate(doneTasksProvider);
  ref.invalidate(meetingsProvider);
  ref.invalidate(followupsProvider);
  ref.invalidate(clientsProvider);
  ref.invalidate(clientDetailProvider);
}

/// مثل refreshAll لكن عبر الحاوية (يعمل حتى بعد اختفاء الويدجت، مثل زر «تراجع»)
void refreshAllIn(ProviderContainer c) {
  c.invalidate(homeSummaryProvider);
  c.invalidate(requestsProvider);
  c.invalidate(requestCountsProvider);
  c.invalidate(tasksProvider);
  c.invalidate(doneTasksProvider);
  c.invalidate(meetingsProvider);
  c.invalidate(followupsProvider);
  c.invalidate(clientsProvider);
  c.invalidate(clientDetailProvider);
}
