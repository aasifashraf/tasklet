import 'local_date.dart';
import 'models.dart';

// Filtering & search (SPEC §6): OR within a category, AND across categories; empty category = no filter.

bool matchesDue(Task task, Set<DueFilter> due, LocalDate today) {
  if (due.isEmpty) return true;
  final date = task.dueDate;
  for (final f in due) {
    final match = switch (f) {
      DueFilter.overdue => date != null && date.isBefore(today) && !task.isDone,
      DueFilter.today => date == today,
      DueFilter.week =>
        date != null &&
            !date.isBefore(today) &&
            !date.isAfter(today.addDays(6)),
      DueFilter.none => date == null,
    };
    if (match) return true;
  }
  return false;
}

bool matchesFilters(ProjectTask entry, BoardFilters filters, LocalDate today) {
  final task = entry.task;
  if (filters.status.isNotEmpty && !filters.status.contains(task.status)) {
    return false;
  }
  if (filters.priorities.isNotEmpty &&
      !filters.priorities.contains(task.priority)) {
    return false;
  }
  if (filters.projects.isNotEmpty &&
      !filters.projects.contains(entry.project.id)) {
    return false;
  }
  if (filters.labels.isNotEmpty) {
    final match =
        (filters.labels.contains(noLabelFilterId) && task.labelIds.isEmpty) ||
        task.labelIds.any(filters.labels.contains);
    if (!match) return false;
  }
  return matchesDue(task, filters.due, today);
}

/// Every whitespace-separated word of [query] must appear (case-insensitive) somewhere in the task's
/// ID + title + description. An empty query matches everything.
bool matchesSearch(ProjectTask entry, String query) =>
    SearchQuery(query).matches(entry);

/// A search query parsed once and applied to many tasks (see [matchesSearch]).
class SearchQuery {
  SearchQuery(String query)
    : words = [
        for (final w in query.toLowerCase().split(_whitespace))
          if (w.isNotEmpty) w,
      ];

  static final _whitespace = RegExp(r'\s+');
  static final _digits = RegExp(r'^[0-9]+$');

  final List<String> words;

  // Per word, for matching task IDs ("WEB-12") without building one for every task: project keys are always
  // A-Z and 0-9 (project_keys.dart), so a word without a dash is in the ID only if it is in the key or, when all
  // digits, in the number.
  late final List<String> _upperWords = [
    for (final w in words) w.toUpperCase(),
  ];
  late final List<bool> _allDigits = [
    for (final w in words) _digits.hasMatch(w),
  ];

  bool get isEmpty => words.isEmpty;

  /// Whether every task this query matches is also matched by [previous]: each of its words is part of one of
  /// these words (typing more of a search). Words match within one field, so a part of one does too.
  bool narrows(SearchQuery previous) =>
      previous.words.every((p) => words.any((w) => w.contains(p)));

  bool matches(ProjectTask entry) {
    final text = entry.task.searchText;
    for (var i = 0; i < words.length; i++) {
      if (!text.contains(words[i]) && !_inId(entry, i)) return false;
    }
    return true;
  }

  bool _inId(ProjectTask entry, int i) {
    final word = words[i];
    if (word.contains('-')) {
      return entry.displayId.toLowerCase().contains(word);
    }
    return entry.project.key.contains(_upperWords[i]) ||
        (_allDigits[i] && '${entry.task.number}'.contains(word));
  }
}

/// The Project filter's one-or-the-other model (SPEC §6): "No Project" alone, or one-or-more real projects.
/// Picking a real project clears "No Project" and vice versa. An empty set is "All Projects".
Set<String> toggleProjectFilter(Set<String> current, String projectId) {
  if (projectId == noProjectId) {
    return current.contains(noProjectId) ? {} : {noProjectId};
  }
  final next = {...current}..remove(noProjectId);
  if (!next.remove(projectId)) next.add(projectId);
  return next;
}

/// Drops filter values that reference projects/labels which no longer exist or are archived (SPEC §6).
/// [validProjectIds] should include [noProjectId]; [validLabelIds] should include [noLabelFilterId].
BoardFilters pruneStaleFilters(
  BoardFilters filters,
  Set<String> validProjectIds,
  Set<String> validLabelIds,
) {
  final projects = filters.projects.where(validProjectIds.contains).toSet();
  final labels = filters.labels.where(validLabelIds.contains).toSet();
  if (projects.length == filters.projects.length &&
      labels.length == filters.labels.length) {
    return filters;
  }
  return filters.copyWith(projects: projects, labels: labels);
}
