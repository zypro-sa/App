import 'report_models.dart';

/// شخص مختصر (مسؤول بند أو مشروع)
class PlanPerson {
  const PlanPerson(this.id, this.name, this.avatarUrl);
  final String id;
  final String name;
  final String? avatarUrl;

  static List<PlanPerson> list(Object? v) => [
        for (final p in (v as List? ?? const []))
          if (p is Map) PlanPerson('${p['id']}', '${p['name'] ?? ''}', p['avatar_url'] as String?),
      ];
}

DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// حالة بند الخطة
enum PlanStatus {
  todo('todo', 'لم يبدأ'),
  on('on', 'على المسار'),
  risk('risk', 'متعثر'),
  done('done', 'منجز');

  const PlanStatus(this.db, this.label);
  final String db;
  final String label;
  static PlanStatus from(Object? v) => values.firstWhere((s) => s.db == v, orElse: () => todo);
}

class PlanItem {
  PlanItem(Map<String, dynamic> m)
      : id = '${m['id']}',
        title = '${m['title'] ?? ''}',
        notes = m['notes'] as String?,
        status = PlanStatus.from(m['status']),
        progress = ReportData.n(m['progress']).toInt(),
        dueDate = _d(m['due_date']),
        kpi = m['kpi'] as String?,
        kpiTarget = ReportData.nn(m['kpi_target']),
        kpiValue = ReportData.nn(m['kpi_value']),
        overdue = m['overdue'] == true,
        owners = PlanPerson.list(m['owners']);
  final String id;
  final String title;
  final String? notes;
  final PlanStatus status;
  final int progress;
  final DateTime? dueDate;
  final String? kpi;
  final num? kpiTarget;
  final num? kpiValue;
  final bool overdue;
  final List<PlanPerson> owners;
}

/// حالة تنفيذ القرار
enum DecisionState {
  done('done', 'نُفّذ'),
  on('on', 'جارٍ'),
  late('late', 'متأخر');

  const DecisionState(this.db, this.label);
  final String db;
  final String label;
  static DecisionState from(Object? v) => values.firstWhere((s) => s.db == v, orElse: () => on);
}

class PlanDecision {
  PlanDecision(Map<String, dynamic> m)
      : id = '${m['id']}',
        text = '${m['text'] ?? ''}',
        meeting = m['meeting'] as String?,
        meetingDate = _d(m['meeting_date']),
        dueDate = _d(m['due_date']),
        owner = m['owner'] as String?,
        state = DecisionState.from(m['state']);
  final String id;
  final String text;
  final String? meeting;
  final DateTime? meetingDate;
  final DateTime? dueDate;
  final String? owner;
  final DecisionState state;
}

class PlanTopic {
  PlanTopic(Map<String, dynamic> m)
      : id = '${m['id']}',
        title = '${m['title'] ?? ''}',
        minutes = (m['minutes'] as num?)?.toInt(),
        status = '${m['status'] ?? 'open'}',
        proposer = m['proposer'] as String?,
        proposedBy = m['proposed_by'] as String?;
  final String id;
  final String title;
  final int? minutes;
  final String status;
  final String? proposer;
  final String? proposedBy;
}

/// مراحل المشاريع والأفكار
enum InitiativeStage {
  idea('idea', 'أفكار'),
  active('active', 'قيد التنفيذ'),
  waiting('waiting', 'بانتظار'),
  done('done', 'منجز');

  const InitiativeStage(this.db, this.label);
  final String db;
  final String label;
  static InitiativeStage from(Object? v) => values.firstWhere((s) => s.db == v, orElse: () => idea);
}

const initiativeCategories = <String, String>{
  'dev': 'تطوير',
  'service': 'خدمة جديدة',
  'marketing': 'تسويق',
  'ops': 'تشغيل',
  'improve': 'تحسين',
};

class Initiative {
  Initiative(Map<String, dynamic> m)
      : id = '${m['id']}',
        title = '${m['title'] ?? ''}',
        description = m['description'] as String?,
        category = '${m['category'] ?? 'dev'}',
        stage = InitiativeStage.from(m['stage']),
        progress = ReportData.n(m['progress']).toInt(),
        dueDate = _d(m['due_date']),
        votes = ReportData.n(m['votes']).toInt(),
        voted = m['voted'] == true,
        creator = m['creator'] as String?,
        createdBy = m['created_by'] as String?,
        owners = PlanPerson.list(m['owners']);
  final String id;
  final String title;
  final String? description;
  final String category;
  final InitiativeStage stage;
  final int progress;
  final DateTime? dueDate;
  final int votes;
  final bool voted;
  final String? creator;
  final String? createdBy;
  final List<PlanPerson> owners;
}

/// كل بيانات تبويب «جدول الأعمال»
class WorkPlan {
  WorkPlan(this.raw);
  final Map<String, dynamic> raw;

  bool get canEdit => raw['can_edit'] == true;
  List<PlanItem> get items => [for (final m in (raw['items'] as List? ?? const [])) if (m is Map) PlanItem(Map<String, dynamic>.from(m))];
  List<PlanDecision> get decisions =>
      [for (final m in (raw['decisions'] as List? ?? const [])) if (m is Map) PlanDecision(Map<String, dynamic>.from(m))];
  List<PlanTopic> get topics => [for (final m in (raw['topics'] as List? ?? const [])) if (m is Map) PlanTopic(Map<String, dynamic>.from(m))];
  List<Initiative> get initiatives =>
      [for (final m in (raw['initiatives'] as List? ?? const [])) if (m is Map) Initiative(Map<String, dynamic>.from(m))];

  /// متوسط تقدم البنود
  int get planProgress {
    final l = items;
    if (l.isEmpty) return 0;
    return (l.fold<int>(0, (a, i) => a + i.progress) / l.length).round();
  }
}
