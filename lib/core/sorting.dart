import 'models.dart';

// Sort rules (SPEC §5.3), applied identically to board columns and list sections. Every comparator ends with
// an id tie-break so no two tasks ever compare equal (drag targets and virtualization depend on it).

typedef TaskComparator = int Function(Task a, Task b);

int _manual(Task a, Task b) {
  final byOrder = a.sortOrder.compareTo(b.sortOrder);
  if (byOrder != 0) return byOrder;
  final byCreated = b.createdAt.compareTo(a.createdAt); // newest first
  if (byCreated != 0) return byCreated;
  return a.id.compareTo(b.id);
}

/// Priority ascending (urgent first) with None always last.
int _priorityAsc(Task a, Task b) => a.priority.rank.compareTo(b.priority.rank);

int _priority(Task a, Task b, int sign) {
  final aNone = a.priority == Priority.none,
      bNone = b.priority == Priority.none;
  if (aNone != bNone) return aNone ? 1 : -1;
  final byRank = sign * _priorityAsc(a, b);
  return byRank != 0 ? byRank : _manual(a, b);
}

int _due(Task a, Task b, int sign) {
  final aDate = a.dueDate ?? a.startDate, bDate = b.dueDate ?? b.startDate;
  if (aDate == null || bDate == null) {
    if (aDate != bDate) return aDate == null ? 1 : -1; // undated always sink
  } else {
    final byDate = sign * aDate.compareTo(bDate);
    if (byDate != 0) return byDate;
  }
  final byPriority = _priorityAsc(a, b);
  return byPriority != 0 ? byPriority : _manual(a, b);
}

int _byTime(DateTime a, DateTime b, int sign, Task ta, Task tb) {
  final byTime = sign * a.compareTo(b);
  return byTime != 0 ? byTime : _manual(ta, tb);
}

/// Done column under Manual order: most recently completed first (SPEC §5.1).
int _recentFirst(Task a, Task b) {
  final byCompleted = (b.completedAt ?? b.updatedAt).compareTo(
    a.completedAt ?? a.updatedAt,
  );
  if (byCompleted != 0) return byCompleted;
  final byUpdated = b.updatedAt.compareTo(a.updatedAt);
  return byUpdated != 0 ? byUpdated : _manual(a, b);
}

/// The comparator for one status group. [status] matters only for Done under Manual order.
TaskComparator comparatorFor(
  SortOrder order,
  SortDirection direction, {
  TaskStatus? status,
}) {
  final sign = direction == SortDirection.asc ? 1 : -1;
  return switch (order) {
    SortOrder.manual => status == TaskStatus.done ? _recentFirst : _manual,
    SortOrder.priority => (a, b) => _priority(a, b, sign),
    SortOrder.dueDate => (a, b) => _due(a, b, sign),
    SortOrder.updated => (a, b) => _byTime(
      a.updatedAt,
      b.updatedAt,
      sign,
      a,
      b,
    ),
    SortOrder.newest => (a, b) => _byTime(a.createdAt, b.createdAt, sign, a, b),
  };
}

/// Whether drag-reordering within a column is meaningful: only Manual order, and never in Done under Manual
/// (Done shows "Recent first", which is computed, not stored).
bool isManuallyOrdered(SortOrder order, TaskStatus status) =>
    order == SortOrder.manual && status != TaskStatus.done;

/// Groups [tasks] by status (workflow order) and sorts each group.
Map<TaskStatus, List<ProjectTask>> groupAndSort(
  Iterable<ProjectTask> tasks,
  ViewDisplay display,
) {
  final groups = {for (final s in TaskStatus.values) s: <ProjectTask>[]};
  for (final t in tasks) {
    groups[t.task.status]!.add(t);
  }
  for (final entry in groups.entries) {
    final compare = comparatorFor(
      display.order,
      display.direction,
      status: entry.key,
    );
    entry.value.sort((a, b) => compare(a.task, b.task));
  }
  return groups;
}
