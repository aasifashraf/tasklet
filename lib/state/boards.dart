import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/filters.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import '../core/sorting.dart';
import '../core/today_rules.dart';
import 'clock.dart';
import 'prefs.dart';
import 'workspace.dart';

/// Which board a page shows (SPEC §4.2–4.4, §4.7).
@immutable
sealed class BoardKind {
  const BoardKind();

  /// Key for per-board prefs and session state.
  String get id;

  /// Whether tasks from several projects appear (enables the Project filter and column).
  bool get crossProject => true;
}

final class AllTasksBoard extends BoardKind {
  const AllTasksBoard();
  @override
  String get id => 'all';
  @override
  bool operator ==(Object other) => other is AllTasksBoard;
  @override
  int get hashCode => id.hashCode;
}

final class TodayBoard extends BoardKind {
  const TodayBoard();
  @override
  String get id => 'today';
  @override
  bool operator ==(Object other) => other is TodayBoard;
  @override
  int get hashCode => id.hashCode;
}

final class ProjectBoard extends BoardKind {
  const ProjectBoard(this.projectId);
  final String projectId;
  @override
  String get id => 'project:$projectId';
  @override
  bool get crossProject => false;
  @override
  bool operator ==(Object other) =>
      other is ProjectBoard && other.projectId == projectId;
  @override
  int get hashCode => id.hashCode;
}

final class ViewBoard extends BoardKind {
  const ViewBoard(this.viewId);
  final String viewId;
  @override
  String get id => 'view:$viewId';
  @override
  bool operator ==(Object other) =>
      other is ViewBoard && other.viewId == viewId;
  @override
  int get hashCode => id.hashCode;
}

/// Default display options per board (SPEC §5.3): Today has its own; single-project boards never show Project.
ViewDisplay defaultDisplay(BoardKind kind) => switch (kind) {
  TodayBoard() => ViewDisplay.todayDefaults,
  ProjectBoard() => ViewDisplay(
    properties: {...DisplayProperty.values}..remove(DisplayProperty.project),
  ),
  _ => ViewDisplay(),
};

/// Session-only filters per board (reset on relaunch). Saved views keep theirs in the view instead.
class SessionFilters extends Notifier<Map<String, BoardFilters>> {
  @override
  Map<String, BoardFilters> build() => {};
  void set(String boardId, BoardFilters f) => state = {...state, boardId: f};
}

final sessionFiltersProvider =
    NotifierProvider<SessionFilters, Map<String, BoardFilters>>(
      SessionFilters.new,
    );

/// Session-only search text per board; never saved, not even in views (SPEC §6). null = search field closed.
class SessionSearch extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() => {};
  void set(String boardId, String? text) => state = {...state, boardId: text};
}

final sessionSearchProvider =
    NotifierProvider<SessionSearch, Map<String, String?>>(SessionSearch.new);

/// Everything a board page renders.
class BoardData {
  const BoardData({
    required this.kind,
    required this.display,
    required this.filters,
    required this.search,
    required this.groups,
    required this.totalInScope,
    required this.availableLabels,
    required this.project,
    required this.view,
  });

  final BoardKind kind;
  final ViewDisplay display;

  /// Effective filters (stale values already pruned).
  final BoardFilters filters;
  final String search;

  /// Matching tasks by status, sorted.
  final Map<TaskStatus, List<ProjectTask>> groups;

  /// Tasks on the board before filters/search (decides "No tasks yet" vs "No matching tasks").
  final int totalInScope;

  /// Labels offered by the filter menu: (label, owning project or null for workspace).
  final List<(Label, Project?)> availableLabels;
  final Project? project;
  final SavedView? view;

  int get matchCount => groups.values.fold(0, (n, g) => n + g.length);
  bool get filtersActive => !filters.isEmpty;
}

/// Tasks in scope for [kind], before filters/search.
Iterable<ProjectTask> scopeTasks(
  Workspace ws,
  BoardKind kind,
  LocalDate today,
  Set<TodayRule> rules,
) {
  switch (kind) {
    case AllTasksBoard() || ViewBoard():
      return ws.activeTasks;
    case TodayBoard():
      return ws.activeTasks.where((e) => matchesToday(e.task, rules, today));
    case ProjectBoard(:final projectId):
      final p = ws.projectById(projectId);
      return p == null
          ? const []
          : [for (final t in p.tasks) ProjectTask(p, t)];
  }
}

/// Labels usable on [kind]: a project's own + workspace; cross-project boards get every active project's labels.
List<(Label, Project?)> boardLabels(Workspace ws, BoardKind kind) {
  if (kind case ProjectBoard(:final projectId)) {
    final p = ws.projectById(projectId);
    return [
      if (p != null)
        for (final l in p.labels) (l, p),
      for (final l in ws.labels) (l, null),
    ];
  }
  return [
    for (final p in ws.projects.where((p) => !p.archived))
      for (final l in p.labels) (l, p),
    for (final l in ws.labels) (l, null),
  ];
}

final boardProvider = Provider.family<BoardData?, BoardKind>((ref, kind) {
  final ws = ref.watch(workspaceDataProvider);
  if (ws == null) return null;
  final today = ref.watch(todayProvider);
  final prefs = ref.watch(prefsProvider);
  final view = kind is ViewBoard
      ? ws.views.where((v) => v.id == kind.viewId).firstOrNull
      : null;
  final project = kind is ProjectBoard ? ws.projectById(kind.projectId) : null;

  final display = kind is ViewBoard
      ? (view?.display ?? defaultDisplay(kind))
      : (prefs.boardDisplay(kind.id) ?? defaultDisplay(kind));
  final rawFilters = kind is ViewBoard
      ? (view?.filters ?? BoardFilters.empty)
      : (ref.watch(sessionFiltersProvider)[kind.id] ?? BoardFilters.empty);
  final search = ref.watch(sessionSearchProvider)[kind.id] ?? '';

  final labels = boardLabels(ws, kind);
  final filters = pruneStaleFilters(
    kind.crossProject ? rawFilters : rawFilters.copyWith(projects: const {}),
    {noProjectId, for (final p in ws.projects.where((p) => !p.archived)) p.id},
    {noLabelFilterId, for (final (l, _) in labels) l.id},
  );

  final scope = scopeTasks(ws, kind, today, prefs.todayRules).toList();
  final query = SearchQuery(search);
  final matching = scope.where(
    (e) => matchesFilters(e, filters, today) && query.matches(e),
  );
  return BoardData(
    kind: kind,
    display: display,
    filters: filters,
    search: search,
    groups: groupAndSort(matching, display),
    totalInScope: scope.length,
    availableLabels: labels,
    project: project,
    view: view,
  );
});

/// Writes display/filter changes to the right place: the view for saved views, device prefs/session otherwise.
class BoardActions {
  BoardActions(this.ref, this.kind);
  final WidgetRef ref;
  final BoardKind kind;

  void setDisplay(ViewDisplay display) {
    if (kind case ViewBoard(:final viewId)) {
      ref
          .read(workspaceProvider.notifier)
          .updateView(viewId, (v) => v.copyWith(display: display));
    } else {
      ref
          .read(prefsProvider.notifier)
          .set(PrefKeys.boardDisplay(kind.id), display.toJson());
    }
  }

  void resetDisplay() {
    if (kind case ViewBoard(:final viewId)) {
      ref
          .read(workspaceProvider.notifier)
          .updateView(viewId, (v) => v.copyWith(display: null));
    } else {
      ref
          .read(prefsProvider.notifier)
          .set(PrefKeys.boardDisplay(kind.id), null);
    }
  }

  void setFilters(BoardFilters filters) {
    if (kind case ViewBoard(:final viewId)) {
      ref
          .read(workspaceProvider.notifier)
          .updateView(viewId, (v) => v.copyWith(filters: filters));
    } else {
      ref.read(sessionFiltersProvider.notifier).set(kind.id, filters);
    }
  }

  void setSearch(String? text) =>
      ref.read(sessionSearchProvider.notifier).set(kind.id, text);

  void toggleCollapsed(TaskStatus status) {
    final prefs = ref.read(prefsProvider);
    final collapsed = {...prefs.collapsedGroups(kind.id)};
    if (!collapsed.remove(status)) collapsed.add(status);
    ref.read(prefsProvider.notifier).set(PrefKeys.collapsedGroups(kind.id), [
      for (final s in collapsed) s.json,
    ]);
  }
}
