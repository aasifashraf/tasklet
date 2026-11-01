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
bool matchesSearch(ProjectTask entry, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack =
      '${entry.displayId} ${entry.task.title} ${entry.task.description}'
          .toLowerCase();
  return words.every(haystack.contains);
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
