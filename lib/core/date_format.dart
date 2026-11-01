import 'package:intl/intl.dart';

import 'local_date.dart';

// Human date labels. All take `today` so they roll over at midnight with the clock (SPEC §9).

final _monthDay = DateFormat('MMM d');
final _monthDayYear = DateFormat('MMM d, y');
final _weekdayMonthDay = DateFormat('EEEE, MMMM d');
final _longDate = DateFormat('MMMM d, y');
final _weekdayShort = DateFormat('EEE, MMM d');

/// "Oct 3", or "Nov 9, 2027" outside the current year.
String shortDate(LocalDate date, LocalDate today) =>
    (date.year == today.year ? _monthDay : _monthDayYear).format(
      date.toLocalDateTime(),
    );

/// "Today" / "Tomorrow" / "Yesterday", otherwise [shortDate].
String relativeDate(LocalDate date, LocalDate today) =>
    switch (today.daysUntil(date)) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => shortDate(date, today),
    };

/// The combined card date pill (SPEC §8.6): "Oct 3 → Oct 10", "Oct 3 →", "Oct 10"; one date if start == due.
String? datePillLabel(LocalDate? start, LocalDate? due, LocalDate today) {
  if (start == null && due == null) return null;
  if (start == null || start == due) return relativeDate(due!, today);
  if (due == null) return '${relativeDate(start, today)} →';
  return '${relativeDate(start, today)} → ${relativeDate(due, today)}';
}

/// "Friday, October 23" (Dashboard).
String fullDate(LocalDate date) =>
    _weekdayMonthDay.format(date.toLocalDateTime());

/// "October 23, 2026" (detail panel footer).
String longDate(DateTime time) => _longDate.format(time.toLocal());

/// "Mon, Nov 3" (context-menu due-date hints).
String weekdayHint(LocalDate date) =>
    _weekdayShort.format(date.toLocalDateTime());

/// "Good morning/afternoon/evening[, Name]" (SPEC §4.1).
String greeting(DateTime now, String name) {
  final part = now.hour < 12
      ? 'morning'
      : (now.hour < 18 ? 'afternoon' : 'evening');
  return name.trim().isEmpty ? 'Good $part' : 'Good $part, ${name.trim()}';
}

/// "Completed today", "Completed yesterday", "Completed Oct 3".
String completedLabel(DateTime completedAt, LocalDate today) {
  final date = LocalDate.fromDateTime(completedAt);
  final rel = relativeDate(date, today);
  return rel == 'Today' || rel == 'Yesterday'
      ? 'Completed ${rel.toLowerCase()}'
      : 'Completed $rel';
}
