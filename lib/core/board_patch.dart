import 'merge.dart' show jsonEquals;
import 'models.dart';
import 'sorting.dart';

// Incremental board updates (docs/SYSTEM_DESIGN.md section 9): after an edit only a few tasks change, so a board
// re-inserts those instead of grouping and sorting every task again (~200 ms at 100k tasks, ~1 ms patched).

/// Tasks that differ between two workspace snapshots: [removed] (changed or deleted, old versions, by id) and
/// [added] (changed or new, new versions). Unchanged projects and tasks are the same instances in both snapshots.
typedef TaskDiff = ({
  Map<String, ProjectTask> removed,
  List<ProjectTask> added,
});

/// The task-level difference from [before] to [after], or null when only a full recompute is safe: a project was
/// added, removed, or changed anything besides its tasks (name, key, color, archived, labels...), or more than
/// [limit] tasks changed.
TaskDiff? diffTasks(Workspace before, Workspace after, {int limit = 200}) {
  if (before.projects.length != after.projects.length) return null;
  final previous = {for (final p in before.allProjects) p.id: p};
  final removed = <String, ProjectTask>{};
  final added = <ProjectTask>[];
  for (final p in after.allProjects) {
    final old = previous[p.id];
    if (identical(old, p)) continue;
    if (old == null || !_sameProjectFields(old, p)) return null;
    final oldTasks = {for (final t in old.tasks) t.id: t};
    for (final t in p.tasks) {
      final o = oldTasks.remove(t.id);
      if (identical(o, t)) continue;
      if (o != null) removed[t.id] = ProjectTask(old, o);
      added.add(ProjectTask(p, t));
    }
    for (final o in oldTasks.values) {
      removed[o.id] = ProjectTask(old, o);
    }
    if (removed.length + added.length > limit) return null;
  }
  return (removed: removed, added: added);
}

bool _sameProjectFields(Project a, Project b) =>
    a.name == b.name &&
    a.key == b.key &&
    a.color == b.color &&
    a.unknownColor == b.unknownColor &&
    a.icon == b.icon &&
    a.archived == b.archived &&
    a.favorite == b.favorite &&
    a.sortOrder == b.sortOrder &&
    a.favoriteOrder == b.favoriteOrder &&
    jsonEquals(a.extra, b.extra) &&
    _sameLabels(a.labels, b.labels);

bool _sameLabels(List<Label> a, List<Label> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].name != b[i].name ||
        a[i].color != b[i].color ||
        a[i].icon != b[i].icon) {
      return false;
    }
  }
  return true;
}

/// [previous] groups (sorted by [display]) with the [removed] tasks (their old versions) taken out and [added]
/// inserted at their sorted positions. Every comparator ends with an id tie-break, so a task's position is unique:
/// both steps are binary searches, and the result equals grouping and sorting everything again.
Map<TaskStatus, List<ProjectTask>> patchGroups(
  Map<TaskStatus, List<ProjectTask>> previous,
  ViewDisplay display, {
  required Iterable<ProjectTask> removed,
  required Iterable<ProjectTask> added,
}) {
  final result = {
    for (final s in TaskStatus.values)
      s: List.of(previous[s] ?? const <ProjectTask>[]),
  };
  // Where [task] is, or would go, in [list].
  int position(List<ProjectTask> list, Task task) {
    final compare = comparatorFor(
      display.order,
      display.direction,
      status: task.status,
    );
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (compare(list[mid].task, task) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  for (final e in removed) {
    final list = result[e.task.status]!;
    final i = position(list, e.task);
    // Not on the board before (filtered out or out of scope): nothing to remove.
    if (i < list.length && list[i].task.id == e.task.id) list.removeAt(i);
  }
  for (final e in added) {
    final list = result[e.task.status]!;
    list.insert(position(list, e.task), e);
  }
  return result;
}
