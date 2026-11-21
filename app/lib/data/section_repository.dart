import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';
import 'report_models.dart';
import 'section_models.dart';
import '../core/i18n.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _uid => _db.auth.currentUser!.id;

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _now() => DateTime.now().toUtc().toIso8601String();

/// عمليات المرحلة الثانية.
class SectionRepository {
  // ---------------- المشاريع ----------------
  Future<List<Project>> projects(ProjectStatus status) async {
    final rows = await _db
        .from('projects')
        .select(Project.select)
        .isFilter('deleted_at', null)
        .eq('status', status.db)
        .order('end_date', ascending: true, nullsFirst: false);
    return rows.map(Project.fromMap).toList();
  }

  Future<Map<ProjectStatus, int>> projectCounts() async {
    final rows = await _db.from('projects').select('status').isFilter('deleted_at', null);
    final counts = <ProjectStatus, int>{};
    for (final r in rows) {
      final s = ProjectStatus.from(r['status'] as String?);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Future<Project> project(String id) async {
    final row = await _db.from('projects').select(Project.select).eq('id', id).single();
    return Project.fromMap(row);
  }

  Future<List<Milestone>> milestones(String projectId) async {
    final rows = await _db
        .from('milestones')
        .select()
        .eq('project_id', projectId)
        .isFilter('deleted_at', null)
        .order('due_date', ascending: true, nullsFirst: false);
    return rows.map(Milestone.fromMap).toList();
  }

  Future<List<TaskItem>> projectTasks(String projectId) async {
    final rows = await _db
        .from('tasks')
        .select(TaskItem.select)
        .eq('project_id', projectId)
        .isFilter('deleted_at', null)
        .order('due_at', ascending: true, nullsFirst: false);
    return rows.map(TaskItem.fromMap).toList();
  }

  Future<List<RequestItem>> projectRequests(String projectId) async {
    final rows = await _db
        .from('requests')
        .select(RequestItem.select)
        .eq('project_id', projectId)
        .isFilter('deleted_at', null);
    return rows.map(RequestItem.fromMap).toList();
  }

  Future<String> createProject({
    required String name,
    required String clientId,
    String? managerId,
    DateTime? endDate,
    num? contractValue,
    ProjectStatus status = ProjectStatus.active,
    Map<String, dynamic> custom = const {},
  }) async {
    final row = await _db
        .from('projects')
        .insert({
          'name': name,
          'client_id': clientId,
          'status': status.db,
          'manager_id': managerId ?? _uid,
          'start_date': _isoDate(DateTime.now()),
          if (endDate != null) 'end_date': _isoDate(endDate),
          if (contractValue != null) 'contract_value': contractValue,
          if (custom.isNotEmpty) 'custom': custom,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> setProjectStatus(String id, ProjectStatus s) =>
      _db.from('projects').update({'status': s.db}).eq('id', id);

  Future<void> addMilestone(String projectId, String title, DateTime? due) => _db.from('milestones').insert({
        'project_id': projectId,
        'title': title,
        if (due != null) 'due_date': _isoDate(due),
      });

  Future<void> setMilestoneDone(String id, bool done) =>
      _db.from('milestones').update({'is_done': done}).eq('id', id);

  // ---------------- المالية ----------------
  Future<List<Invoice>> invoices() async {
    final rows = await _db
        .from('invoices')
        .select(Invoice.select)
        .isFilter('deleted_at', null)
        .order('due_date', ascending: true);
    final list = rows.map(Invoice.fromMap).toList();
    // المتأخرة ثم المفتوحة ثم المدفوعة ثم الملغاة
    list.sort((a, b) {
      int rank(Invoice i) => i.isVoid ? 3 : (i.isOverdue ? 0 : (i.isOpen ? 1 : 2));
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.dueDate.compareTo(b.dueDate);
    });
    return list;
  }

  Future<FinanceSummary> financeSummary() async {
    final invs = await invoices();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final pays = await _db
        .from('payments')
        .select('amount')
        .isFilter('deleted_at', null)
        .gte('paid_at', _isoDate(monthStart));
    return FinanceSummary(
      due: invs.where((i) => i.isOpen).fold<num>(0, (a, i) => a + i.remaining),
      overdue: invs.where((i) => i.isOverdue).fold<num>(0, (a, i) => a + i.remaining),
      collectedThisMonth: pays.fold<num>(0, (a, p) => a + num.parse(p['amount'].toString())),
    );
  }

  Future<void> createInvoice({required String clientId, required num total, required DateTime dueDate}) =>
      _db.from('invoices').insert({
        'client_id': clientId,
        'total': total,
        'due_date': _isoDate(dueDate),
      });

  Future<void> updateInvoice(String id, Map<String, dynamic> changes) =>
      _db.from('invoices').update(changes).eq('id', id);

  Future<void> deletePayment(String id) => _db.from('payments').delete().eq('id', id);

  Future<void> addReturn(String invoiceId, num amount, String? reason) => _db.from('invoice_returns').insert({
        'invoice_id': invoiceId,
        'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  Future<void> deleteReturn(String id) => _db.from('invoice_returns').delete().eq('id', id);

  Future<void> updateQuote(String id, Map<String, dynamic> changes) =>
      _db.from('quotes').update(changes).eq('id', id);

  /// يحوّل عرض السعر المقبول إلى فاتورة بإجماليه شامل الضريبة.
  Future<void> quoteToInvoice(Quote q, DateTime dueDate) async {
    await _db.from('invoices').insert({
      'client_id': q.clientId,
      'quote_id': q.id,
      'total': q.total,
      'due_date': _isoDate(dueDate),
      if (q.notes != null) 'notes': q.notes,
    });
    if (q.status != QuoteStatus.accepted) {
      await _db.from('quotes').update({'status': 'accepted'}).eq('id', q.id);
    }
  }

  Future<void> recordPayment(String invoiceId, num amount) =>
      _db.from('payments').insert({'invoice_id': invoiceId, 'amount': amount, 'method': 'bank_transfer'});

  Future<List<Quote>> quotes() async {
    final rows = await _db
        .from('quotes')
        .select(Quote.select)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(Quote.fromMap).toList();
  }

  Future<void> createQuote({required String clientId, required num amount, bool withVat = true}) =>
      _db.from('quotes').insert({
        'client_id': clientId,
        'amount': amount,
        'vat_amount': withVat ? (amount * 0.15) : 0,
      });

  Future<void> setQuoteStatus(String id, QuoteStatus s) => _db.from('quotes').update({
        'status': s.db,
        if (s == QuoteStatus.sent) 'sent_at': _isoDate(DateTime.now()),
      }).eq('id', id);

  // ---------------- الملاحظات ----------------
  Future<List<NoteItem>> notes() async {
    final rows = await _db
        .from('notes')
        .select()
        .isFilter('deleted_at', null)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(NoteItem.fromMap).toList();
  }

  Future<void> createNote(String content, NoteType type) =>
      _db.from('notes').insert({'content': content, 'type': type.db});

  Future<void> setNotePinned(String id, bool pinned) =>
      _db.from('notes').update({'is_pinned': pinned}).eq('id', id);

  Future<void> noteToTask(NoteItem n) async {
    final title = n.content.length > 80 ? '${n.content.substring(0, 80)}…' : n.content;
    final row = await _db
        .from('tasks')
        .insert({'title': title, 'assignee_id': _uid, 'assigned_by_id': _uid})
        .select('id')
        .single();
    await _db.from('notes').update({'converted_task_id': row['id']}).eq('id', n.id);
  }

  // ---------------- الفريق ----------------
  Future<List<TeamMember>> team() async {
    final rows = await _db.rpc('team_members') as List;
    return rows.map((m) => TeamMember.fromMap(Map<String, dynamic>.from(m as Map))).toList();
  }

  Future<void> inviteMember({
    required String email,
    required String name,
    required UserRole role,
    String? jobTitle,
    String? locale,
    bool resend = false,
  }) async {
    final res = await _db.functions.invoke('invite-member', body: {
      'email': email,
      'name': name,
      'role': role.db,
      if (jobTitle != null && jobTitle.isNotEmpty) 'job_title': jobTitle,
      if (kIsWeb) 'redirect_to': '${Uri.base.origin}${Uri.base.path}',
      'resend': resend,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    final userId = data is Map ? data['user_id'] : null;
    if (locale != null && userId is String) await setMemberLocale(userId, locale);
  }

  // ------------------------------------------------------------------
  // دفترة
  // ------------------------------------------------------------------
  Future<DaftraSyncState> daftraState() async {
    final m = await _db.from('daftra_sync').select().eq('id', 1).maybeSingle();
    return DaftraSyncState.fromMap(m);
  }

  /// تشغيل المزامنة. dryRun: تجربة دون أي تعديل. auto: مزامنة صامتة عند فتح التطبيق.
  Future<Map<String, dynamic>> daftraSync({bool dryRun = false, bool auto = false}) async {
    try {
      final res = await _db.functions.invoke('daftra-sync', body: {'dry_run': dryRun, 'auto': auto});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? d['error'] : (d ?? e.reasonPhrase ?? e.status));
    }
  }

  Future<void> setMemberLocale(String id, String locale) =>
      _db.from('profiles').update({'locale': locale}).eq('id', id);

  Future<void> setMemberRole(String id, UserRole role) =>
      _db.from('profiles').update({'role': role.db}).eq('id', id);

  /// يحفظ فقط ما يختلف عن الافتراضي لدور العضو.
  Future<void> setMemberPermissions(String id, Map<String, bool> overrides) =>
      _db.from('profiles').update({'permissions': overrides}).eq('id', id);

  /// الإيقاف عبر الخادم: يمنع تسجيل الدخول أيضًا
  Future<void> setMemberActive(String id, bool active) => _admin({'action': 'set_active', 'user_id': id, 'active': active});

  // ------------------------------------------------------------------
  // إدارة المالك للأعضاء (دالة admin-users)
  // ------------------------------------------------------------------
  Future<void> _admin(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke('admin-users', body: body);
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
    } on FunctionException catch (e) {
      final d = e.details;
      if (e.status == 404) throw Exception(tr('دالة admin-users غير منشورة بعد في Supabase'));
      throw Exception(d is Map && d['error'] != null ? d['error'] : (d ?? e.reasonPhrase ?? e.status));
    }
  }

  Future<void> adminUpdateMember(String id, {String? name, String? jobTitle, String? phone, String? email}) => _admin({
        'action': 'update',
        'user_id': id,
        if (name != null) 'name': name,
        if (jobTitle != null) 'job_title': jobTitle,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
      });

  Future<void> adminSetPassword(String id, String password) =>
      _admin({'action': 'set_password', 'user_id': id, 'password': password});

  Future<void> adminDeleteMember(String id, String transferTo) =>
      _admin({'action': 'delete', 'user_id': id, 'transfer_to': transferTo});

  // ------------------------------------------------------------------
  // الحساب الشخصي
  // ------------------------------------------------------------------
  Future<void> updateMyProfile({String? name, String? phone}) => _db.from('profiles').update({
        if (name != null) 'name': name.trim(),
        if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.trim(),
      }).eq('id', _db.auth.currentUser!.id);

  /// يُرسل رابط تأكيد للبريد الجديد؛ يتغير البريد بعد الضغط عليه
  Future<void> changeMyEmail(String email) => _db.auth.updateUser(UserAttributes(email: email.trim()));

  Future<void> changeMyPassword(String password) => _db.auth.updateUser(UserAttributes(password: password));

  Future<void> uploadMyAvatar(List<int> bytes, String mime) async {
    final uid = _db.auth.currentUser!.id;
    final ext = mime.contains('png') ? 'png' : (mime.contains('webp') ? 'webp' : 'jpg');
    final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    final url = _db.storage.from('avatars').getPublicUrl(path);
    await _db.from('profiles').update({'avatar_url': url}).eq('id', uid);
  }

  Future<void> removeMyAvatar() =>
      _db.from('profiles').update({'avatar_url': null}).eq('id', _db.auth.currentUser!.id);

  /// رابط استعادة كلمة المرور يعود للتطبيق نفسه
  Future<void> sendPasswordReset(String email) => _db.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: Uri.base.replace(queryParameters: const {}, fragment: '').toString().split('#').first,
      );


  // ---------------- لوحة التحكم ----------------
  Future<List<FieldSetting>> fieldSettings(ConfigEntity e) async {
    final rows = await _db
        .from('field_settings')
        .select()
        .eq('entity', e.db)
        .isFilter('deleted_at', null)
        .order('sort_order', ascending: true);
    return rows.map(FieldSetting.fromMap).toList();
  }

  Future<Map<ConfigEntity, int>> fieldCounts() async {
    final rows = await _db.from('field_settings').select('entity, is_system').isFilter('deleted_at', null);
    final counts = <ConfigEntity, int>{};
    for (final r in rows) {
      final e = ConfigEntity.from(r['entity'] as String?);
      if (r['is_system'] != true) counts[e] = (counts[e] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> updateField(String id, Map<String, dynamic> changes) =>
      _db.from('field_settings').update(changes).eq('id', id);

  Future<void> createField({
    required ConfigEntity entity,
    required String label,
    String? labelEn,
    required FieldType type,
    required List<String> options,
    required bool required,
    required bool showOnCard,
    required int sortOrder,
  }) =>
      _db.from('field_settings').insert({
        'entity': entity.db,
        'key': 'cf_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        'label': label,
        'label_en': labelEn,
        'type': type.db,
        'options': options,
        'required': required,
        'show_on_card': showOnCard,
        'sort_order': sortOrder,
      });

  Future<void> deleteField(String id) =>
      _db.from('field_settings').update({'deleted_at': _now()}).eq('id', id);

  Future<void> reorderFields(List<FieldSetting> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i + 1) {
        await _db.from('field_settings').update({'sort_order': i + 1}).eq('id', ordered[i].id);
      }
    }
  }

  Future<List<StatusLabel>> statusLabels(ConfigEntity e) async {
    final rows = await _db
        .from('status_labels')
        .select()
        .eq('entity', e.db)
        .order('sort_order', ascending: true);
    return rows.map(StatusLabel.fromMap).toList();
  }

  Future<void> updateStatusLabel(ConfigEntity e, String status, String label, String color, {String? labelEn}) => _db
      .from('status_labels')
      .update({'label': label, 'label_en': labelEn, 'color': color})
      .eq('entity', e.db)
      .eq('status', status);

  // ---------------- إدارة البيانات والسلة ----------------
  Future<List<Map<String, dynamic>>> manageRows(String table) async {
    final select = switch (table) {
      'requests' => 'id, number, title, status, client:clients(name)',
      'tasks' => 'id, title, status, due_at',
      'clients' => 'id, name, city, status',
      'meetings' => 'id, title, start_at, status',
      'notes' => 'id, content, type, created_at',
      _ => 'id',
    };
    final order = switch (table) {
      'requests' => 'number',
      'meetings' => 'start_at',
      'clients' => 'name',
      _ => 'created_at',
    };
    final rows = await _db
        .from(table)
        .select(select)
        .isFilter('deleted_at', null)
        .order(order, ascending: table == 'clients')
        .limit(300);
    return rows;
  }

  Future<void> softDelete(String table, List<String> ids) =>
      _db.from(table).update({'deleted_at': _now()}).inFilter('id', ids);

  Future<void> setStatus(String table, List<String> ids, String status) =>
      _db.from(table).update({'status': status}).inFilter('id', ids);

  Future<void> rename(String table, String id, String field, String value) =>
      _db.from(table).update({field: value}).eq('id', id);

  Future<int> deleteCancelledRequests() async {
    final rows = await _db
        .from('requests')
        .update({'deleted_at': _now()})
        .eq('status', 'cancelled')
        .isFilter('deleted_at', null)
        .select('id');
    return rows.length;
  }

  Future<List<TrashItem>> trash() async {
    final results = await Future.wait<dynamic>([
      _db.from('trash_items').select().order('deleted_at', ascending: false),
      _db.from('profiles').select('id, name'),
    ]);
    final names = {
      for (final p in results[1] as List) p['id'] as String: (p['name'] ?? '') as String,
    };
    return (results[0] as List)
        .map((m) => TrashItem.fromMap(Map<String, dynamic>.from(m as Map), names))
        .toList();
  }

  Future<void> restore(TrashItem t) => _db.from(t.table).update({'deleted_at': null}).eq('id', t.id);

  Future<void> deleteForever(TrashItem t) => _db.from(t.table).delete().eq('id', t.id);

  // ---------------- تفاصيل الطلب ----------------
  Future<RequestDetail> requestDetail(String id) async {
    final row = await _db.from('requests').select(RequestDetail.select).eq('id', id).single();
    return RequestDetail.fromMap(row);
  }

  Future<List<RequestItem>> clientRequests(String clientId) async {
    final rows = await _db
        .from('requests')
        .select(RequestItem.select)
        .eq('client_id', clientId)
        .isFilter('deleted_at', null)
        .order('received_at', ascending: false);
    return rows.map(RequestItem.fromMap).toList();
  }

  Future<void> updateRequest(String id, Map<String, dynamic> changes) =>
      _db.from('requests').update(changes).eq('id', id);

  Future<List<Invoice>> requestInvoices(String requestId) async {
    final rows = await _db
        .from('invoices')
        .select(Invoice.select)
        .eq('request_id', requestId)
        .isFilter('deleted_at', null)
        .order('issue_date', ascending: true);
    return rows.map(Invoice.fromMap).toList();
  }

  Future<void> setStepDone(String id, bool done) =>
      _db.from('request_steps').update({'is_done': done}).eq('id', id);

  Future<void> addStep(String requestId, String title, int order) =>
      _db.from('request_steps').insert({'request_id': requestId, 'title': title, 'sort_order': order});

  Future<void> renameStep(String id, String title) =>
      _db.from('request_steps').update({'title': title}).eq('id', id);

  Future<void> deleteStep(String id) => _db.from('request_steps').delete().eq('id', id);

  // ---------------- الإشعارات ----------------
  Future<List<NotificationItem>> notifications() async {
    final rows = await _db
        .from('notifications')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(NotificationItem.fromMap).toList();
  }

  Future<void> markNotificationRead(String id) =>
      _db.from('notifications').update({'read_at': _now()}).eq('id', id).isFilter('read_at', null);

  Future<void> markAllNotificationsRead() =>
      _db.from('notifications').update({'read_at': _now()}).eq('user_id', _uid).isFilter('read_at', null);

  Future<void> clearReadNotifications() =>
      _db.from('notifications').delete().eq('user_id', _uid).not('read_at', 'is', null);

  Future<void> sendTestNotification() => _db.from('notifications').insert({
        'user_id': _uid,
        'type': 'test',
        'title': tr('الإشعارات تعمل ✓'),
        'body': tr('هكذا ستصلك التذكيرات من Zypro'),
        'url': '/home',
      });

  Future<Map<String, dynamic>> notifyPrefs() async {
    final row = await _db.from('profiles').select('notify_prefs').eq('id', _uid).single();
    return Map<String, dynamic>.from((row['notify_prefs'] ?? const {}) as Map);
  }

  Future<void> setNotifyPrefs(Map<String, dynamic> prefs) =>
      _db.from('profiles').update({'notify_prefs': prefs}).eq('id', _uid);

  Future<void> savePushSubscription(String subscriptionJson, String? userAgent) async {
    final sub = Map<String, dynamic>.from(jsonDecode(subscriptionJson) as Map);
    final keys = Map<String, dynamic>.from(sub['keys'] as Map);
    await _db.from('push_subscriptions').upsert({
      'user_id': _uid,
      'endpoint': sub['endpoint'],
      'p256dh': keys['p256dh'],
      'auth': keys['auth'],
      if (userAgent != null) 'user_agent': userAgent,
    }, onConflict: 'endpoint');
  }

  Future<void> deletePushSubscription(String endpoint) =>
      _db.from('push_subscriptions').delete().eq('endpoint', endpoint);

  Future<int> myDeviceCount() async {
    final rows = await _db.from('push_subscriptions').select('id').eq('user_id', _uid);
    return rows.length;
  }

  // ---------------- التقارير ----------------
  Future<ReportData> reportDashboard(DateTime from, DateTime to, {String? member}) async {
    final res = await _db.rpc('report_dashboard', params: {
      'p_from': _isoDate(from),
      'p_to': _isoDate(to),
      if (member != null) 'p_member': member,
    });
    return ReportData(Map<String, dynamic>.from(res as Map));
  }

  Future<List<ReportRow>> reportList(String kind, DateTime from, DateTime to, {String? member}) async {
    final res = await _db.rpc('report_list', params: {
      'p_kind': kind,
      'p_from': _isoDate(from),
      'p_to': _isoDate(to),
      if (member != null) 'p_member': member,
    });
    return (res as List).map((e) => ReportRow(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> saveGoal(DateTime month, String metric, num target) => _db.from('report_goals').upsert(
        {'month': _isoDate(DateTime(month.year, month.month)), 'metric': metric, 'target': target},
        onConflict: 'month,metric',
      );

  // ---------------- التقارير المخصصة والمتقدمة ----------------
  Future<CustomResult> reportCustom(Map<String, dynamic> query) async {
    final res = await _db.rpc('report_custom', params: {'p': query});
    return CustomResult(Map<String, dynamic>.from(res as Map));
  }

  Future<List<SavedReport>> savedReports() async {
    final rows = await _db.from('saved_reports').select().order('created_at');
    return rows.map((r) => SavedReport.fromMap(r)).toList();
  }

  Future<void> saveReport({
    String? id,
    required String name,
    required CustomConfig config,
    bool shared = false,
    bool pinned = false,
    bool onTv = false,
  }) async {
    final data = {
      'name': name,
      'config': config.toJson(),
      'shared': shared,
      'pinned': pinned,
      'on_tv': onTv,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id == null) {
      await _db.from('saved_reports').insert({...data, 'owner_id': _uid});
    } else {
      await _db.from('saved_reports').update(data).eq('id', id);
    }
  }

  Future<void> deleteReport(String id) => _db.from('saved_reports').delete().eq('id', id);

  Future<Map<String, dynamic>> reportWorkload(int days) async =>
      Map<String, dynamic>.from(await _db.rpc('report_workload', params: {'p_days': days}) as Map);

  Future<Map<String, dynamic>> reportFunnel(DateTime from, DateTime to) async => Map<String, dynamic>.from(
      await _db.rpc('report_funnel', params: {'p_from': _isoDate(from), 'p_to': _isoDate(to)}) as Map);

  Future<Map<String, dynamic>> clientTiers() async =>
      Map<String, dynamic>.from(await _db.rpc('report_client_tiers') as Map);

  Future<void> deleteGoal(DateTime month, String metric) => _db
      .from('report_goals')
      .delete()
      .eq('month', _isoDate(DateTime(month.year, month.month)))
      .eq('metric', metric);
}

// ---------------- مزوّدات Riverpod ----------------
final sectionRepoProvider = Provider((_) => SectionRepository());

final projectsProvider = FutureProvider.family<List<Project>, ProjectStatus>(
  (ref, s) => ref.watch(sectionRepoProvider).projects(s),
);
final projectCountsProvider = FutureProvider<Map<ProjectStatus, int>>(
  (ref) => ref.watch(sectionRepoProvider).projectCounts(),
);
final projectProvider = FutureProvider.family<Project, String>(
  (ref, id) => ref.watch(sectionRepoProvider).project(id),
);
final milestonesProvider = FutureProvider.family<List<Milestone>, String>(
  (ref, id) => ref.watch(sectionRepoProvider).milestones(id),
);
final projectTasksProvider = FutureProvider.family<List<TaskItem>, String>(
  (ref, id) => ref.watch(sectionRepoProvider).projectTasks(id),
);
final projectRequestsProvider = FutureProvider.family<List<RequestItem>, String>(
  (ref, id) => ref.watch(sectionRepoProvider).projectRequests(id),
);

final invoicesProvider = FutureProvider<List<Invoice>>((ref) => ref.watch(sectionRepoProvider).invoices());
final financeSummaryProvider =
    FutureProvider<FinanceSummary>((ref) => ref.watch(sectionRepoProvider).financeSummary());
final quotesProvider = FutureProvider<List<Quote>>((ref) => ref.watch(sectionRepoProvider).quotes());

final daftraStateProvider = FutureProvider<DaftraSyncState>((ref) => ref.watch(sectionRepoProvider).daftraState());

final notesProvider = FutureProvider<List<NoteItem>>((ref) => ref.watch(sectionRepoProvider).notes());

final teamMembersProvider = FutureProvider<List<TeamMember>>((ref) => ref.watch(sectionRepoProvider).team());

final fieldSettingsProvider = FutureProvider.family<List<FieldSetting>, ConfigEntity>(
  (ref, e) => ref.watch(sectionRepoProvider).fieldSettings(e),
);
final fieldConfigProvider = FutureProvider.family<FieldConfig, ConfigEntity>(
  (ref, e) async => FieldConfig(await ref.watch(fieldSettingsProvider(e).future)),
);
final fieldCountsProvider =
    FutureProvider<Map<ConfigEntity, int>>((ref) => ref.watch(sectionRepoProvider).fieldCounts());
final statusLabelsProvider = FutureProvider.family<List<StatusLabel>, ConfigEntity>(
  (ref, e) => ref.watch(sectionRepoProvider).statusLabels(e),
);

final manageRowsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, table) => ref.watch(sectionRepoProvider).manageRows(table),
);
final trashProvider = FutureProvider<List<TrashItem>>((ref) => ref.watch(sectionRepoProvider).trash());

/// تقرير مخصص — المفتاح هو CustomConfig.key
final customReportProvider = FutureProvider.autoDispose.family<CustomResult, String>(
  (ref, key) => ref.watch(sectionRepoProvider).reportCustom(Map<String, dynamic>.from(jsonDecode(key) as Map)),
);
final savedReportsProvider = FutureProvider<List<SavedReport>>((ref) => ref.watch(sectionRepoProvider).savedReports());
final workloadProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(sectionRepoProvider).reportWorkload(14));
final funnelProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (DateTime, DateTime)>(
  (ref, k) => ref.watch(sectionRepoProvider).reportFunnel(k.$1, k.$2),
);
final clientTiersProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(sectionRepoProvider).clientTiers());

/// (من، إلى، عضو)
final reportDashboardProvider = FutureProvider.family<ReportData, (DateTime, DateTime, String?)>(
  (ref, k) => ref.watch(sectionRepoProvider).reportDashboard(k.$1, k.$2, member: k.$3),
);

final requestDetailProvider = FutureProvider.family<RequestDetail, String>(
  (ref, id) => ref.watch(sectionRepoProvider).requestDetail(id),
);
final notificationsProvider =
    FutureProvider<List<NotificationItem>>((ref) => ref.watch(sectionRepoProvider).notifications());
final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.isRead).length ?? 0,
);
final notifyPrefsProvider =
    FutureProvider<Map<String, dynamic>>((ref) => ref.watch(sectionRepoProvider).notifyPrefs());
final myDeviceCountProvider = FutureProvider<int>((ref) => ref.watch(sectionRepoProvider).myDeviceCount());

final requestInvoicesProvider = FutureProvider.family<List<Invoice>, String>(
  (ref, id) => ref.watch(sectionRepoProvider).requestInvoices(id),
);
final clientRequestsProvider = FutureProvider.family<List<RequestItem>, String>(
  (ref, id) => ref.watch(sectionRepoProvider).clientRequests(id),
);

/// تحديث كل بيانات المرحلة الثانية مع بيانات المرحلة الأولى.
void refreshSections(WidgetRef ref) {
  refreshAll(ref);
  ref.invalidate(projectsProvider);
  ref.invalidate(projectCountsProvider);
  ref.invalidate(projectProvider);
  ref.invalidate(milestonesProvider);
  ref.invalidate(projectTasksProvider);
  ref.invalidate(projectRequestsProvider);
  ref.invalidate(invoicesProvider);
  ref.invalidate(financeSummaryProvider);
  ref.invalidate(quotesProvider);
  ref.invalidate(reportDashboardProvider);
  ref.invalidate(savedReportsProvider);
  ref.invalidate(customReportProvider);
  ref.invalidate(workloadProvider);
  ref.invalidate(funnelProvider);
  ref.invalidate(clientTiersProvider);
  ref.invalidate(daftraStateProvider);
  ref.invalidate(notesProvider);
  ref.invalidate(teamMembersProvider);
  ref.invalidate(fieldSettingsProvider);
  ref.invalidate(fieldConfigProvider);
  ref.invalidate(fieldCountsProvider);
  ref.invalidate(statusLabelsProvider);
  ref.invalidate(manageRowsProvider);
  ref.invalidate(trashProvider);
  ref.invalidate(requestDetailProvider);
  ref.invalidate(clientRequestsProvider);
  ref.invalidate(requestInvoicesProvider);
  ref.invalidate(notificationsProvider);
}
