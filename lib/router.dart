import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'ui/pages/board_pages.dart';
import 'ui/pages/dashboard_page.dart';
import 'ui/pages/labels_page.dart';
import 'ui/pages/projects_page.dart';
import 'ui/pages/reports_page.dart';
import 'ui/pages/today_page.dart';
import 'ui/pages/views_page.dart';
import 'ui/shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

NoTransitionPage<void> _page(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, child: child);

/// Routes from SPEC §15. Also used by notification clicks and menu commands.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      builder: (context, state, child) => WorkspaceGate(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (c, s) => _page(s, const DashboardPage()),
        ),
        GoRoute(
          path: '/today',
          pageBuilder: (c, s) => _page(s, const TodayPage()),
        ),
        GoRoute(
          path: '/my-tasks',
          pageBuilder: (c, s) => _page(s, const AllTasksPage()),
        ),
        GoRoute(
          path: '/projects',
          pageBuilder: (c, s) => _page(s, const ProjectsPage()),
        ),
        GoRoute(
          path: '/projects/:id',
          pageBuilder: (c, s) =>
              _page(s, ProjectBoardPage(projectId: s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/views',
          pageBuilder: (c, s) => _page(s, const ViewsPage()),
        ),
        GoRoute(
          path: '/views/:id',
          pageBuilder: (c, s) =>
              _page(s, ViewBoardPage(viewId: s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/labels',
          pageBuilder: (c, s) => _page(s, const LabelsPage()),
        ),
        GoRoute(
          path: '/reports',
          pageBuilder: (c, s) => _page(s, const ReportsPage()),
        ),
      ],
    ),
  ],
);
