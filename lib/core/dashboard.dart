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

bool _completedWithinLastWeek(Task t, DateTime now) {
  final completed = t.completedAt;
  if (!t.isDone || completed == null) return false;
  final completedDay = LocalDate.fromDateTime(completed);
  final today = LocalDate.fromDateTime(now);
  final days = completedDay.daysUntil(today);
  return days >= 0 && days < 7;
}

Glance glanceFor(Iterable<ProjectTask> tasks, LocalDate today, DateTime now) {
  var overdue = 0, dueToday = 0, dueWeek = 0, done = 0;
  final weekEnd = today.addDays(6);
  for (final e in tasks) {
    final t = e.task;
    if (_completedWithinLastWeek(t, now)) done++;
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
  final list =
      [
        for (final e in tasks)
          if (_completedWithinLastWeek(e.task, now)) e,
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
