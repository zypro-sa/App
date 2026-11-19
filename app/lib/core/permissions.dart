import '../data/models.dart' show UserRole;

/// صلاحية واحدة قابلة للتشغيل أو الإيقاف لكل عضو.
class Permission {
  const Permission(this.key, this.label, this.description, this.group);
  final String key;
  final String label;
  final String description;
  final String group;
}

/// قائمة الصلاحيات — تطابق role_default_perm و has_perm في قاعدة البيانات.
class Permissions {
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

  static const all = <Permission>[
    Permission(requestsViewAll, 'رؤية كل الطلبات', 'بدونها يرى الطلبات المسندة إليه فقط', 'الطلبات والمهام'),
    Permission(requestsManage, 'إضافة الطلبات وتعديلها', 'إنشاء طلبات جديدة وتغيير حالتها', 'الطلبات والمهام'),
    Permission(tasksViewAll, 'رؤية كل المهام', 'بدونها يرى مهامه وما أسنده فقط', 'الطلبات والمهام'),
    Permission(tasksAssign, 'إسناد المهام للآخرين', 'إنشاء مهام لأعضاء الفريق وتعديلها', 'الطلبات والمهام'),
    Permission(clientsManage, 'إضافة العملاء وتعديلهم', 'بدونها يرى العملاء فقط', 'العملاء والمشاريع'),
    Permission(projectsManage, 'إدارة كل المشاريع', 'بدونها يرى المشاريع التي يديرها فقط', 'العملاء والمشاريع'),
    Permission(meetingsManage, 'إنشاء الاجتماعات وإدارتها', 'بدونها يرى الاجتماعات التي يحضرها فقط', 'العملاء والمشاريع'),
    Permission(reportsView, 'التقارير', 'رؤية تقارير الأداء وسجل النشاط', 'المتابعة'),
    Permission(teamView, 'رؤية الفريق ومتابعاتهم', 'قائمة الأعضاء وأعباؤهم ومتابعاتهم', 'المتابعة'),
    Permission(financeManage, 'المالية', 'الفواتير والدفعات وعروض الأسعار', 'الإدارة'),
    Permission(settingsLists, 'تعديل خيارات القوائم', 'مثل أنواع الخدمات والقطاعات', 'الإدارة'),
    Permission(settingsFields, 'تعديل الحقول والحالات', 'إضافة الحقول وإخفاؤها وأسماء الحالات', 'الإدارة'),
    Permission(dataDelete, 'حذف البيانات واسترجاعها', 'نقل العناصر للسلة واسترجاعها', 'الإدارة'),
  ];

  static const _managerDefaults = {
    requestsViewAll, requestsManage, tasksViewAll, tasksAssign, clientsManage,
    projectsManage, meetingsManage, reportsView, teamView, settingsLists, dataDelete,
  };

  static bool roleDefault(UserRole role, String key) => switch (role) {
        UserRole.owner => true,
        UserRole.manager => _managerDefaults.contains(key),
        UserRole.employee => false,
      };

  /// الصلاحية الفعلية: المالك دائمًا، وإلا التخصيص ثم الافتراضي حسب الدور.
  static bool effective(UserRole role, Map<String, dynamic> overrides, String key) {
    if (role == UserRole.owner) return true;
    final v = overrides[key];
    return v is bool ? v : roleDefault(role, key);
  }
}
