import 'colors.dart';
import 'models.dart';
import 'ordering.dart';
import 'project_keys.dart';

// Pure workspace-level rules (projects, labels, backups). The controller only looks things up, calls these and
// saves the result (docs/SYSTEM_DESIGN.md section 7.2).

/// A new project at the end of the Projects list, with the next free key for its name (SPEC §2.4, §4.5).
Project newProject({
  required String id,
  required String name,
  required TaskletColor color,
  String? icon,
  required List<Project> existing,
  required DateTime now,
}) => Project(
  id: id,
  name: name.trim(),
  key: keyForNewProject(name, existing),
  color: color,
  icon: icon,
  sortOrder: existing.isEmpty
      ? 0
      : existing.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) +
            sortOrderGap,
  createdAt: now,
  updatedAt: now,
);

/// An order value after every one in [orders] (pinning a favorite or a quick filter adds it at the end).
double orderAfterAll(Iterable<double> orders) =>
    orders.fold<double>(-sortOrderGap, (m, o) => o > m ? o : m) + sortOrderGap;

/// [project] without label [labelId]: removed from its own labels and from every task that had it (those tasks'
/// `updatedAt` is bumped). Null when the project doesn't use the label at all (SPEC §4.8).
Project? stripLabel(Project project, String labelId, DateTime now) {
  final owns = project.labels.any((l) => l.id == labelId);
  final used = project.tasks.any((t) => t.labelIds.contains(labelId));
  if (!owns && !used) return null;
  return project.copyWith(
    labels: [
      for (final l in project.labels)
        if (l.id != labelId) l,
    ],
    tasks: [
      for (final t in project.tasks)
        t.labelIds.contains(labelId)
            ? t.copyWith(
                labelIds: [
                  for (final id in t.labelIds)
                    if (id != labelId) id,
                ],
                updatedAt: now,
              )
            : t,
    ],
    updatedAt: now,
  );
}

/// [backup] made current again for the project [current] (docs/DECISIONS.md D12): it keeps the current key, never
/// lowers `nextNumber` (numbers are never reused, SPEC §2.4), and leaves out tasks whose ids now live in another
/// project ([elsewhere]), since restoring them would put one task in two projects. Returns the project and how many
/// tasks were left out.
({Project project, int leftOut}) restoredFromBackup({
  required Project current,
  required Project backup,
  required Set<String> elsewhere,
  required DateTime now,
}) {
  final tasks = [
    for (final t in backup.tasks)
      if (!elsewhere.contains(t.id)) t,
  ];
  return (
    project: backup.copyWith(
      key: current.key,
      tasks: tasks,
      nextNumber: backup.nextNumber > current.nextNumber
          ? backup.nextNumber
          : current.nextNumber,
      updatedAt: now,
    ),
    leftOut: backup.tasks.length - tasks.length,
  );
}
