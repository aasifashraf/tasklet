import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard.dart';
import '../../core/date_format.dart';
import '../../core/models.dart';
import '../../state/clock.dart';
import '../../state/prefs.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../board/task_tiles.dart';
import '../glyphs.dart';
import '../task/task_menu.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_parts.dart';
import 'page_scaffold.dart';

/// Dashboard (SPEC §4.1).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    if (ws == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final now = ref.watch(nowProvider);
    final today = ref.watch(todayProvider);
    final name = ref.watch(prefsProvider.select((p) => p.userName));
    final storedFilter = ref.watch(
      prefsProvider.select((p) => p.dashboardProject),
    );
    final activeProjects = ws.projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final project = activeProjects
        .where((p) => p.id == storedFilter)
        .firstOrNull;
    final tasks = project == null
        ? ws.activeTasks.toList()
        : [for (final task in project.tasks) ProjectTask(project, task)];

    void setFilter(String? id) =>
        ref.read(prefsProvider.notifier).set(PrefKeys.dashboardProject, id);

    final glance = glanceFor(tasks, today, now);
    final next = upNext(tasks, today);
    final recent = recentlyCompleted(tasks, now);

    return PageScaffold(
      title: 'Dashboard',
      actions: [
        PillMenuButton(
          label: project?.name ?? 'All Projects',
          leading: project == null
              ? null
              : CubeIcon(color: t.named(project.color), size: 12),
          menuChildren: [
            checkItem(
              'All Projects',
              checked: project == null,
              onPressed: () => setFilter(null),
            ),
            if (activeProjects.isNotEmpty) const Divider(),
            for (final p in activeProjects)
              checkItem(
                p.name,
                checked: project?.id == p.id,
                leading: CubeIcon(color: t.named(p.color), size: 12),
                onPressed: () => setFilter(p.id),
              ),
          ],
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    greeting(now, name),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fullDate(today),
                    style: TextStyles.bodySecondary(context)
                        .copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  if (tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: EmptyState(
                        icon: Icons.checklist_rounded,
                        title: project == null
                            ? 'No tasks yet'
                            : 'This project has no tasks',
                        message: 'Press Ctrl+N to create a task. Your overview will appear here.',
                      ),
                    )
                  else ...[
                    _GlanceStrip(glance: glance),
                    if (next.isNotEmpty) ...[
                      _SectionTitle('Up Next'),
                      _TaskRows(
                        entries: next,
                        showProject: project == null,
                        trailing: (e) => _DuePill(e.task),
                      ),
                    ],
                    _SectionTitle('Overview'),
                    _StatusCard(counts: statusCounts(tasks)),
                    if (recent.isNotEmpty) ...[
                      _SectionTitle('Recently Completed'),
                      _TaskRows(
                        entries: recent,
                        showProject: project == null,
                        trailing: (e) => Text(
                          completedLabel(e.task.completedAt!, today),
                          style: TextStyles.meta(context),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 28, 0, 10),
    child: Text(text, style: TextStyles.section(context)),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _GlanceStrip extends StatelessWidget {
  const _GlanceStrip({required this.glance});
  final Glance glance;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget cell(String label, int value, Color? color) => Expanded(
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: value > 0 && color != null ? color : t.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyles.bodySecondary(context)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell('Overdue', glance.overdue, t.danger),
        const SizedBox(width: 10),
        cell('Due today', glance.dueToday, t.warning),
        const SizedBox(width: 10),
        cell('Due this week', glance.dueThisWeek, null),
        const SizedBox(width: 10),
        cell('Done this week', glance.doneThisWeek, null),
      ],
    );
  }
}

class _DuePill extends ConsumerWidget {
  const _DuePill(this.task);
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    return datePill(context, task, today, start: false, due: true) ??
        const SizedBox.shrink();
  }
}

/// Up Next / Recently Completed rows: click opens the panel, right-click has the full task menu (SPEC §4.1).
class _TaskRows extends ConsumerWidget {
  const _TaskRows({
    required this.entries,
    required this.showProject,
    required this.trailing,
  });
  final List<ProjectTask> entries;
  final bool showProject;
  final Widget Function(ProjectTask e) trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final open = ref.watch(openTaskProvider);
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        children: [
          for (final e in entries)
            ContextMenuRegion(
              menuChildren: () => taskMenuChildren(context, ref, e),
              child: TaskFocus(
                taskRef: TaskRef(e.project.id, e.task.id),
                builder: (focused) => Hoverable(
                  cursor: SystemMouseCursors.click,
                  builder: (context, hovered) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(openTaskProvider.notifier)
                        .open(TaskRef(e.project.id, e.task.id)),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: open?.taskId == e.task.id
                            ? t.openHighlight
                            : (hovered ? t.hover : Colors.transparent),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          StatusIcon(e.task.status),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 60,
                            child: Text(
                              e.displayId,
                              style: TextStyles.meta(context),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.body(context),
                            ),
                          ),
                          if (showProject && !e.project.isNoProject) ...[
                            CubeIcon(color: t.named(e.project.color), size: 12),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                e.project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyles.meta(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          trailing(e),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.counts});
  final Map<TaskStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final total = counts.values.fold(0, (a, b) => a + b);
    Color colorOf(TaskStatus s) => switch (s) {
      TaskStatus.backlog => t.tertiary.withValues(alpha: 0.35),
      TaskStatus.todo => t.tertiary,
      TaskStatus.inProgress => t.status(TaskStatus.inProgress),
      TaskStatus.done => t.accent,
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status', style: TextStyles.sectionLabel(context)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  for (final s in TaskStatus.values)
                    if (counts[s]! > 0)
                      Expanded(
                        flex: counts[s]!,
                        child: Container(color: colorOf(s)),
                      ),
                  if (total == 0) Expanded(child: Container(color: t.selected)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              for (final s in TaskStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusIcon(s),
                    const SizedBox(width: 6),
                    Text(s.label, style: TextStyles.body(context)),
                    const SizedBox(width: 6),
                    Text(
                      '${counts[s]}',
                      style: TextStyles.body(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      total == 0
                          ? '0%'
                          : '${(counts[s]! * 100 / total).round()}%',
                      style: TextStyles.meta(context),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
