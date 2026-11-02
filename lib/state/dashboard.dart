import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dashboard.dart';
import '../core/models.dart';
import 'clock.dart';
import 'prefs.dart';
import 'workspace.dart';

/// Everything the Dashboard shows (SPEC §4.1), computed once per workspace snapshot, day and project filter.
class DashboardData {
  const DashboardData({
    required this.activeProjects,
    required this.project,
    required this.isEmpty,
    required this.glance,
    required this.upNext,
    required this.recent,
    required this.statusCounts,
  });

  /// Non-archived projects in sidebar order, for the filter menu.
  final List<Project> activeProjects;

  /// The project the Dashboard is filtered to, or null for all projects.
  final Project? project;
  final bool isEmpty;
  final Glance glance;
  final List<ProjectTask> upNext;
  final List<ProjectTask> recent;
  final Map<TaskStatus, int> statusCounts;
}

/// Recomputes only when the workspace, the day or the filter changes; not on the clock's 30-second tick
/// (docs/SYSTEM_DESIGN.md, P1).
final dashboardProvider = Provider<DashboardData?>((ref) {
  final ws = ref.watch(workspaceDataProvider);
  if (ws == null) return null;
  final today = ref.watch(todayProvider);
  final storedFilter = ref.watch(
    prefsProvider.select((p) => p.dashboardProject),
  );
  final activeProjects = ws.projects.where((p) => !p.archived).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final project = activeProjects.where((p) => p.id == storedFilter).firstOrNull;
  final tasks = project == null
      ? ws.activeTasks.toList()
      : [for (final task in project.tasks) ProjectTask(project, task)];
  // "Done this week" only depends on the day, so local midnight stands in for the current time.
  final dayStart = today.toLocalDateTime();
  return DashboardData(
    activeProjects: activeProjects,
    project: project,
    isEmpty: tasks.isEmpty,
    glance: glanceFor(tasks, today, dayStart),
    upNext: upNext(tasks, today),
    recent: recentlyCompleted(tasks, dayStart),
    statusCounts: statusCounts(tasks),
  );
});
