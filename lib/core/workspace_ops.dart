import 'colors.dart';
import 'models.dart';
import 'ordering.dart';
import 'project_keys.dart';

// Pure workspace-level rules (projects, labels, backups). The controller only looks things up, calls these and
// saves the result (docs/SYSTEM_DESIGN.md section 7.2).

/// A new project at the end of the Projects list, with the next free key for its name (SPEC §2.4, §4.5).
Project newProject({
  required String id,
  required String name,
  required TaskletColor color,
  String? icon,
  required List<Project> existing,
  required DateTime now,
}) => Project(
  id: id,
  name: name.trim(),
  key: keyForNewProject(name, existing),
  color: color,
  icon: icon,
  sortOrder: existing.isEmpty
      ? 0
      : existing.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) +
            sortOrderGap,
  createdAt: now,
  updatedAt: now,
);

/// An order value after every one in [orders] (pinning a favorite or a quick filter adds it at the end).
double orderAfterAll(Iterable<double> orders) =>
    orders.fold<double>(-sortOrderGap, (m, o) => o > m ? o : m) + sortOrderGap;

/// [project] without label [labelId]: removed from its own labels and from every task that had it (those tasks'
/// `updatedAt` is bumped). Null when the project doesn't use the label at all (SPEC §4.8).
Project? stripLabel(Project project, String labelId, DateTime now) {
  final owns = project.labels.any((l) => l.id == labelId);
  final used = project.tasks.any((t) => t.labelIds.contains(labelId));
  if (!owns && !used) return null;
  return project.copyWith(
    labels: [
      for (final l in project.labels)
        if (l.id != labelId) l,
    ],
    tasks: [
      for (final t in project.tasks)
        t.labelIds.contains(labelId)
            ? t.copyWith(
                labelIds: [
                  for (final id in t.labelIds)
                    if (id != labelId) id,
                ],
                updatedAt: now,
              )
            : t,
    ],
    updatedAt: now,
  );
}

/// [backup] made current again for the project [current] (docs/DECISIONS.md D12): it keeps the current key, never
/// lowers `nextNumber` (numbers are never reused, SPEC §2.4), and leaves out tasks whose ids now live in another
/// project ([elsewhere]), since restoring them would put one task in two projects. Returns the project and how many
/// tasks were left out.
({Project project, int leftOut}) restoredFromBackup({
  required Project current,
  required Project backup,
  required Set<String> elsewhere,
  required DateTime now,
}) {
  final tasks = [
    for (final t in backup.tasks)
      if (!elsewhere.contains(t.id)) t,
  ];
  return (
    project: backup.copyWith(
      key: current.key,
      tasks: tasks,
      nextNumber: backup.nextNumber > current.nextNumber
          ? backup.nextNumber
          : current.nextNumber,
      updatedAt: now,
    ),
    leftOut: backup.tasks.length - tasks.length,
  );
}

/// [project] as it should be written into another workspace's folder (docs/DECISIONS.md D15). Workspace labels
/// its tasks use ([workspaceLabels], from the workspace it leaves) come along as the project's own labels, so
/// the other folder's labels.json is never touched. It keeps its key unless a project there already has it, keeps
/// every task number, and goes to the end of the Projects (and Favorites) list.
Project projectForTransfer(
  Project project, {
  required List<Label> workspaceLabels,
  required List<Project> targetProjects,
  required DateTime now,
}) {
  final own = {for (final l in project.labels) l.id};
  final used = {for (final t in project.tasks) ...t.labelIds};
  final carried = [
    for (final l in workspaceLabels)
      if (used.contains(l.id) && !own.contains(l.id)) l,
  ];
  final keyTaken = targetProjects.any((p) => p.key == project.key);
  return project.copyWith(
    key: keyTaken ? keyForNewProject(project.name, targetProjects) : null,
    labels: [...project.labels, ...carried],
    sortOrder: orderAfterAll(targetProjects.map((p) => p.sortOrder)),
    favoriteOrder: project.favorite
        ? orderAfterAll([
            for (final p in targetProjects)
              if (p.favorite) p.favoriteOrder,
          ])
        : null,
    updatedAt: now,
  );
}

/// Duplicate Project… (D17 templates): a new project like [source] ("Name copy", its own key, right after it in
/// the sidebar) whose tasks start over: Todo (Backlog stays Backlog), no dates, completion or snooze, checklists
/// unticked, numbers from 1. Labels are copied with new ids so the tasks keep theirs; repeat rules are kept.
Project duplicateProject(
  Project source, {
  required String id,
  required List<Project> existing,
  required String Function() newId,
  required DateTime now,
}) {
  final labelIds = {for (final l in source.labels) l.id: newId()};
  final tasks = [...source.tasks]..sort((a, b) => a.number.compareTo(b.number));
  final name = '${source.name} copy';
  return Project(
    id: id,
    name: name,
    key: keyForNewProject(name, existing),
    color: source.color,
    unknownColor: source.unknownColor,
    icon: source.icon,
    sortOrder: source.sortOrder + sortOrderGap / 2,
    labels: [
      for (final l in source.labels)
        Label(
          id: labelIds[l.id]!,
          name: l.name,
          color: l.color,
          unknownColor: l.unknownColor,
          icon: l.icon,
        ),
    ],
    nextNumber: tasks.length + 1,
    createdAt: now,
    updatedAt: now,
    tasks: [
      for (final (i, t) in tasks.indexed)
        Task(
          id: newId(),
          number: i + 1,
          title: t.title,
          description: t.description,
          status: t.status == TaskStatus.backlog
              ? TaskStatus.backlog
              : TaskStatus.todo,
          priority: t.priority,
          labelIds: [for (final l in t.labelIds) labelIds[l] ?? l],
          checklist: [for (final c in t.checklist) c.copyWith(done: false)],
          repeat: t.repeat,
          sortOrder: (i + 1) * sortOrderGap,
          createdAt: now,
          updatedAt: now,
        ),
    ],
  );
}
