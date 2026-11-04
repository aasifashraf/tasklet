import 'local_date.dart';
import 'models.dart';

// Recurring tasks (docs/DECISIONS.md D17): completing a repeating task leaves it Done (Done is a log) and creates
// the next one, which takes over the rule.

/// The next due date after [anchor] for [rule], skipping past [today] when the rule follows the due date (a late
/// completion never creates an already overdue task). Months keep the rule's day where the month has it
/// (Jan 31, Feb 28, Mar 31).
LocalDate nextOccurrence(Repeat rule, LocalDate anchor, LocalDate today) {
  var date = _step(rule, anchor);
  if (rule.from == RepeatFrom.due) {
    while (!date.isAfter(today)) {
      date = _step(rule, date);
    }
  }
  return date;
}

LocalDate _step(Repeat rule, LocalDate from) => switch (rule.unit) {
  RepeatUnit.day => from.addDays(rule.every),
  RepeatUnit.weekday => _weekdaysAfter(from, rule.every),
  RepeatUnit.week => from.addDays(7 * rule.every),
  RepeatUnit.month => _addMonths(from, rule.every, rule.day ?? from.day),
  RepeatUnit.year => _addMonths(from, 12 * rule.every, rule.day ?? from.day),
};

LocalDate _weekdaysAfter(LocalDate from, int count) {
  var date = from;
  for (var left = count; left > 0;) {
    date = date.addDays(1);
    if (date.weekday <= DateTime.friday) left--;
  }
  return date;
}

LocalDate _addMonths(LocalDate from, int months, int day) {
  final index = from.year * 12 + (from.month - 1) + months;
  final year = index ~/ 12, month = index % 12 + 1;
  final last = DateTime.utc(year, month + 1, 0).day;
  return LocalDate(year, month, day > last ? last : day);
}

/// The id of the occurrence that follows [taskId] on [due]. Derived, not random: two computers completing the same
/// occurrence create the same task, which the merge (D13) keeps once.
String nextOccurrenceId(String taskId, LocalDate due) =>
    '${taskId.split('~').first}~${due.toString().replaceAll('-', '')}';

/// After [before] became [after] in [project]: if a repeating task was just completed, moves the rule to a new
/// task for the next occurrence (top of Todo, number from the project) and returns the project with it, plus the
/// new task. Otherwise returns null.
(Project, Task)? completeRepeating(
  Project project,
  Task before,
  Task after, {
  required LocalDate today,
  required DateTime now,
}) {
  final rule = before.repeat;
  if (rule == null || before.isDone || !after.isDone) return null;
  final completed = after.completedDay ?? today;
  final anchor = rule.from == RepeatFrom.due
      ? (before.dueDate ?? completed)
      : completed;
  final due = nextOccurrence(rule, anchor, today);
  final id = nextOccurrenceId(before.id, due);
  // Already created (reopened and completed again).
  if (project.taskById(id) != null) return null;
  // The start date keeps its distance to the due date.
  final shift = before.dueDate?.daysUntil(due);
  final start = shift == null ? null : before.startDate?.addDays(shift);
  final topOfTodo = [
    for (final t in project.tasks)
      if (t.status == TaskStatus.todo) t.sortOrder,
  ].fold<double>(0, (a, b) => b < a ? b : a);
  final next = Task(
    id: id,
    number: project.nextNumber,
    title: before.title,
    description: before.description,
    priority: before.priority,
    startDate: start,
    dueDate: due,
    labelIds: before.labelIds,
    checklist: [for (final i in before.checklist) i.copyWith(done: false)],
    repeat:
        rule.day == null &&
            (rule.unit == RepeatUnit.month || rule.unit == RepeatUnit.year)
        ? rule.withDay(anchor.day)
        : rule,
    sortOrder: topOfTodo - 1000,
    createdAt: now,
    updatedAt: now,
  );
  final tasks = [
    for (final t in project.tasks)
      if (t.id == after.id) after.copyWith(repeat: null) else t,
    next,
  ];
  return (
    project.copyWith(
      tasks: tasks,
      nextNumber: project.nextNumber + 1,
      updatedAt: now,
    ),
    next,
  );
}
