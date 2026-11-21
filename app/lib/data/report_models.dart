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
