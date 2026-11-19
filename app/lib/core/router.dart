import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/clients/client_screen.dart';
import '../features/clients/clients_screen.dart';
import '../features/followups/followups_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meetings/meetings_screen.dart';
import '../features/more/more_screen.dart';
import '../features/quick_add/quick_add_sheet.dart';
import '../features/requests/requests_screen.dart';
import '../features/tasks/tasks_screen.dart';

/// يعيد توجيه المستخدم عند تسجيل الدخول أو الخروج.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
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
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final atLogin = state.matchedLocation == '/login';
    if (!loggedIn && !atLogin) return '/login';
    if (loggedIn && atLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/requests', builder: (_, __) => const RequestsScreen()),
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
            ],
          ),
        ]),
      ],
    ),
  ],
);

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
        tooltip: 'إضافة سريعة',
        onPressed: () => showQuickAdd(context, initial: _quickAddDefaults[shell.currentIndex]),
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'اليوم'),
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'الطلبات'),
          NavigationDestination(icon: Icon(Icons.check_box_outlined), selectedIcon: Icon(Icons.check_box), label: 'المهام'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'الاجتماعات'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'المزيد'),
        ],
      ),
    );
  }
}
