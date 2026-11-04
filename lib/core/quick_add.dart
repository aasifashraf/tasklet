import 'dates.dart';
import 'local_date.dart';
import 'models.dart';

// Quick add (docs/DECISIONS.md D17): a New Task title like "Fix login tomorrow !high #bug +WEB" fills the task's
// fields. A token is taken only when it means something here (an existing label or project, a real date or
// priority), so "#1 priority" or "+1" stay part of the title.

/// What a title typed into New Task means: the remaining title and the fields it set (null = not mentioned).
class QuickAdd {
  const QuickAdd({
    required this.title,
    this.due,
    this.priority,
    this.labels = const [],
    this.project,
  });
  final String title;
  final LocalDate? due;
  final Priority? priority;
  final List<Label> labels;
  final Project? project;

  bool get isEmpty =>
      due == null && priority == null && labels.isEmpty && project == null;
}

const _priorities = {
  'urgent': Priority.urgent,
  'high': Priority.high,
  'medium': Priority.medium,
  'med': Priority.medium,
  'low': Priority.low,
  '1': Priority.urgent,
  '2': Priority.high,
  '3': Priority.medium,
  '4': Priority.low,
};

const _weekdays = {
  'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2, //
  'wednesday': 3, 'wed': 3, 'thursday': 4, 'thu': 4, 'thurs': 4,
  'friday': 5, 'fri': 5, 'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
};

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses [text]. [labels] are the labels usable for the task (any project's when [projects] can change it),
/// [projects] the projects it may go to. The last mention of a field wins.
QuickAdd parseQuickAdd(
  String text, {
  required LocalDate today,
  required List<Label> labels,
  required List<Project> projects,
}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final keep = List<bool>.filled(words.length, true);
  LocalDate? due;
  Priority? priority;
  Project? project;
  final picked = <Label>[];

  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final lower = w.toLowerCase();
    if (lower.startsWith('!') && _priorities.containsKey(lower.substring(1))) {
      priority = _priorities[lower.substring(1)];
      keep[i] = false;
    } else if (w.startsWith('#') && w.length > 1) {
      final name = w.substring(1).toLowerCase();
      final label =
          labels.where((l) => l.name.toLowerCase() == name).firstOrNull ??
          labels
              .where((l) => l.name.toLowerCase().replaceAll(' ', '-') == name)
              .firstOrNull;
      if (label != null) {
        if (!picked.any((l) => l.id == label.id)) picked.add(label);
        keep[i] = false;
      }
    } else if (w.startsWith('+') && w.length > 1) {
      final key = w.substring(1).toUpperCase();
      final match =
          projects.where((p) => p.key == key).firstOrNull ??
          projects
              .where((p) => p.name.toLowerCase().startsWith(lower.substring(1)))
              .firstOrNull;
      if (match != null) {
        project = match;
        keep[i] = false;
      }
    } else {
      final (date, used) = _date(words, i, today);
      if (date != null) {
        due = date;
        for (var k = i; k < i + used; k++) {
          keep[k] = false;
        }
        i += used - 1;
      }
    }
  }
  return QuickAdd(
    title: [
      for (var i = 0; i < words.length; i++)
        if (keep[i]) words[i],
    ].join(' '),
    due: due,
    priority: priority,
    labels: picked,
    project: project,
  );
}

/// A date starting at word [i] and how many words it took: today, tomorrow, weekdays (the next one), "next week"
/// (Monday), "in N days/weeks", "nov 5" / "5 nov" (this year, or next if already past), "2026-11-05".
(LocalDate?, int) _date(List<String> words, int i, LocalDate today) {
  String at(int k) =>
      k < words.length ? words[k].toLowerCase().replaceAll(',', '') : '';
  final w = at(i);
  switch (w) {
    case 'today' || 'tod':
      return (today, 1);
    case 'tomorrow' || 'tmr' || 'tom':
      return (tomorrowOf(today), 1);
  }
  if (_weekdays[w] case final day?) {
    final ahead = (day - today.weekday + 7) % 7;
    return (today.addDays(ahead == 0 ? 7 : ahead), 1);
  }
  if (w == 'next' && at(i + 1) == 'week') return (nextMondayAfter(today), 2);
  if (w == 'in') {
    final n = int.tryParse(at(i + 1));
    final unit = at(i + 2);
    if (n != null && n > 0 && n < 1000) {
      if (unit == 'day' || unit == 'days') return (today.addDays(n), 3);
      if (unit == 'week' || unit == 'weeks') return (today.addDays(7 * n), 3);
    }
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(w)) {
    try {
      return (LocalDate.parse(w), 1);
    } on FormatException {
      return (null, 0);
    }
  }
  // "nov 5" or "5 nov".
  final month = _months[w.length >= 3 ? w.substring(0, 3) : ''];
  final day = int.tryParse(at(i + 1));
  if (month != null && day != null) return (_upcoming(today, month, day), 2);
  final first = int.tryParse(w);
  final month2 =
      _months[at(i + 1).length >= 3 ? at(i + 1).substring(0, 3) : ''];
  if (first != null && month2 != null) {
    return (_upcoming(today, month2, first), 2);
  }
  return (null, 0);
}

LocalDate? _upcoming(LocalDate today, int month, int day) {
  for (final year in [today.year, today.year + 1]) {
    final date = DateTime.utc(year, month, day);
    if (date.month != month) return null; // "feb 30"
    final local = LocalDate(year, month, day);
    if (!local.isBefore(today)) return local;
  }
  return null;
}
