import '../data/models.dart' show UserRole;
import 'i18n.dart';

/// صلاحية واحدة داخل قسم (مثل: إضافة، إسناد مهام، حذف).
class PermItem {
  const PermItem(this.action, this.labelAr, this.noteAr);
  final String action; // view | add | edit | delete
  final String labelAr;
  final String noteAr;
  String get label => tr(labelAr);
  String get note => tr(noteAr);
}

/// قسم من أقسام التطبيق وصلاحياته.
/// [scopeAllAr]/[scopeOwnAr]: إن وُجدا فللقسم نطاق عرض (الكل / المكلّف به فقط / لا شيء).
class PermModule {
  const PermModule(
    this.key,
    this.labelAr, {
    this.items = const [],
    this.scopeAllAr,
    this.scopeOwnAr,
    this.noteAr,
    this.groupAr = 'العمل اليومي',
  });
  final String key;
  final String labelAr;
  final List<PermItem> items;
  final String? scopeAllAr;
  final String? scopeOwnAr;
  final String? noteAr;
  final String groupAr;

  String get label => tr(labelAr);
  String get group => tr(groupAr);
  String? get note => noteAr == null ? null : tr(noteAr!);
  bool get scoped => scopeAllAr != null;
  String keyOf(String action) => '$key.$action';
  String get viewAllKey => '$key.view';
  String get viewOwnKey => '$key.view_own';

  /// كل مفاتيح القسم (للعدّ وإعادة الافتراضي)
  List<String> get allKeys => [
        if (scoped) ...[viewAllKey, viewOwnKey],
        for (final i in items) keyOf(i.action),
      ];
}

/// قائمة الصلاحيات — تطابق role_default_perm و has_perm في قاعدة البيانات.
class Permissions {
  // ---- المفاتيح الجديدة ----

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

  static const teamAdd = 'team.add';
  static const teamEdit = 'team.edit';
  static const teamDelete = 'team.delete';
  static const settingsListsView = 'settings_lists.view';
  static const settingsListsAdd = 'settings_lists.add';
  static const settingsListsEdit = 'settings_lists.edit';
  static const settingsListsDelete = 'settings_lists.delete';
  static const settingsFieldsView = 'settings_fields.view';
  static const settingsFieldsAdd = 'settings_fields.add';
  static const settingsFieldsEdit = 'settings_fields.edit';
  static const settingsFieldsDelete = 'settings_fields.delete';
  static const statusesView = 'statuses.view';
  static const statusesEdit = 'statuses.edit';

  static const modules = <PermModule>[
    PermModule('requests', 'الطلبات',
        scopeAllAr: 'كل الطلبات',
        scopeOwnAr: 'المسندة إليه وما أنشأه',
        items: [
          PermItem('add', 'إضافة', 'إنشاء طلبات جديدة'),
          PermItem('edit', 'تعديل', 'تعديل أي طلب (المسؤول عن الطلب يحدّثه دائمًا)'),
          PermItem('delete', 'حذف', 'نقل الطلبات للسلة واسترجاعها'),
        ]),
    PermModule('tasks', 'المهام',
        scopeAllAr: 'كل المهام',
        scopeOwnAr: 'المسندة إليه فقط',
        noteAr: 'إضافة مهام لنفسه متاحة دائمًا',
        items: [
          PermItem('add', 'إسناد مهام', 'إنشاء مهام لأعضاء آخرين'),
          PermItem('edit', 'تعديل', 'تعديل مهام الآخرين'),
          PermItem('delete', 'حذف', 'حذف مهام الآخرين (ما أنشأه بنفسه يحذفه دائمًا)'),
        ]),
    PermModule('meetings', 'الاجتماعات',
        scopeAllAr: 'كل الاجتماعات',
        scopeOwnAr: 'المكلّف بها فقط',
        items: [
          PermItem('add', 'إضافة', 'إنشاء اجتماعات'),
          PermItem('edit', 'تعديل', 'تعديل الاجتماعات والمحاضر'),
          PermItem('delete', 'حذف', 'حذف الاجتماعات'),
        ]),
    PermModule('projects', 'المشاريع',
        scopeAllAr: 'كل المشاريع',
        scopeOwnAr: 'التي يديرها فقط',
        items: [
          PermItem('add', 'إضافة', 'إنشاء مشاريع'),
          PermItem('edit', 'تعديل', 'تعديل المشاريع والمراحل'),
          PermItem('delete', 'حذف', 'حذف المشاريع'),
        ]),
    PermModule('clients', 'العملاء', items: [
      PermItem('view', 'عرض', 'رؤية العملاء وملفاتهم'),
      PermItem('add', 'إضافة', 'إضافة عملاء وجهات اتصال'),
      PermItem('edit', 'تعديل', 'تعديل بيانات العملاء وجهات الاتصال'),
      PermItem('delete', 'حذف', 'حذف العملاء'),
    ]),
    PermModule('followups', 'المتابعات', noteAr: 'متابعاته الشخصية يضيفها ويعدّلها ويحذفها دائمًا', items: [
      PermItem('view', 'عرض متابعات الفريق', 'رؤية متابعات بقية الأعضاء'),
      PermItem('add', 'إضافة للآخرين', 'إنشاء متابعات لأعضاء آخرين'),
      PermItem('edit', 'تعديل', 'تعديل متابعات الآخرين'),
      PermItem('delete', 'حذف', 'حذف متابعات الآخرين'),
    ]),
    PermModule('finance', 'المالية', groupAr: 'الإدارة', items: [
      PermItem('view', 'عرض', 'الفواتير والدفعات وعروض الأسعار'),
      PermItem('add', 'إضافة', 'فواتير ودفعات وعروض ومرتجعات'),
      PermItem('edit', 'تعديل', 'تعديلها ومزامنة دفترة'),
      PermItem('delete', 'حذف', 'حذفها وإلغاء الفواتير'),
    ]),
    PermModule('reports', 'التقارير', groupAr: 'الإدارة',
        noteAr: 'التقارير تُحسب تلقائيًا من البيانات، فليس فيها ما يُضاف أو يُحذف',
        items: [PermItem('view', 'عرض', 'تقارير الأداء وسجل النشاط')]),
    PermModule('team', 'الفريق', groupAr: 'الإدارة',
        noteAr: 'لا أحد غير المالك يعدّل حسابه أو حساب المالك',
        items: [
          PermItem('view', 'عرض', 'قائمة الأعضاء وأعباؤهم'),
          PermItem('add', 'دعوة أعضاء', 'إضافة أعضاء جدد'),
          PermItem('edit', 'تعديل', 'بيانات الأعضاء وأدوارهم وصلاحياتهم وكلمات المرور'),
          PermItem('delete', 'إيقاف وحذف', 'إيقاف الحسابات وحذفها نهائيًا'),
        ]),
    PermModule('settings_lists', 'خيارات القوائم', groupAr: 'لوحة التحكم', noteAr: 'مثل أنواع الخدمات والقطاعات', items: [
      PermItem('view', 'عرض', 'فتح القوائم في لوحة التحكم'),
      PermItem('add', 'إضافة', 'إضافة خيارات جديدة'),
      PermItem('edit', 'تعديل', 'إعادة تسمية الخيارات وترتيبها'),
      PermItem('delete', 'حذف', 'حذف الخيارات'),
    ]),
    PermModule('settings_fields', 'الحقول', groupAr: 'لوحة التحكم', noteAr: 'حقول نماذج الإضافة والبطاقات', items: [
      PermItem('view', 'عرض', 'فتح الحقول في لوحة التحكم'),
      PermItem('add', 'إضافة', 'إضافة حقول مخصصة'),
      PermItem('edit', 'تعديل', 'تسمية الحقول وإظهارها وجعلها إلزامية'),
      PermItem('delete', 'حذف', 'حذف الحقول المخصصة'),
    ]),
    PermModule('statuses', 'الحالات', groupAr: 'لوحة التحكم',
        noteAr: 'الحالات ثابتة لأن التنبيهات تعتمد عليها؛ يتغير اسمها ولونها فقط',
        items: [
          PermItem('view', 'عرض', 'رؤية الحالات في لوحة التحكم'),
          PermItem('edit', 'تعديل', 'تغيير أسماء الحالات وألوانها'),
        ]),
  ];

  static const _allRoles = {'requests.view_own', 'tasks.view_own', 'meetings.view_own', 'projects.view_own', 'clients.view'};
  static const _managerDefaults = {
    'requests.view', 'requests.add', 'requests.edit', 'requests.delete',
    'tasks.view', 'tasks.add', 'tasks.edit', 'tasks.delete',
    'meetings.view', 'meetings.add', 'meetings.edit', 'meetings.delete',
    'clients.add', 'clients.edit', 'clients.delete',
    'projects.view', 'projects.add', 'projects.edit', 'projects.delete',
    'followups.view', 'followups.add', 'followups.edit', 'followups.delete',
    'reports.view', 'team.view',
    'settings_lists.view', 'settings_lists.add', 'settings_lists.edit', 'settings_lists.delete',
    'statuses.view', 'settings_fields.view',
  };

  static bool roleDefault(UserRole role, String key) => switch (role) {
        UserRole.owner => true,
        _ when _allRoles.contains(key) => true,
        UserRole.manager => _managerDefaults.contains(key),
        UserRole.employee => false,
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
      settingsLists => r(settingsListsAdd) || r(settingsListsEdit) || r(settingsListsDelete),
      settingsFields => r(settingsFieldsAdd) || r(settingsFieldsEdit) || r(settingsFieldsDelete) || r(statusesEdit),
      dataDelete => r(requestsDelete) || r(tasksDelete) || r(meetingsDelete) ||
          r(clientsDelete) || r(projectsDelete) || r(financeDelete),
      _ => r(key),
    };
  }
}
