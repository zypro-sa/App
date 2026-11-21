/// بيانات التقارير كما تعيدها report_dashboard — قراءة مرنة لأن بعض الأقسام اختيارية.
class ReportData {
  ReportData(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> _m(String k) => raw[k] is Map ? Map<String, dynamic>.from(raw[k] as Map) : const {};
  List<Map<String, dynamic>> _l(Object? v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

  Map<String, dynamic> get kpi => _m('kpi');
  Map<String, dynamic> get alerts => _m('alerts');
  Map<String, dynamic> get byStatus => _m('by_status');
  Map<String, dynamic> get meetings => _m('meetings');
  Map<String, dynamic> get decisionTasks => _m('decision_tasks');
  Map<String, dynamic> get promises => _m('promises');
  Map<String, dynamic> get goals => _m('goals');
  Map<String, dynamic>? get finance => raw['finance'] is Map ? Map<String, dynamic>.from(raw['finance'] as Map) : null;
  Map<String, dynamic>? get clients => raw['clients'] is Map ? Map<String, dynamic>.from(raw['clients'] as Map) : null;
  bool get canFinance => raw['can_finance'] == true;

  List<Map<String, dynamic>> get weekly => _l(raw['weekly']);
  List<Map<String, dynamic>> get services => _l(raw['services']);
  List<Map<String, dynamic>> get stuck => _l(raw['stuck']);
  List<Map<String, dynamic>> get team => _l(raw['team']);
  List<Map<String, dynamic>> listOf(Map<String, dynamic>? m, String k) => _l(m?[k]);

  static num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  static num? nn(Object? v) => v == null ? null : (v is num ? v : num.tryParse('$v'));
}

/// صف في القائمة التفصيلية (report_list)
class ReportRow {
  ReportRow(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get kind => '${m['kind'] ?? ''}';
  String get title => '${m['title'] ?? ''}';
  String get subtitle => '${m['subtitle'] ?? ''}';
  String get badge => '${m['badge'] ?? ''}';
  String get tone => '${m['tone'] ?? 'neutral'}';
  num get amount => ReportData.n(m['amount']);
  String? get date => m['date'] as String?;
  String? get client => m['client'] as String?;
  String? get assignee => m['assignee'] as String?;
}

/// المقاييس التي يمكن وضع أهداف لها
class GoalMetric {
  const GoalMetric(this.key, this.labelAr, {this.percent = false, this.money = false});
  final String key;
  final String labelAr;
  final bool percent;
  final bool money;

  static const all = [
    GoalMetric('requests_closed', 'طلبات منجزة'),
    GoalMetric('collected', 'التحصيل', money: true),
    GoalMetric('on_time', 'الالتزام بالمواعيد', percent: true),
    GoalMetric('new_clients', 'عملاء جدد'),
    GoalMetric('tasks_done', 'مهام منجزة'),
    GoalMetric('meetings_held', 'اجتماعات منعقدة'),
  ];
}

// =====================================================================
// منشئ التقارير
// =====================================================================
const _keep = Object();

/// إعدادات تقرير مخصص. الفترة نسبية (آخر ٣٠ يومًا…) حتى يبقى التقرير المحفوظ محدّثًا.
class CustomConfig {
  const CustomConfig({
    this.source = 'requests',
    this.groupBy = 'status',
    this.metric = 'count',
    this.view = 'bar',
    this.dateBasis = 'created',
    this.period = '30',
    this.from,
    this.to,
    this.status = const [],
    this.priority = const [],
    this.person,
    this.client,
    this.service,
  });

  final String source;
  final String groupBy;
  final String metric;
  final String view; // number | table | bar | line | donut
  final String dateBasis; // created | closed | due
  final String period; // 7 | 30 | 90 | 365 | month | year | custom
  final DateTime? from;
  final DateTime? to;
  final List<String> status;
  final List<String> priority;
  final String? person;
  final String? client;
  final String? service;

  (DateTime, DateTime) get range {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (period) {
      case 'month':
        return (DateTime(today.year, today.month), today);
      case 'year':
        return (DateTime(today.year), today);
      case 'custom':
        return (from ?? today.subtract(const Duration(days: 29)), to ?? today);
      default:
        final days = int.tryParse(period) ?? 30;
        return (today.subtract(Duration(days: days - 1)), today);
    }
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ما يُرسل إلى report_custom
  Map<String, dynamic> toQuery() {
    final (f, t) = range;
    return {
      'source': source,
      'group_by': groupBy,
      'metric': metric,
      'date_basis': dateBasis,
      'from': _d(f),
      'to': _d(t),
      'limit': 50,
      'filters': {
        if (status.isNotEmpty) 'status': status,
        if (priority.isNotEmpty) 'priority': priority,
        if (person != null) 'person': person,
        if (client != null) 'client': client,
        if (service != null && service!.isNotEmpty) 'service': service,
      },
    };
  }

  /// مفتاح ثابت للمزوّد
  String get key => jsonEncodeSorted(toQuery());

  /// ما يُحفظ في saved_reports
  Map<String, dynamic> toJson() => {
        'source': source,
        'group_by': groupBy,
        'metric': metric,
        'view': view,
        'date_basis': dateBasis,
        'period': period,
        if (from != null) 'from': _d(from!),
        if (to != null) 'to': _d(to!),
        'status': status,
        'priority': priority,
        if (person != null) 'person': person,
        if (client != null) 'client': client,
        if (service != null) 'service': service,
      };

  factory CustomConfig.fromJson(Map<String, dynamic> m) => CustomConfig(
        source: (m['source'] ?? 'requests') as String,
        groupBy: (m['group_by'] ?? 'status') as String,
        metric: (m['metric'] ?? 'count') as String,
        view: (m['view'] ?? 'bar') as String,
        dateBasis: (m['date_basis'] ?? 'created') as String,
        period: (m['period'] ?? '30') as String,
        from: DateTime.tryParse('${m['from'] ?? ''}'),
        to: DateTime.tryParse('${m['to'] ?? ''}'),
        status: [for (final s in (m['status'] as List? ?? const [])) '$s'],
        priority: [for (final s in (m['priority'] as List? ?? const [])) '$s'],
        person: m['person'] as String?,
        client: m['client'] as String?,
        service: m['service'] as String?,
      );

  CustomConfig copyWith({
    String? source,
    String? groupBy,
    String? metric,
    String? view,
    String? dateBasis,
    String? period,
    Object? from = _keep,
    Object? to = _keep,
    List<String>? status,
    List<String>? priority,
    Object? person = _keep,
    Object? client = _keep,
    Object? service = _keep,
  }) =>
      CustomConfig(
        source: source ?? this.source,
        groupBy: groupBy ?? this.groupBy,
        metric: metric ?? this.metric,
        view: view ?? this.view,
        dateBasis: dateBasis ?? this.dateBasis,
        period: period ?? this.period,
        from: identical(from, _keep) ? this.from : from as DateTime?,
        to: identical(to, _keep) ? this.to : to as DateTime?,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        person: identical(person, _keep) ? this.person : person as String?,
        client: identical(client, _keep) ? this.client : client as String?,
        service: identical(service, _keep) ? this.service : service as String?,
      );
}

/// ترميز JSON بمفاتيح مرتّبة (حتى يكون مفتاح المزوّد ثابتًا)
String jsonEncodeSorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '${_q(k)}:${jsonEncodeSorted(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(jsonEncodeSorted).join(',')}]';
  if (v is String) return _q(v);
  return '$v';
}

String _q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

/// نتيجة report_custom
class CustomResult {
  CustomResult(this.raw);
  final Map<String, dynamic> raw;

  List<CustomRow> get rows => [
        for (final r in (raw['rows'] as List? ?? const []))
          if (r is Map) CustomRow('${r['key']}', '${r['label']}', ReportData.nn(r['value']), ReportData.n(r['count']).toInt()),
      ];
  num? get totalValue => raw['total'] is Map ? ReportData.nn((raw['total'] as Map)['value']) : null;
  int get totalCount => raw['total'] is Map ? ReportData.n((raw['total'] as Map)['count']).toInt() : 0;
}

class CustomRow {
  const CustomRow(this.key, this.label, this.value, this.count);
  final String key;
  final String label;
  final num? value;
  final int count;
}

/// تقرير محفوظ
class SavedReport {
  SavedReport({
    required this.id,
    required this.name,
    required this.config,
    required this.ownerId,
    this.shared = false,
    this.pinned = false,
    this.onTv = false,
  });
  final String id;
  final String name;
  final CustomConfig config;
  final String ownerId;
  final bool shared;
  final bool pinned;
  final bool onTv;

  factory SavedReport.fromMap(Map<String, dynamic> m) => SavedReport(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        config: CustomConfig.fromJson(Map<String, dynamic>.from((m['config'] ?? const {}) as Map)),
        ownerId: m['owner_id'] as String,
        shared: m['shared'] == true,
        pinned: m['pinned'] == true,
        onTv: m['on_tv'] == true,
      );
}
