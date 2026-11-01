import 'local_date.dart';
import 'models.dart';

// Daily due-date reminder rules (SPEC §11.3).

/// What a reminder notification says, and where clicking it leads.
class ReminderDigest {
  const ReminderDigest({
    required this.title,
    this.body,
    this.singleTask,
    required this.includesTodayOrOverdue,
  });
  final String title;
  final String? body;

  /// Set when exactly one task matched: clicking opens it.
  final ProjectTask? singleTask;

  /// Clicking a summary opens Today if true, otherwise All Tasks.
  final bool includesTodayOrOverdue;
}

String _tasks(int n) => n == 1 ? '1 task' : '$n tasks';

/// Builds today's digest from open tasks in non-archived projects that have a due date; null if nothing matches.
ReminderDigest? buildDigest(
  Iterable<ProjectTask> activeTasks,
  LocalDate today, {
  required bool includeOverdue,
  required bool dayBefore,
}) {
  final dueToday = <ProjectTask>[],
      overdue = <ProjectTask>[],
      tomorrow = <ProjectTask>[];
  for (final e in activeTasks) {
    final due = e.task.dueDate;
    if (e.task.isDone || due == null) continue;
    if (due == today) {
      dueToday.add(e);
    } else if (includeOverdue && due.isBefore(today)) {
      overdue.add(e);
    } else if (dayBefore && due == today.addDays(1)) {
      tomorrow.add(e);
    }
  }
  final total = dueToday.length + overdue.length + tomorrow.length;
  if (total == 0) return null;
  final urgent = dueToday.isNotEmpty || overdue.isNotEmpty;

  if (total == 1) {
    final (title, task) = dueToday.isNotEmpty
        ? ('Due Today', dueToday.single)
        : overdue.isNotEmpty
        ? ('Overdue', overdue.single)
        : ('Due Tomorrow', tomorrow.single);
    return ReminderDigest(
      title: title,
      body: task.task.title,
      singleTask: task,
      includesTodayOrOverdue: urgent,
    );
  }

  final String title;
  final others = <String>[];
  if (dueToday.isNotEmpty) {
    title = '${_tasks(dueToday.length)} due today';
    if (overdue.isNotEmpty) others.add('${overdue.length} overdue');
    if (tomorrow.isNotEmpty) others.add('${tomorrow.length} due tomorrow');
  } else if (overdue.isNotEmpty) {
    title = overdue.length == 1
        ? '1 overdue task'
        : '${overdue.length} overdue tasks';
    if (tomorrow.isNotEmpty) others.add('${tomorrow.length} due tomorrow');
  } else {
    title = '${_tasks(tomorrow.length)} due tomorrow';
  }
  return ReminderDigest(
    title: title,
    body: others.isEmpty ? null : 'Plus ${others.join(' and ')}.',
    includesTodayOrOverdue: urgent,
  );
}

/// Whether today's reminder should go out now: once per calendar day, at or after the configured time, catching up
/// if the app wasn't running then. Turning reminders on (or moving the time) to an already-passed time marks today as
/// sent, so it waits until tomorrow — see [markSentIfTimePassed].
bool reminderIsDue({
  required DateTime now,
  required int hour,
  required int minute,
  required String? lastSentDay,
}) {
  final today = LocalDate.fromDateTime(now);
  if (lastSentDay == today.toString()) return false;
  return !now.isBefore(DateTime(now.year, now.month, now.day, hour, minute));
}

/// The value to store as "last sent day" when reminders are enabled or the time changes: today if the new time has
/// already passed (so nothing fires until tomorrow), otherwise [current] unchanged.
String? markSentIfTimePassed({
  required DateTime now,
  required int hour,
  required int minute,
  String? current,
}) {
  final passed = !now.isBefore(
    DateTime(now.year, now.month, now.day, hour, minute),
  );
  return passed ? LocalDate.fromDateTime(now).toString() : current;
}
