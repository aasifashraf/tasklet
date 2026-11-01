import 'local_date.dart';

/// Calendar helpers. All take "today" explicitly so callers derive it from the clock (SPEC §9).

LocalDate tomorrowOf(LocalDate today) => today.addDays(1);

/// The next Monday strictly after [today] — the start of next work week (SPEC §7.3).
/// Independent of the OS first-day-of-week, so it never lands on a weekend.
LocalDate nextMondayAfter(LocalDate today) => today.addDays(8 - today.weekday);

/// The first day of the week containing [date], where [firstDayOfWeek] is an ISO weekday (1 = Monday … 7 = Sunday).
LocalDate startOfWeek(LocalDate date, int firstDayOfWeek) {
  final offset = (date.weekday - firstDayOfWeek) % 7;
  return date.addDays(-offset);
}

LocalDate startOfMonth(LocalDate date) => LocalDate(date.year, date.month, 1);

LocalDate endOfMonth(LocalDate date) {
  final next = date.month == 12
      ? LocalDate(date.year + 1, 1, 1)
      : LocalDate(date.year, date.month + 1, 1);
  return next.addDays(-1);
}
