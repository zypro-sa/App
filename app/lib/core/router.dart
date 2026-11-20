import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/section_models.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/notifications/notification_settings_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/projects/project_detail_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/bulk_manage_screen.dart';
import '../features/settings/section_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/trash_screen.dart';
import '../features/team/team_screen.dart';
import '../features/clients/client_screen.dart';
import '../features/clients/clients_screen.dart';
import '../features/followups/followups_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meetings/meetings_screen.dart';
import '../features/more/more_screen.dart';
import '../features/quick_add/quick_add_sheet.dart';
import '../features/requests/request_detail_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/tasks/tasks_screen.dart';
import 'i18n.dart';

/// يصبح true عند فتح رابط استعادة كلمة المرور.
final passwordRecovery = ValueNotifier<bool>(false);

bool _needsPassword() {
  final user = Supabase.instance.client.auth.currentUser;
  return passwordRecovery.value || user?.userMetadata?['needs_password'] == true;
}

/// يعيد توجيه المستخدم عند تسجيل الدخول أو الخروج.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) passwordRecovery.value = true;
      notifyListeners();
    });
    passwordRecovery.addListener(notifyListeners);
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final appRouter = GoRouter(
  initialLocation: '/home',
  refreshListenable: _AuthRefresh(),
  errorBuilder: (_, __) => const _Redirecting(),
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loc = state.matchedLocation;
    // روابط الدعوة والاستعادة تصل بمعاملات في العنوان
    final authCallback = state.uri.toString().contains('access_token') || loc.isEmpty;
    if (!loggedIn) return loc == '/login' ? null : '/login';
    if (_needsPassword()) return loc == '/set-password' ? null : '/set-password';
    if (loc == '/login' || loc == '/set-password' || authCallback) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomeScreen(),
            routes: [
              GoRoute(path: 'notifications', builder: (_, __) => const NotificationsScreen()),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/requests',
            builder: (_, __) => const RequestsScreen(),
            routes: [
              GoRoute(path: ':id', builder: (_, s) => RequestDetailScreen(requestId: s.pathParameters['id']!)),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/meetings', builder: (_, __) => const MeetingsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/more',
            builder: (_, __) => const MoreScreen(),
            routes: [
              GoRoute(path: 'clients', builder: (_, __) => const ClientsScreen()),
              GoRoute(
                path: 'clients/:id',
                builder: (_, s) => ClientScreen(clientId: s.pathParameters['id']!),
              ),
              GoRoute(path: 'followups', builder: (_, __) => const FollowupsScreen()),
              GoRoute(
                path: 'projects',
                builder: (_, __) => const ProjectsScreen(),
                routes: [
                  GoRoute(path: ':id', builder: (_, s) => ProjectDetailScreen(projectId: s.pathParameters['id']!)),
                ],
              ),
              GoRoute(path: 'finance', builder: (_, __) => const FinanceScreen()),
              GoRoute(path: 'notifications', builder: (_, __) => const NotificationSettingsScreen()),
              GoRoute(path: 'notes', builder: (_, __) => const NotesScreen()),
              GoRoute(path: 'reports', builder: (_, __) => const ReportsScreen()),
              GoRoute(
                path: 'team',
                builder: (_, __) => const TeamScreen(),
                routes: [
                  GoRoute(path: ':id', builder: (_, s) => MemberScreen(memberId: s.pathParameters['id']!)),
                ],
              ),
              GoRoute(
                path: 'settings',
                builder: (_, __) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'section/:entity',
                    builder: (_, s) => SectionSettingsScreen(entity: ConfigEntity.from(s.pathParameters['entity'])),
                  ),
                  GoRoute(
                    path: 'data',
                    builder: (_, s) => BulkManageScreen(initialTable: s.uri.queryParameters['table'] ?? 'requests'),
                  ),
                  GoRoute(path: 'trash', builder: (_, __) => const TrashScreen()),
                ],
              ),
            ],
          ),
        ]),
      ],
    ),
  ],
);

class _Redirecting extends StatelessWidget {
  const _Redirecting();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) GoRouter.of(context).go('/home');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// الإطار الثابت: شريط التنقل السفلي وزر الإضافة السريعة.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _quickAddDefaults = [
    QuickAddType.task, // اليوم
    QuickAddType.request, // الطلبات
    QuickAddType.task, // المهام
    QuickAddType.meeting, // الاجتماعات
    QuickAddType.task, // المزيد
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        tooltip: tr('إضافة سريعة'),
        onPressed: () => showQuickAdd(context, initial: _quickAddDefaults[shell.currentIndex]),
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: tr('اليوم')),
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: tr('الطلبات')),
          NavigationDestination(icon: Icon(Icons.check_box_outlined), selectedIcon: Icon(Icons.check_box), label: tr('المهام')),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: tr('الاجتماعات')),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: tr('المزيد')),
        ],
      ),
    );
  }
}
