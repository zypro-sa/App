import '../data/models.dart' show UserRole;
import 'i18n.dart';

/// الإجراءات الأربعة لكل قسم.
enum PermAction {
  view('view', 'عرض'),
  add('add', 'إضافة'),
  edit('edit', 'تعديل'),
  delete('delete', 'حذف');

  const PermAction(this.key, this.labelAr);
  final String key;
  final String labelAr;
  String get label => tr(labelAr);
}

/// قسم من أقسام التطبيق وما ينطبق عليه من الإجراءات، مع شرح كل إجراء.
class PermModule {
  const PermModule(this.key, this.labelAr, this.notesAr, {this.groupAr = 'العمل اليومي'});
  final String key;
  final String labelAr;
  final String groupAr;

  /// شرح كل إجراء متاح؛ الإجراء غير الموجود هنا لا ينطبق على القسم
  final Map<PermAction, String> notesAr;

  String get label => tr(labelAr);
  String get group => tr(groupAr);
  bool supports(PermAction a) => notesAr.containsKey(a);
  String note(PermAction a) => tr(notesAr[a] ?? '');
  String keyOf(PermAction a) => '$key.${a.key}';
}

/// قائمة الصلاحيات — تطابق role_default_perm و has_perm في قاعدة البيانات.
class Permissions {
  // ---- المفاتيح الجديدة ----
  static String of(String module, PermAction a) => '$module.${a.key}';

  static const requestsView = 'requests.view';
  static const requestsAdd = 'requests.add';
  static const requestsEdit = 'requests.edit';
  static const requestsDelete = 'requests.delete';
  static const tasksView = 'tasks.view';
  static const tasksAdd = 'tasks.add';
  static const tasksEdit = 'tasks.edit';
  static const tasksDelete = 'tasks.delete';
  static const meetingsAdd = 'meetings.add';
  static const meetingsEdit = 'meetings.edit';
  static const meetingsDelete = 'meetings.delete';
  static const clientsAdd = 'clients.add';
  static const clientsEdit = 'clients.edit';
  static const clientsDelete = 'clients.delete';
  static const projectsAdd = 'projects.add';
  static const projectsEdit = 'projects.edit';
  static const projectsDelete = 'projects.delete';
  static const financeView = 'finance.view';
  static const financeAdd = 'finance.add';
  static const financeEdit = 'finance.edit';
  static const financeDelete = 'finance.delete';

  // ---- أسماء قديمة (تُترجم تلقائيًا للجديدة في effective) ----
  static const requestsViewAll = 'requests.view_all';
  static const requestsManage = 'requests.manage';
  static const tasksViewAll = 'tasks.view_all';
  static const tasksAssign = 'tasks.assign';
  static const clientsManage = 'clients.manage';
  static const projectsManage = 'projects.manage';
  static const meetingsManage = 'meetings.manage';
  static const reportsView = 'reports.view';
  static const teamView = 'team.view';
  static const financeManage = 'finance.manage';
  static const settingsLists = 'settings.lists';
  static const settingsFields = 'settings.fields';
  static const dataDelete = 'data.delete';

  static const modules = <PermModule>[
    PermModule('requests', 'الطلبات', {
      PermAction.view: 'كل الطلبات (بدونها: المسندة إليه وما أنشأه)',
      PermAction.add: 'إنشاء طلبات جديدة',
      PermAction.edit: 'تعديل أي طلب (المسؤول عن الطلب يحدّثه دائمًا)',
      PermAction.delete: 'نقل الطلبات للسلة واسترجاعها',
    }),
    PermModule('tasks', 'المهام', {
      PermAction.view: 'كل المهام (بدونها: مهامه وما أسنده)',
      PermAction.add: 'إسناد مهام للآخرين (مهامه لنفسه متاحة دائمًا)',
      PermAction.edit: 'تعديل مهام الآخرين',
      PermAction.delete: 'حذف مهام الآخرين (مهامه التي أنشأها متاحة دائمًا)',
    }),
    PermModule('meetings', 'الاجتماعات', {
      PermAction.view: 'كل الاجتماعات (بدونها: التي يحضرها أو أنشأها)',
      PermAction.add: 'إنشاء اجتماعات',
      PermAction.edit: 'تعديل الاجتماعات والمحاضر',
      PermAction.delete: 'حذف الاجتماعات',
    }),
    PermModule('clients', 'العملاء', {
      PermAction.view: 'رؤية العملاء وملفاتهم',
      PermAction.add: 'إضافة عملاء وجهات اتصال',
      PermAction.edit: 'تعديل بيانات العملاء وجهات الاتصال',
      PermAction.delete: 'حذف العملاء',
    }),
    PermModule('projects', 'المشاريع', {
      PermAction.view: 'كل المشاريع (بدونها: التي يديرها)',
      PermAction.add: 'إنشاء مشاريع',
      PermAction.edit: 'تعديل المشاريع والمراحل',
      PermAction.delete: 'حذف المشاريع',
    }),
    PermModule('followups', 'المتابعات', {
      PermAction.view: 'رؤية متابعات الفريق (متابعاته متاحة دائمًا)',
      PermAction.edit: 'إدارة متابعات الفريق',
    }),
    PermModule('finance', 'المالية', {
      PermAction.view: 'الفواتير والدفعات وعروض الأسعار',
      PermAction.add: 'إضافة فواتير ودفعات وعروض ومرتجعات',
      PermAction.edit: 'تعديلها ومزامنة دفترة',
      PermAction.delete: 'حذفها وإلغاء الفواتير',
    }, groupAr: 'الإدارة'),
    PermModule('reports', 'التقارير', {
      PermAction.view: 'تقارير الأداء وسجل النشاط',
    }, groupAr: 'الإدارة'),
    PermModule('team', 'الفريق', {
      PermAction.view: 'قائمة الأعضاء وأعباؤهم (الإدارة للمالك فقط)',
    }, groupAr: 'الإدارة'),
    PermModule('settings_lists', 'خيارات القوائم', {
      PermAction.edit: 'مثل أنواع الخدمات والقطاعات',
    }, groupAr: 'لوحة التحكم'),
    PermModule('settings_fields', 'الحقول والحالات', {
      PermAction.edit: 'إضافة الحقول وإخفاؤها وأسماء الحالات',
    }, groupAr: 'لوحة التحكم'),
  ];

  static const _managerDefaults = {
    'requests.view', 'requests.add', 'requests.edit', 'requests.delete',
    'tasks.view', 'tasks.add', 'tasks.edit', 'tasks.delete',
    'meetings.view', 'meetings.add', 'meetings.edit', 'meetings.delete',
    'clients.view', 'clients.add', 'clients.edit', 'clients.delete',
    'projects.view', 'projects.add', 'projects.edit', 'projects.delete',
    'followups.view', 'followups.edit',
    'reports.view', 'team.view', 'settings_lists.edit',
  };
  static const _employeeDefaults = {'clients.view'};

  static bool roleDefault(UserRole role, String key) => switch (role) {
        UserRole.owner => true,
        UserRole.manager => _managerDefaults.contains(key),
        UserRole.employee => _employeeDefaults.contains(key),
      };

  static bool _raw(UserRole role, Map<String, dynamic> overrides, String key) {
    if (role == UserRole.owner) return true;
    final v = overrides[key];
    return v is bool ? v : roleDefault(role, key);
  }

  /// الصلاحية الفعلية: المالك دائمًا، وإلا التخصيص ثم الافتراضي حسب الدور.
  /// الأسماء القديمة تُترجم كما في has_perm بقاعدة البيانات.
  static bool effective(UserRole role, Map<String, dynamic> overrides, String key) {
    bool r(String k) => _raw(role, overrides, k);
    return switch (key) {
      requestsViewAll => r(requestsView),
      requestsManage => r(requestsAdd) || r(requestsEdit),
      tasksViewAll => r(tasksView),
      tasksAssign => r(tasksAdd) || r(tasksEdit),
      clientsManage => r(clientsAdd) || r(clientsEdit),
      projectsManage => r(projectsAdd) || r(projectsEdit),
      meetingsManage => r(meetingsAdd) || r(meetingsEdit),
      financeManage => r(financeView),
      settingsLists => r('settings_lists.edit'),
      settingsFields => r('settings_fields.edit'),
      dataDelete => r(requestsDelete) || r(tasksDelete) || r(meetingsDelete) ||
          r(clientsDelete) || r(projectsDelete) || r(financeDelete),
      _ => r(key),
    };
  }
}
