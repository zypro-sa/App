// نماذج المرحلة الثانية: المشاريع، المالية، الملاحظات، الفريق، الإعدادات، السلة، التقارير.
import '../core/permissions.dart';
import 'models.dart';

DateTime? _ts(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
DateTime? _d(dynamic v) => v == null ? null : DateTime.parse(v as String);
String? _nested(dynamic v, String key) => v is Map ? v[key]?.toString() : null;
num _num(dynamic v) => v == null ? 0 : (v is num ? v : num.tryParse(v.toString()) ?? 0);

// ---------------- المشاريع ----------------
enum ProjectStatus {
  planning('planning', 'تخطيط'),
  active('active', 'جارٍ'),
  onHold('on_hold', 'معلّق'),
  completed('completed', 'مكتمل'),
  cancelled('cancelled', 'ملغى');

  const ProjectStatus(this.db, this.label);
  final String db;
  final String label;

  static ProjectStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => planning);
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    this.clientId,
    this.clientName,
    this.managerId,
    this.managerName,
    this.endDate,
    this.contractValue,
    this.nextMilestone,
    this.milestonesDone = 0,
    this.milestonesTotal = 0,
  });

  final String id;
  final String name;
  final ProjectStatus status;
  final int progress;
  final String? clientId;
  final String? clientName;
  final String? managerId;
  final String? managerName;
  final DateTime? endDate;
  final num? contractValue;
  final String? nextMilestone;
  final int milestonesDone;
  final int milestonesTotal;

  int? get daysLeft {
    if (endDate == null) return null;
    final n = DateTime.now();
    return endDate!.difference(DateTime(n.year, n.month, n.day)).inDays;
  }

  static const select =
      'id, name, status, progress, client_id, manager_id, end_date, contract_value, '
      'client:clients(name), manager:profiles!projects_manager_id_fkey(name), '
      'milestones(title, is_done, due_date, deleted_at)';

  factory Project.fromMap(Map<String, dynamic> m) {
    final ms = ((m['milestones'] ?? []) as List)
        .where((x) => x['deleted_at'] == null)
        .toList()
      ..sort((a, b) => ((a['due_date'] ?? '9999') as String).compareTo((b['due_date'] ?? '9999') as String));
    final next = ms.where((x) => x['is_done'] != true).firstOrNull;
    return Project(
      id: m['id'] as String,
      name: m['name'] as String,
      status: ProjectStatus.from(m['status'] as String?),
      progress: (m['progress'] ?? 0) as int,
      clientId: m['client_id'] as String?,
      clientName: _nested(m['client'], 'name'),
      managerId: m['manager_id'] as String?,
      managerName: _nested(m['manager'], 'name'),
      endDate: _d(m['end_date']),
      contractValue: m['contract_value'] == null ? null : _num(m['contract_value']),
      nextMilestone: next?['title'] as String?,
      milestonesDone: ms.where((x) => x['is_done'] == true).length,
      milestonesTotal: ms.length,
    );
  }
}

class Milestone {
  Milestone({required this.id, required this.title, required this.isDone, this.dueDate});

  final String id;
  final String title;
  final bool isDone;
  final DateTime? dueDate;

  factory Milestone.fromMap(Map<String, dynamic> m) => Milestone(
        id: m['id'] as String,
        title: m['title'] as String,
        isDone: (m['is_done'] ?? false) as bool,
        dueDate: _d(m['due_date']),
      );
}

// ---------------- المالية ----------------
enum InvoiceStatus {
  issued('issued', 'صادرة'),
  partiallyPaid('partially_paid', 'مدفوعة جزئيًا'),
  paid('paid', 'مدفوعة'),
  overdue('overdue', 'متأخرة'),
  voided('void', 'ملغاة');

  const InvoiceStatus(this.db, this.label);
  final String db;
  final String label;

  static InvoiceStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => issued);
}

class Invoice {
  Invoice({
    required this.id,
    required this.number,
    required this.total,
    required this.paid,
    required this.issueDate,
    required this.dueDate,
    required this.status,
    this.clientName,
  });

  final String id;
  final String number;
  final num total;
  final num paid;
  final DateTime issueDate;
  final DateTime dueDate;
  final InvoiceStatus status;
  final String? clientName;

  num get remaining => (total - paid) < 0 ? 0 : total - paid;
  bool get isOpen => status != InvoiceStatus.paid && status != InvoiceStatus.voided;
  bool get isOverdue {
    final n = DateTime.now();
    return isOpen && dueDate.isBefore(DateTime(n.year, n.month, n.day));
  }

  static const select =
      'id, number, total, issue_date, due_date, status, client:clients(name), payments(amount, paid_at, deleted_at)';

  factory Invoice.fromMap(Map<String, dynamic> m) {
    final pays = ((m['payments'] ?? []) as List).where((p) => p['deleted_at'] == null);
    return Invoice(
      id: m['id'] as String,
      number: m['number'] as String,
      total: _num(m['total']),
      paid: pays.fold<num>(0, (a, p) => a + _num(p['amount'])),
      issueDate: _d(m['issue_date'])!,
      dueDate: _d(m['due_date'])!,
      status: InvoiceStatus.from(m['status'] as String?),
      clientName: _nested(m['client'], 'name'),
    );
  }
}

class PaymentEntry {
  PaymentEntry(this.amount, this.paidAt);
  final num amount;
  final DateTime paidAt;
}

class FinanceSummary {
  FinanceSummary({required this.due, required this.overdue, required this.collectedThisMonth});
  final num due;
  final num overdue;
  final num collectedThisMonth;
}

enum QuoteStatus {
  draft('draft', 'مسودة'),
  sent('sent', 'مُرسل'),
  accepted('accepted', 'مقبول'),
  rejected('rejected', 'مرفوض'),
  expired('expired', 'منتهٍ');

  const QuoteStatus(this.db, this.label);
  final String db;
  final String label;

  static QuoteStatus from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => draft);
}

class Quote {
  Quote({
    required this.id,
    required this.number,
    required this.amount,
    required this.vat,
    required this.status,
    this.clientName,
    this.sentAt,
  });

  final String id;
  final String number;
  final num amount;
  final num vat;
  final QuoteStatus status;
  final String? clientName;
  final DateTime? sentAt;

  num get total => amount + vat;

  static const select = 'id, number, amount, vat_amount, status, sent_at, client:clients(name)';

  factory Quote.fromMap(Map<String, dynamic> m) => Quote(
        id: m['id'] as String,
        number: m['number'] as String,
        amount: _num(m['amount']),
        vat: _num(m['vat_amount']),
        status: QuoteStatus.from(m['status'] as String?),
        clientName: _nested(m['client'], 'name'),
        sentAt: _d(m['sent_at']),
      );
}

// ---------------- الملاحظات ----------------
enum NoteType {
  general('general', 'عامة'),
  idea('idea', 'فكرة'),
  call('call', 'مكالمة');

  const NoteType(this.db, this.label);
  final String db;
  final String label;

  static NoteType from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => general);
}

class NoteItem {
  NoteItem({
    required this.id,
    required this.content,
    required this.type,
    required this.pinned,
    required this.createdAt,
    this.convertedTaskId,
  });

  final String id;
  final String content;
  final NoteType type;
  final bool pinned;
  final DateTime createdAt;
  final String? convertedTaskId;

  factory NoteItem.fromMap(Map<String, dynamic> m) => NoteItem(
        id: m['id'] as String,
        content: m['content'] as String,
        type: NoteType.from(m['type'] as String?),
        pinned: (m['is_pinned'] ?? false) as bool,
        createdAt: _ts(m['created_at'])!,
        convertedTaskId: m['converted_task_id'] as String?,
      );
}

// ---------------- الفريق ----------------
class TeamMember {
  TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.pending,
    required this.openTasks,
    required this.openRequests,
    this.jobTitle,
    this.permissions = const {},
  });

  final Map<String, dynamic> permissions;
  bool can(String key) => Permissions.effective(role, permissions, key);
  bool isCustomized(String key) =>
      role != UserRole.owner && permissions[key] is bool && permissions[key] != Permissions.roleDefault(role, key);

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final bool pending;
  final int openTasks;
  final int openRequests;
  final String? jobTitle;

  String get initial => name.isEmpty ? '؟' : name.substring(0, 1);

  factory TeamMember.fromMap(Map<String, dynamic> m) => TeamMember(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        role: UserRole.from(m['role'] as String?),
        isActive: (m['is_active'] ?? true) as bool,
        pending: (m['pending'] ?? false) as bool,
        openTasks: _num(m['open_tasks']).toInt(),
        openRequests: _num(m['open_requests']).toInt(),
        jobTitle: m['job_title'] as String?,
        permissions: Map<String, dynamic>.from((m['permissions'] ?? const {}) as Map),
      );
}

// ---------------- لوحة التحكم ----------------
enum ConfigEntity {
  request('request', 'الطلبات', 'requests'),
  task('task', 'المهام', 'tasks'),
  meeting('meeting', 'الاجتماعات', 'meetings'),
  client('client', 'العملاء', 'clients'),
  project('project', 'المشاريع', 'projects');

  const ConfigEntity(this.db, this.label, this.table);
  final String db;
  final String label;
  final String table;

  static ConfigEntity from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => request);
}

enum FieldType {
  text('text', 'نص'),
  number('number', 'رقم'),
  date('date', 'تاريخ'),
  list('list', 'قائمة'),
  boolean('bool', 'نعم/لا'),
  money('money', 'مبلغ');

  const FieldType(this.db, this.label);
  final String db;
  final String label;

  static FieldType from(String? v) =>
      values.firstWhere((e) => e.db == v, orElse: () => text);
}

class FieldSetting {
  FieldSetting({
    required this.id,
    required this.entity,
    required this.key,
    required this.label,
    required this.type,
    required this.options,
    required this.isSystem,
    required this.isLocked,
    required this.required,
    required this.visible,
    required this.showOnCard,
    required this.sortOrder,
  });

  final String id;
  final ConfigEntity entity;
  final String key;
  final String label;
  final FieldType type;
  final List<String> options;
  final bool isSystem;
  final bool isLocked;
  final bool required;
  final bool visible;
  final bool showOnCard;
  final int sortOrder;

  bool get isCustom => !isSystem;

  String get meta {
    final parts = <String>[type.label];
    if (type == FieldType.list && options.isNotEmpty) parts.add('${options.length} خيارات');
    parts.add(isLocked ? 'أساسي' : (isSystem ? 'افتراضي' : 'مخصص'));
    return parts.join(' · ');
  }

  factory FieldSetting.fromMap(Map<String, dynamic> m) => FieldSetting(
        id: m['id'] as String,
        entity: ConfigEntity.from(m['entity'] as String?),
        key: m['key'] as String,
        label: m['label'] as String,
        type: FieldType.from(m['type'] as String?),
        options: ((m['options'] ?? []) as List).map((e) => e.toString()).toList(),
        isSystem: (m['is_system'] ?? false) as bool,
        isLocked: (m['is_locked'] ?? false) as bool,
        required: (m['required'] ?? false) as bool,
        visible: (m['visible'] ?? true) as bool,
        showOnCard: (m['show_on_card'] ?? false) as bool,
        sortOrder: (m['sort_order'] ?? 0) as int,
      );
}

/// إعدادات الحقول لقسم واحد، مع دوال مساعدة للنماذج.
class FieldConfig {
  FieldConfig(this.fields);
  final List<FieldSetting> fields;

  FieldSetting? byKey(String key) => fields.where((f) => f.key == key).firstOrNull;
  bool isVisible(String key) => byKey(key)?.visible ?? true;
  bool isRequired(String key) => byKey(key)?.required ?? false;
  String labelOf(String key, String fallback) => byKey(key)?.label ?? fallback;
  List<String> optionsOf(String key) => byKey(key)?.options ?? const [];
  List<FieldSetting> get customVisible => fields.where((f) => f.isCustom && f.visible).toList();
}

class StatusLabel {
  StatusLabel({required this.status, required this.label, required this.color});
  final String status;
  final String label;
  final String color; // info | neutral | waiting | done | urgent

  factory StatusLabel.fromMap(Map<String, dynamic> m) => StatusLabel(
        status: m['status'] as String,
        label: m['label'] as String,
        color: (m['color'] ?? 'neutral') as String,
      );
}

// ---------------- السلة ----------------
class TrashItem {
  TrashItem({required this.entity, required this.id, required this.title, required this.deletedAt, this.deletedByName});

  final String entity;
  final String id;
  final String title;
  final DateTime deletedAt;
  final String? deletedByName;

  int get daysLeft => 30 - DateTime.now().difference(deletedAt).inDays;

  static const tables = {
    'request': 'requests',
    'task': 'tasks',
    'meeting': 'meetings',
    'client': 'clients',
    'project': 'projects',
    'note': 'notes',
    'followup': 'followups',
    'quote': 'quotes',
    'invoice': 'invoices',
  };

  static const labels = {
    'request': 'الطلبات',
    'task': 'المهام',
    'meeting': 'الاجتماعات',
    'client': 'العملاء',
    'project': 'المشاريع',
    'note': 'الملاحظات',
    'followup': 'المتابعات',
    'quote': 'عروض الأسعار',
    'invoice': 'الفواتير',
  };

  String get table => tables[entity]!;

  factory TrashItem.fromMap(Map<String, dynamic> m, Map<String, String> names) => TrashItem(
        entity: m['entity'] as String,
        id: m['id'] as String,
        title: (m['title'] ?? '') as String,
        deletedAt: _ts(m['deleted_at'])!,
        deletedByName: names[m['deleted_by']],
      );
}

// ---------------- التقارير ----------------
class ReportSummary {
  ReportSummary({
    required this.closedRequests,
    required this.previousClosed,
    required this.avgDays,
    required this.onTimePct,
    required this.tasksDone,
    required this.tasksTotal,
    required this.weekly,
    required this.team,
  });

  final int closedRequests;
  final int previousClosed;
  final num? avgDays;
  final int? onTimePct;
  final int tasksDone;
  final int tasksTotal;
  final List<(DateTime, int)> weekly;
  final List<(String, int, int?)> team; // الاسم، المنجز، نسبة الالتزام

  int? get changePct =>
      previousClosed == 0 ? null : (((closedRequests - previousClosed) / previousClosed) * 100).round();

  factory ReportSummary.fromMap(Map<String, dynamic> m) => ReportSummary(
        closedRequests: _num(m['closed_requests']).toInt(),
        previousClosed: _num(m['previous_closed_requests']).toInt(),
        avgDays: m['avg_days'] == null ? null : _num(m['avg_days']),
        onTimePct: m['on_time_pct'] == null ? null : _num(m['on_time_pct']).toInt(),
        tasksDone: _num(m['tasks_done']).toInt(),
        tasksTotal: _num(m['tasks_total']).toInt(),
        weekly: ((m['weekly'] ?? []) as List)
            .map((w) => (DateTime.parse(w['week'] as String), _num(w['count']).toInt()))
            .toList(),
        team: ((m['team'] ?? []) as List)
            .map((t) => (
                  (t['name'] ?? '') as String,
                  _num(t['done']).toInt(),
                  t['on_time_pct'] == null ? null : _num(t['on_time_pct']).toInt(),
                ))
            .toList(),
      );
}

// ---------------- تفاصيل الطلب وخطواته ----------------
class RequestStep {
  RequestStep({required this.id, required this.title, required this.isDone, required this.sortOrder, this.doneAt});

  final String id;
  final String title;
  final bool isDone;
  final int sortOrder;
  final DateTime? doneAt;

  factory RequestStep.fromMap(Map<String, dynamic> m) => RequestStep(
        id: m['id'] as String,
        title: m['title'] as String,
        isDone: (m['is_done'] ?? false) as bool,
        sortOrder: (m['sort_order'] ?? 0) as int,
        doneAt: _ts(m['done_at']),
      );
}

class RequestDetail {
  RequestDetail({
    required this.item,
    required this.steps,
    this.description,
    this.serviceType,
    this.paymentTerms,
    this.estimatedValue,
    this.clientId,
    this.assigneeId,
    this.receivedAt,
    this.custom = const {},
  });

  final RequestItem item;
  final List<RequestStep> steps;
  final String? description;
  final String? serviceType;
  final String? paymentTerms;
  final num? estimatedValue;
  final String? clientId;
  final String? assigneeId;
  final DateTime? receivedAt;
  final Map<String, dynamic> custom;

  int get doneSteps => steps.where((s) => s.isDone).length;

  static const select =
      'id, number, title, description, status, priority, progress, due_date, received_at, service_type, '
      'payment_terms, estimated_value, client_id, assignee_id, custom, client:clients(name), '
      'assignee:profiles!requests_assignee_id_fkey(name), '
      'request_steps(id, title, is_done, done_at, sort_order, deleted_at)';

  factory RequestDetail.fromMap(Map<String, dynamic> m) {
    final steps = ((m['request_steps'] ?? []) as List)
        .where((s) => s['deleted_at'] == null)
        .map((s) => RequestStep.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return RequestDetail(
      item: RequestItem.fromMap(m),
      steps: steps,
      description: m['description'] as String?,
      serviceType: m['service_type'] as String?,
      paymentTerms: m['payment_terms'] as String?,
      estimatedValue: m['estimated_value'] == null ? null : _num(m['estimated_value']),
      clientId: m['client_id'] as String?,
      assigneeId: m['assignee_id'] as String?,
      receivedAt: _ts(m['received_at']),
      custom: Map<String, dynamic>.from((m['custom'] ?? const {}) as Map),
    );
  }
}
