import 'local_date.dart';
import 'models.dart';

/// The Today page's three toggleable rules (SPEC §4.2). At least one is always on.
enum TodayRule {
  dueToday('Due today'),
  startsToday('Starts today'),
  overdue('Overdue');

  const TodayRule(this.label);
  final String label;
}

/// Whether [task] belongs on the Today page under any of [rules].
bool matchesToday(Task task, Set<TodayRule> rules, LocalDate today) {
  for (final rule in rules) {
    final match = switch (rule) {
      TodayRule.dueToday => task.dueDate == today,
      TodayRule.startsToday => task.startDate == today,
      TodayRule.overdue =>
        task.dueDate != null && task.dueDate!.isBefore(today) && !task.isDone,
    };
    if (match) return true;
  }
  return false;
}

/// Toggles [rule], refusing to turn off the last remaining one.
Set<TodayRule> toggleTodayRule(Set<TodayRule> rules, TodayRule rule) {
  if (rules.contains(rule)) {
    return rules.length == 1 ? rules : ({...rules}..remove(rule));
  }
  return {...rules, rule};
}
