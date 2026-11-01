import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/ordering.dart';
import '../../core/sorting.dart';
import '../../state/boards.dart';
import '../../state/clock.dart';
import '../../state/prefs.dart';
import '../../state/workspace.dart';
import '../board/kanban.dart';
import '../board/task_list.dart';
import '../board/toolbar.dart';
import '../glyphs.dart';
import '../task/new_task_dialog.dart';
import '../theme.dart';
import '../widgets.dart';
import 'page_scaffold.dart';

/// All Tasks (SPEC §4.3).
class AllTasksPage extends StatelessWidget {
  const AllTasksPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const BoardPage(kind: AllTasksBoard(), title: 'All Tasks');
}

/// One project's board (SPEC §4.4).
class ProjectBoardPage extends ConsumerWidget {
  const ProjectBoardPage({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    final project = ws?.projectById(projectId);
    if (ws == null) return const SizedBox.shrink();
    if (project == null || project.isNoProject) {
      return const PageScaffold(
        title: 'Project',
        body: EmptyState(
          icon: Icons.search_off,
          title: 'Project not found',
          message: 'It may have been deleted, or it hasn\'t finished syncing to this computer yet.',
        ),
      );
    }
    return BoardPage(
      kind: ProjectBoard(projectId),
      title: project.name,
      leading: CubeIcon(
        color: Tokens.of(context).named(project.color),
        size: 15,
      ),
    );
  }
}

/// A saved view's board (SPEC §4.7).
class ViewBoardPage extends ConsumerWidget {
  const ViewBoardPage({super.key, required this.viewId});
  final String viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    final view = ws?.views.where((v) => v.id == viewId).firstOrNull;
    if (ws == null) return const SizedBox.shrink();
    if (view == null) {
      return const PageScaffold(
        title: 'View',
        body: EmptyState(
          icon: Icons.search_off,
          title: 'View not found',
          message: 'It may have been deleted, or views.json hasn\'t finished syncing yet.',
        ),
      );
    }
    return BoardPage(
      kind: ViewBoard(viewId),
      title: view.name,
      leading: LayersIcon(
        color: Tokens.of(context).named(view.color),
        size: 15,
      ),
    );
  }
}

/// Header + toolbar + board/list body, shared by every board page.
class BoardPage extends ConsumerWidget {
  const BoardPage({
    super.key,
    required this.kind,
    required this.title,
    this.leading,
  });
  final BoardKind kind;
  final String title;
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(
      workspaceDataProvider.select((w) => w?.readOnly ?? true),
    );
    return PageScaffold(
      title: title,
      leading: leading,
      actions: [
        TextButton.icon(
          onPressed: readOnly
              ? null
              : () => openNewTaskForBoard(context, ref, kind),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('New Task'),
        ),
      ],
      toolbar: BoardToolbar(kind: kind),
      body: BoardBody(kind: kind),
    );
  }
}

class BoardBody extends ConsumerWidget {
  const BoardBody({super.key, required this.kind});
  final BoardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(boardProvider(kind));
    final readOnly = ref.watch(
      workspaceDataProvider.select((w) => w?.readOnly ?? true),
    );
    if (board == null) return const SizedBox.shrink();
    final isToday = kind is TodayBoard;

    if (board.totalInScope == 0) {
      return isToday
          ? const EmptyState(
              icon: Icons.wb_sunny_outlined,
              title: 'Nothing for today',
              message:
                  'Tasks show up here when they are due today, start today, or are overdue. '
                  'Use Filter to choose which of these to include.',
            )
          : EmptyState(
              icon: Icons.checklist_rounded,
              title: 'No tasks yet',
              message: 'Create a task to get started. Press Ctrl+N any time.',
              action: FilledButton.icon(
                onPressed: readOnly
                    ? null
                    : () => openNewTaskForBoard(context, ref, kind),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('New Task'),
              ),
            );
    }
    if (board.matchCount == 0) {
      return EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No matching tasks',
        message: board.search.isNotEmpty
            ? 'No tasks match "${board.search}" with the current filters.'
            : 'No tasks match the current filters.',
        action: OutlinedButton(
          onPressed: () {
            final actions = BoardActions(ref, kind);
            actions.setFilters(board.filters.cleared());
            if (board.search.isNotEmpty) actions.setSearch(null);
          },
          child: const Text('Clear Filters'),
        ),
      );
    }

    void onAdd(TaskStatus status) =>
        openNewTaskForBoard(context, ref, kind, status: status);
    final layout = isToday ? BoardLayout.list : board.display.layout;
    if (layout == BoardLayout.list) {
      return TaskListView(
        groups: board.groups,
        display: board.display,
        crossProject: kind.crossProject,
        collapsed: ref.watch(
          prefsProvider.select((p) => p.collapsedGroups(kind.id)),
        ),
        onToggle: BoardActions(ref, kind).toggleCollapsed,
        onAdd: onAdd,
        readOnly: readOnly,
      );
    }
    return KanbanBoard(
      groups: board.groups,
      display: board.display,
      crossProject: kind.crossProject,
      readOnly: readOnly,
      onAdd: onAdd,
      onDrop: (entry, target) => _drop(ref, board, entry, target),
    );
  }

  /// Drop rules (SPEC §5.1): a different column always changes status; in Manual order the card lands at the drop
  /// point, otherwise at the top. Same column only reorders in Manual order (the board ignores other cases).
  Future<void> _drop(
    WidgetRef ref,
    BoardData board,
    ProjectTask entry,
    DropTarget target,
  ) async {
    final controller = ref.read(workspaceProvider.notifier);
    final list = [
      for (final e in board.groups[target.status] ?? const <ProjectTask>[])
        if (e.task.id != entry.task.id) e,
    ];
    final manual = isManuallyOrdered(board.display.order, target.status);
    final double sortOrder;
    if (manual) {
      final index = target.index.clamp(0, list.length);
      sortOrder = sortOrderBetween(
        index > 0 ? list[index - 1].task.sortOrder : null,
        index < list.length ? list[index].task.sortOrder : null,
      );
    } else if (target.status != entry.task.status) {
      sortOrder = sortOrderAtTop([for (final e in list) e.task.sortOrder]);
    } else {
      return;
    }
    await controller.placeTask(
      entry.project.id,
      entry.task.id,
      status: target.status == entry.task.status ? null : target.status,
      sortOrder: sortOrder,
    );
  }
}

/// Opens the New Task dialog with defaults for [kind] (SPEC §4.2–4.7), optionally pre-set to [status].
void openNewTaskForBoard(
  BuildContext context,
  WidgetRef ref,
  BoardKind kind, {
  TaskStatus? status,
}) {
  final ws = ref.read(workspaceDataProvider);
  if (ws == null) return;
  final defaults = defaultsForBoard(kind, ws, ref.read(todayProvider));
  showNewTaskDialog(
    context,
    ref,
    status == null ? defaults : defaults.copyWith(status: status),
  );
}
