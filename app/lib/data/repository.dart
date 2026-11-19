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
    final row = await _db.from('profiles').select().eq('id', _uid).maybeSingle();
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
          .select('id')
          .isFilter('deleted_at', null)
          .eq('assignee_id', _uid)
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
          .select(TaskItem.select)
          .isFilter('deleted_at', null)
          .eq('assignee_id', _uid)
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
    var q = _db.from('tasks').select(TaskItem.select).isFilter('deleted_at', null);
    q = assignedByMe
        ? q.eq('assigned_by_id', _uid).neq('assignee_id', _uid)
        : q.eq('assignee_id', _uid);
    final weekAgo = _startOfToday().subtract(const Duration(days: 7));
    final rows = await q
        .or('status.neq.done,completed_at.gte.${_iso(weekAgo)}')
        .order('due_at', ascending: true, nullsFirst: false);
    return rows.map(TaskItem.fromMap).toList();
  }

  Future<void> setTaskDone(String id, bool done) => _db
      .from('tasks')
      .update({'status': done ? 'done' : 'todo'}).eq('id', id);

  Future<void> createTask({
    required String title,
    required Priority priority,
    DateTime? dueAt,
    String? assigneeId,
    String? clientId,
    Map<String, dynamic> custom = const {},
  }) =>
      _db.from('tasks').insert({
        'title': title,
        'priority': priority.db,
        'assignee_id': assigneeId ?? _uid,
        'assigned_by_id': _uid,
        if (dueAt != null) 'due_at': _iso(dueAt),
        if (clientId != null) 'client_id': clientId,
        if (custom.isNotEmpty) 'custom': custom,
      });

  // ---------------- الاجتماعات ----------------
  Future<List<Meeting>> meetingsOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db
        .from('meetings')
        .select(Meeting.select)
        .isFilter('deleted_at', null)
        .neq('status', 'cancelled')
        .gte('start_at', _iso(start))
        .lt('start_at', _iso(end))
        .order('start_at', ascending: true);
    return rows.map(Meeting.fromMap).toList();
  }

  Future<void> saveMinutes(String meetingId, String minutes) => _db
      .from('meetings')
      .update({'minutes': minutes, 'status': 'done'}).eq('id', meetingId);

  Future<void> createMeeting({
    required String title,
    required DateTime startAt,
    required int durationMinutes,
    required MeetingType type,
    String? clientId,
    String? location,
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
    await _db.from('meeting_attendees').insert({
      'meeting_id': row['id'],
      'user_id': _uid,
      'attendance': 'confirmed',
    });
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
    final results = await Future.wait<dynamic>([
      _db.from('clients').select().eq('id', id).single(),
      _db.from('contacts').select().eq('client_id', id).isFilter('deleted_at', null),
      _db.from('client_summary').select().eq('id', id).maybeSingle(),
      _db
          .from('activity_log')
          .select('action, created_at')
          .eq('client_id', id)
          .order('created_at', ascending: false)
          .limit(10),
    ]);
    final summary = results[2] as Map<String, dynamic>?;
    return ClientDetail(
      client: Client.fromMap(results[0] as Map<String, dynamic>),
      contacts: (results[1] as List).map((m) => Contact.fromMap(m)).toList(),
      openRequests: (summary?['open_requests'] ?? 0) as int,
      contractsValue: (summary?['contracts_value'] ?? 0) as num,
      amountDue: (summary?['amount_due'] ?? 0) as num,
      activity: (results[3] as List)
          .map((m) => ActivityEntry(
                m['action'] as String,
                DateTime.parse(m['created_at'] as String).toLocal(),
              ))
          .toList(),
    );
  }

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

final profileProvider = FutureProvider<Profile?>(
  (ref) => ref.watch(repositoryProvider).currentProfile(),
);

final homeSummaryProvider = FutureProvider<HomeSummary>(
  (ref) => ref.watch(repositoryProvider).homeSummary(),
);

final requestsProvider = FutureProvider.family<List<RequestItem>, RequestStatus?>(
  (ref, status) => ref.watch(repositoryProvider).requests(status),
);

final requestCountsProvider = FutureProvider<Map<RequestStatus, int>>(
  (ref) => ref.watch(repositoryProvider).requestCounts(),
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
  ref.invalidate(meetingsProvider);
  ref.invalidate(followupsProvider);
  ref.invalidate(clientsProvider);
  ref.invalidate(clientDetailProvider);
}
