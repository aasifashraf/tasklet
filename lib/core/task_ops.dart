import 'local_date.dart';
import 'models.dart';
import 'ordering.dart';

// Pure task mutations. Invariants owned here:
// - task numbers come from project.nextNumber and are never reused (SPEC §2.4);
// - completedAt is set exactly when status is done (SPEC §2.2);
// - every edit bumps task.updatedAt and project.updatedAt.
//
// Undo restores a full snapshot of the prior task, so exact completedAt/number restoration (SPEC §7.3) needs no
// special casing beyond `moveTask(restoreNumber:)`.

/// A start date may not fall after the due date (either may be unset).
bool datesInOrder(LocalDate? start, LocalDate? due) =>
    start == null || due == null || !start.isAfter(due);

double _topOf(Project project, TaskStatus status) => sortOrderAtTop([
  for (final t in project.tasks)
    if (t.status == status) t.sortOrder,
]);

/// Creates a task at the top of its status group. Returns the updated project and the new task.
(Project, Task) createTask(
  Project project, {
  required String id,
  required String title,
  String description = '',
  TaskStatus status = TaskStatus.todo,
  Priority priority = Priority.none,
  LocalDate? startDate,
  LocalDate? dueDate,
  List<String> labelIds = const [],
  required DateTime now,
}) {
  final task = Task(
    id: id,
    number: project.nextNumber,
    title: title,
    description: description,
    status: status,
    priority: priority,
    startDate: startDate,
    dueDate: dueDate,
    labelIds: labelIds,
    sortOrder: _topOf(project, status),
    createdAt: now,
    updatedAt: now,
    completedAt: status == TaskStatus.done ? now : null,
  );
  final updated = project.copyWith(
    tasks: [...project.tasks, task],
    nextNumber: project.nextNumber + 1,
    updatedAt: now,
  );
  return (updated, task);
}

/// Changes status, maintaining completedAt. A no-op when the status is unchanged.
Task withStatus(Task task, TaskStatus status, DateTime now) {
  if (task.status == status) return task;
  return task.copyWith(
    status: status,
    completedAt: status == TaskStatus.done ? now : null,
    updatedAt: now,
  );
}

/// Replaces the task with the same id (inserting it if absent, e.g. for undo of a delete).
Project putTask(Project project, Task task, DateTime now) {
  final tasks = [...project.tasks];
  final index = tasks.indexWhere((t) => t.id == task.id);
  if (index < 0) {
    tasks.add(task);
  } else {
    tasks[index] = task;
  }
  return project.copyWith(tasks: tasks, updatedAt: now);
}

Project removeTask(Project project, String taskId, DateTime now) =>
    project.copyWith(
      tasks: [
        for (final t in project.tasks)
          if (t.id != taskId) t,
      ],
      updatedAt: now,
    );

/// An exact copy (project, status, priority, dates, labels) with a new id/number and fresh history, at the top of
/// its status group (SPEC §7.3).
(Project, Task) duplicateTask(
  Project project,
  Task source, {
  required String newId,
  required DateTime now,
}) => createTask(
  project,
  id: newId,
  title: source.title,
  description: source.description,
  status: source.status,
  priority: source.priority,
  startDate: source.startDate,
  dueDate: source.dueDate,
  labelIds: source.labelIds,
  now: now,
);

/// Whether no task in [project] (including entries this version can't display) uses [number], ignoring the task
/// [exceptTaskId].
bool isNumberFree(Project project, int number, {String? exceptTaskId}) =>
    project.tasks.every((t) => t.id == exceptTaskId || t.number != number) &&
    !project.opaqueTasks.any(
      (o) => o is Map && o['number'] == number && o['id'] != exceptTaskId,
    );

/// Repairs task numbers that appear twice in one project, e.g. when two computers both created WEB-13 while
/// offline and sync merged the files. Like project keys (SPEC §2.4), the oldest task (by `createdAt`, then id) keeps
/// a contested number and the others get fresh ones from `nextNumber`; numbers of entries this version can't
/// display are never handed out. Returns the repaired project, or null when every number is unique.
Project? resolveDuplicateNumbers(Project project) {
  final taken = <int>{
    for (final o in project.opaqueTasks)
      if (o case {'number': final int n}) n,
  };
  final ordered = [...project.tasks]
    ..sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  var next = project.nextNumber;
  final renumbered = <String, int>{};
  for (final t in ordered) {
    if (!taken.add(t.number)) renumbered[t.id] = next++;
  }
  if (renumbered.isEmpty) return null;
  return project.copyWith(
    tasks: [
      for (final t in project.tasks)
        renumbered[t.id] == null ? t : t.copyWith(number: renumbered[t.id]),
    ],
    nextNumber: next,
  );
}

/// A task found in more than one project file, and where it was kept.
typedef DuplicateTask = ({Task task, String keptIn, String droppedFrom});

/// The same task id in two project files (a sync race between computers, or a file brought back from the sync
/// service's own history) would show one task twice. The copy edited most recently wins (ties: the project with
/// the smaller id, so every computer decides the same way); the others are removed. Returns the changed projects by
/// id and one entry per removed copy.
({Map<String, Project> changed, List<DuplicateTask> dropped})
resolveDuplicateTaskIds(Iterable<Project> projects) {
  final winner = <String, (Project, Task)>{};
  for (final p in projects) {
    for (final t in p.tasks) {
      final best = winner[t.id];
      if (best == null) {
        winner[t.id] = (p, t);
        continue;
      }
      final (bestProject, bestTask) = best;
      final byUpdated = t.updatedAt.compareTo(bestTask.updatedAt);
      if (byUpdated > 0 ||
          (byUpdated == 0 && p.id.compareTo(bestProject.id) < 0)) {
        winner[t.id] = (p, t);
      }
    }
  }
  final changed = <String, Project>{};
  final dropped = <DuplicateTask>[];
  for (final p in projects) {
    final kept = [
      for (final t in p.tasks)
        if (identical(winner[t.id]!.$1, p)) t,
    ];
    if (kept.length == p.tasks.length) continue;
    for (final t in p.tasks) {
      final (keptIn, _) = winner[t.id]!;
      if (!identical(keptIn, p)) {
        dropped.add((task: t, keptIn: keptIn.id, droppedFrom: p.id));
      }
    }
    changed[p.id] = p.copyWith(tasks: kept);
  }
  return (changed: changed, dropped: dropped);
}

/// Moves [task] from [from] to [to]. The task gets [restoreNumber] if given and still free in [to], otherwise
/// [to]'s next number. Labels not in [allowedLabelIds] (labels usable in [to]) are dropped. Lands at the top of its
/// status group. Returns (updated from, updated to, moved task).
(Project, Project, Task) moveTask(
  Project from,
  Project to,
  Task task, {
  required Set<String> allowedLabelIds,
  int? restoreNumber,
  required DateTime now,
}) {
  final numberFree =
      restoreNumber != null &&
      from.id != to.id &&
      isNumberFree(to, restoreNumber);
  final number = numberFree ? restoreNumber : to.nextNumber;
  final moved = task.copyWith(
    number: number,
    labelIds: [
      for (final id in task.labelIds)
        if (allowedLabelIds.contains(id)) id,
    ],
    sortOrder: _topOf(to, task.status),
    updatedAt: now,
  );
  final updatedTo = to.copyWith(
    tasks: [...to.tasks, moved],
    nextNumber: numberFree ? to.nextNumber : to.nextNumber + 1,
    updatedAt: now,
  );
  return (removeTask(from, task.id, now), updatedTo, moved);
}
