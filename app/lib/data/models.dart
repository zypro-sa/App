// نماذج البيانات في التطبيق — تطابق docs/data-model.md
import 'package:flutter/widgets.dart' show StringCharacters;

import '../core/permissions.dart';
import '../core/i18n.dart';

enum RequestStatus {
  newRequest('new', 'جديد'),
  inProgress('in_progress', 'قيد التنفيذ'),
  waitingClient('waiting_client', 'بانتظار العميل'),
  onHold('on_hold', 'معلّق'),
  closed('closed', 'مغلق'),
  cancelled('cancelled', 'ملغى');

  const RequestStatus(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  bool get isOpen => this != closed && this != cancelled;

  static RequestStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => newRequest);
}

enum Priority {
  low('low', 'منخفضة'),
  medium('medium', 'متوسطة'),
  high('high', 'عالية'),
  urgent('urgent', 'عاجلة');

  const Priority(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static Priority from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => medium);
}

enum TaskStatus {
  todo('todo', 'جديدة'),
  inProgress('in_progress', 'قيد التنفيذ'),
  done('done', 'منجزة');

  const TaskStatus(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static TaskStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => todo);
}

enum MeetingType {
  inPerson('in_person', 'حضوري'),
  online('online', 'عن بُعد'),
  call('call', 'مكالمة');

  const MeetingType(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static MeetingType from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => inPerson);
}

enum MeetingStatus {
  scheduled('scheduled', 'مجدول'),
  done('done', 'منعقد'),
  postponed('postponed', 'مؤجل'),
  cancelled('cancelled', 'ملغى');

  const MeetingStatus(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static MeetingStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => scheduled);
}

enum FollowupDirection {
  promised('promised', 'وعدتُ بها'),
  waiting('waiting', 'أنتظرها');

  const FollowupDirection(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static FollowupDirection from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => promised);
}

enum UserRole {
  owner('owner', 'المالك'),
  manager('manager', 'مدير'),
  employee('employee', 'موظف');

  const UserRole(this.db, this.labelAr);
  final String db;
  final String labelAr;
  String get label => tr(labelAr);

  static UserRole from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => employee);
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

String? _nested(dynamic v, String key) =>
    v is Map ? v[key]?.toString() : null;

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.role,
    this.jobTitle,
    this.permissions = const {},
    this.locale,
    this.email,
    this.phone,
    this.avatarUrl,
  });

  final String? email;
  final String? phone;
  final String? avatarUrl;

  final String id;
  final String name;
  final UserRole role;
  final String? jobTitle;
  final Map<String, dynamic> permissions;
  final String? locale; // لغة العضو: ar | en

  /// هل يملك هذه الصلاحية؟ (انظر core/permissions.dart)
  bool can(String key) => Permissions.effective(role, permissions, key);

  String get initial => name.isEmpty ? tr('؟') : name.characters.first;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        role: UserRole.from(m['role'] as String?),
        jobTitle: m['job_title'] as String?,
        permissions: Map<String, dynamic>.from((m['permissions'] ?? const {}) as Map),
        locale: m['locale'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        avatarUrl: m['avatar_url'] as String?,
      );
}

class RequestItem {
  RequestItem({
    required this.id,
    required this.number,
    required this.title,
    required this.status,
    required this.priority,
    required this.progress,
    this.clientName,
    this.assigneeName,
    this.dueDate,
  });

  final String id;
  final int number;
  final String title;
  final RequestStatus status;
  final Priority priority;
  final int progress;
  final String? clientName;
  final String? assigneeName;
  final DateTime? dueDate;

  bool get isOverdue {
    if (dueDate == null || !status.isOpen) return false;
    final today = DateTime.now();
    return dueDate!.isBefore(DateTime(today.year, today.month, today.day));
  }

  int get overdueDays => dueDate == null
      ? 0
      : DateTime.now().difference(dueDate!).inDays;

  static const select =
      'id, number, title, status, priority, progress, due_date, '
      'client:clients(name), assignee:profiles!requests_assignee_id_fkey(name)';

  factory RequestItem.fromMap(Map<String, dynamic> m) => RequestItem(
        id: m['id'] as String,
        number: m['number'] as int,
        title: m['title'] as String,
        status: RequestStatus.from(m['status'] as String?),
        priority: Priority.from(m['priority'] as String?),
        progress: (m['progress'] ?? 0) as int,
        clientName: _nested(m['client'], 'name'),
        assigneeName: _nested(m['assignee'], 'name'),
        dueDate: m['due_date'] == null ? null : DateTime.parse(m['due_date'] as String),
      );
}

class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.assigneeId,
    this.assignedById,
    this.dueAt,
    this.completedAt,
    this.requestNumber,
    this.clientName,
    this.assigneeName,
    this.fromMeeting = false,
    this.people = const [],
  });

  final String id;
  final String title;
  final TaskStatus status;
  final Priority priority;
  final String assigneeId;
  final String? assignedById;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final int? requestNumber;
  final String? clientName;
  final String? assigneeName;
  final bool fromMeeting;

  /// كل المسندة إليهم المهمة: (المعرّف، الاسم)
  final List<(String, String)> people;

  /// المهمة مشتركة بين أكثر من شخص؟
  bool get isShared => people.length > 1;

  /// أسماء المشاركين للعرض
  String get peopleLabel => people.isEmpty ? (assigneeName ?? '') : people.map((p) => p.$2).join('، ');

  bool get isDone => status == TaskStatus.done;

  bool get isOverdue {
    if (dueAt == null || isDone) return false;
    final today = DateTime.now();
    return dueAt!.isBefore(DateTime(today.year, today.month, today.day));
  }

  static const select =
      'id, title, status, priority, due_at, completed_at, assignee_id, assigned_by_id, '
      'source_decision_id, request:requests(number), client:clients(name), '
      'assignee:profiles!tasks_assignee_id_fkey(name), '
      'people:task_assignees(user_id, profile:profiles(name))';

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        status: TaskStatus.from(m['status'] as String?),
        priority: Priority.from(m['priority'] as String?),
        assigneeId: m['assignee_id'] as String,
        assignedById: m['assigned_by_id'] as String?,
        dueAt: _date(m['due_at']),
        completedAt: _date(m['completed_at']),
        requestNumber: m['request'] is Map ? m['request']['number'] as int? : null,
        clientName: _nested(m['client'], 'name'),
        assigneeName: _nested(m['assignee'], 'name'),
        fromMeeting: m['source_decision_id'] != null,
        people: [
          for (final a in (m['people'] as List? ?? const []))
            if (a is Map && a['user_id'] != null) (a['user_id'] as String, _nested(a['profile'], 'name') ?? ''),
        ],
      );
}

class AgendaItem {
  AgendaItem(this.order, this.title);
  final int order;
  final String title;
}

class Meeting {
  Meeting({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.type,
    this.location,
    this.clientId,
    this.clientName,
    this.minutes,
    this.agenda = const [],
    this.attendeeCount = 0,
    this.status = MeetingStatus.scheduled,
  });

  final MeetingStatus status;
  final String id;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final MeetingType type;
  final String? location;
  final String? clientId;
  final String? clientName;
  final String? minutes;
  final List<AgendaItem> agenda;
  final int attendeeCount;

  int get durationMinutes => endAt.difference(startAt).inMinutes;

  static const select =
      'id, title, start_at, end_at, type, location, minutes, client_id, status, '
      'client:clients(name), agenda_items(order, title), meeting_attendees(count)';

  factory Meeting.fromMap(Map<String, dynamic> m) {
    final agenda = ((m['agenda_items'] ?? []) as List)
        .map((a) => AgendaItem((a['order'] ?? 0) as int, a['title'] as String))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final att = m['meeting_attendees'];
    final count = att is List && att.isNotEmpty ? (att.first['count'] ?? 0) as int : 0;
    return Meeting(
      id: m['id'] as String,
      title: m['title'] as String,
      startAt: _date(m['start_at'])!,
      endAt: _date(m['end_at'])!,
      type: MeetingType.from(m['type'] as String?),
      location: m['location'] as String?,
      clientId: m['client_id'] as String?,
      clientName: _nested(m['client'], 'name'),
      minutes: m['minutes'] as String?,
      agenda: agenda,
      attendeeCount: count,
      status: MeetingStatus.from(m['status'] as String?),
    );
  }
}

class FollowUp {
  FollowUp({
    required this.id,
    required this.title,
    required this.direction,
    required this.dueAt,
    this.counterpart,
    this.isAuto = false,
  });

  final String id;
  final String title;
  final FollowupDirection direction;
  final DateTime dueAt;
  final String? counterpart;
  final bool isAuto;

  factory FollowUp.fromMap(Map<String, dynamic> m) => FollowUp(
        id: m['id'] as String,
        title: m['title'] as String,
        direction: FollowupDirection.from(m['direction'] as String?),
        dueAt: _date(m['due_at'])!,
        counterpart: m['counterpart'] as String?,
        isAuto: m['source'] == 'auto',
      );
}

class Client {
  Client({
    required this.id,
    required this.name,
    this.status,
    this.sector,
    this.city,
    this.crNumber,
    this.vatNumber,
    this.address,
    this.fromDaftra = false,
  });

  final String id;
  final String name;
  final String? status;
  final String? sector;
  final String? city;
  final String? crNumber;
  final String? vatNumber;
  final String? address;
  final bool fromDaftra;

  String get initial => name.isEmpty ? tr('؟') : name.characters.first;

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as String,
        name: m['name'] as String,
        status: m['status'] as String?,
        sector: m['sector'] as String?,
        city: m['city'] as String?,
        crNumber: m['cr_number'] as String?,
        vatNumber: m['vat_number'] as String?,
        address: m['address'] as String?,
        fromDaftra: m['daftra_id'] != null,
      );
}

class Contact {
  Contact({this.id = '', required this.name, this.position, this.phone, this.email, this.isPrimary = false});

  final String id;
  final String name;
  final String? position;
  final String? phone;
  final String? email;
  final bool isPrimary;

  factory Contact.fromMap(Map<String, dynamic> m) => Contact(
        id: (m['id'] ?? '') as String,
        name: m['name'] as String,
        position: m['position'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        isPrimary: (m['is_primary'] ?? false) as bool,
      );
}

class ClientDetail {
  ClientDetail({
    required this.client,
    required this.contacts,
    required this.openRequests,
    required this.contractsValue,
    required this.amountDue,
    required this.activity,
    this.summaryError,
  });

  /// إن تعذّر حساب الأرقام لا نُخفي بقية الملف
  final String? summaryError;
  final Client client;
  final List<Contact> contacts;
  final int openRequests;
  final num contractsValue;
  final num amountDue;
  final List<ActivityEntry> activity;

  Contact? get primaryContact =>
      contacts.where((c) => c.isPrimary).firstOrNull ?? contacts.firstOrNull;
}

class ActivityEntry {
  ActivityEntry(this.action, this.at);
  final String action;
  final DateTime at;
}

class HomeSummary {
  HomeSummary({
    required this.meetingsToday,
    required this.urgentTasks,
    required this.overdueRequests,
    required this.nextMeeting,
    required this.todayTasks,
    required this.followups,
  });

  final int meetingsToday;
  final int urgentTasks;
  final int overdueRequests;
  final Meeting? nextMeeting;
  final List<TaskItem> todayTasks;
  final List<FollowUp> followups;
}
