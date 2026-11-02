import 'local_date.dart';
import 'models.dart';
import 'sorting.dart';

/// Glance numbers (SPEC §4.1). "This week" = today + next 6 days; "done this week" = completed in the last 7 days.
class Glance {
  const Glance({
    required this.overdue,
    required this.dueToday,
    required this.dueThisWeek,
    required this.doneThisWeek,
  });
  final int overdue;
  final int dueToday;
  final int dueThisWeek;
  final int doneThisWeek;
}

/// "Completed in the last 7 days" as an instant range: from local midnight 6 days before [now]'s day up to (not
/// including) local midnight after it. Comparing instants avoids a timezone conversion per task, which dominated
/// the Dashboard at 100k tasks (docs/SYSTEM_DESIGN.md, P1).
typedef _Window = ({DateTime from, DateTime until});

_Window _lastWeek(DateTime now) {
  final today = LocalDate.fromDateTime(now);
  return (
    from: today.addDays(-6).toLocalDateTime(),
    until: today.addDays(1).toLocalDateTime(),
  );
}

bool _completedIn(Task t, _Window w) {
  final completed = t.completedAt;
  return t.isDone &&
      completed != null &&
      !completed.isBefore(w.from) &&
      completed.isBefore(w.until);
}

Glance glanceFor(Iterable<ProjectTask> tasks, LocalDate today, DateTime now) {
  var overdue = 0, dueToday = 0, dueWeek = 0, done = 0;
  final weekEnd = today.addDays(6);
  final window = _lastWeek(now);
  for (final e in tasks) {
    final t = e.task;
    if (_completedIn(t, window)) done++;
    if (t.isDone || t.dueDate == null) continue;
    final due = t.dueDate!;
    if (due.isBefore(today)) overdue++;
    if (due == today) dueToday++;
    if (!due.isBefore(today) && !due.isAfter(weekEnd)) dueWeek++;
  }
  return Glance(
    overdue: overdue,
    dueToday: dueToday,
    dueThisWeek: dueWeek,
    doneThisWeek: done,
  );
}

/// Up to 6 open tasks overdue or due within 7 days: due date asc, then priority (none last), then manual order.
List<ProjectTask> upNext(Iterable<ProjectTask> tasks, LocalDate today) {
  final weekEnd = today.addDays(6);
  final manual = comparatorFor(SortOrder.manual, SortDirection.asc);
  final list = [
    for (final e in tasks)
      if (!e.task.isDone &&
          e.task.dueDate != null &&
          !e.task.dueDate!.isAfter(weekEnd))
        e,
  ];
  list.sort((a, b) {
    final byDue = a.task.dueDate!.compareTo(b.task.dueDate!);
    if (byDue != 0) return byDue;
    final byPriority = a.task.priority.rank.compareTo(b.task.priority.rank);
    return byPriority != 0 ? byPriority : manual(a.task, b.task);
  });
  return list.take(6).toList();
}

/// Up to 5 tasks completed in the last 7 days, most recent first.
List<ProjectTask> recentlyCompleted(Iterable<ProjectTask> tasks, DateTime now) {
  final window = _lastWeek(now);
  final list =
      [
        for (final e in tasks)
          if (_completedIn(e.task, window)) e,
      ]..sort((a, b) {
        final byTime = b.task.completedAt!.compareTo(a.task.completedAt!);
        return byTime != 0 ? byTime : a.task.id.compareTo(b.task.id);
      });
  return list.take(5).toList();
}

/// Task counts per status, in workflow order.
Map<TaskStatus, int> statusCounts(Iterable<ProjectTask> tasks) {
  final counts = {for (final s in TaskStatus.values) s: 0};
  for (final e in tasks) {
    counts[e.task.status] = counts[e.task.status]! + 1;
  }
  return counts;
}
