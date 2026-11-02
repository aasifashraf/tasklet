import 'colors.dart';
import 'models.dart';
import 'ordering.dart';
import 'project_keys.dart';

// What a brand-new organization starts with (docs/DECISIONS.md D16): four labels and quick filters that make sense
// in any line of work, plus, in the very first organization only, a sample "Tasklet" project showing Tasklet's own
// plan. Written only into an empty folder; existing data is never touched.

/// Content written into a new, empty organization folder.
typedef StarterContent = ({
  List<Label> labels,
  List<SavedView> views,
  List<Project> projects,
});

/// The starter content. [withSampleProject] adds the Tasklet project (first organization only). [newId] makes ids;
/// [now] stamps everything.
StarterContent starterContent({
  required String Function() newId,
  required DateTime now,
  required bool withSampleProject,
}) {
  final labels = starterLabels(newId);
  return (
    labels: labels,
    views: starterViews(newId, now),
    projects: [if (withSampleProject) starterProject(newId, now, labels)],
  );
}

/// bug, feature, refactor and security, each with an icon and color.
List<Label> starterLabels(String Function() newId) => [
  for (final (name, icon, color) in const [
    ('bug', 'bug', TaskletColor.red),
    ('feature', 'sparkles', TaskletColor.purple),
    ('refactor', 'wrench', TaskletColor.blue),
    ('security', 'shield-check', TaskletColor.amber),
  ])
    Label(id: newId(), name: name, color: color, icon: icon),
];

/// Quick filters built only from status, priority and due date, so they fit any kind of work. The first three are
/// pinned to the sidebar.
List<SavedView> starterViews(String Function() newId, DateTime now) {
  final specs = <(String, String, TaskletColor, BoardFilters, SortOrder, bool)>[
    (
      'Overdue',
      'alarm-clock',
      TaskletColor.red,
      BoardFilters(due: {DueFilter.overdue}),
      SortOrder.dueDate,
      true,
    ),
    (
      'Due Soon',
      'calendar-days',
      TaskletColor.orange,
      BoardFilters(due: {DueFilter.week}),
      SortOrder.dueDate,
      true,
    ),
    (
      'High Priority',
      'flag',
      TaskletColor.red,
      BoardFilters(priorities: {Priority.urgent, Priority.high}),
      SortOrder.priority,
      true,
    ),
    (
      'In Progress',
      'hourglass',
      TaskletColor.yellow,
      BoardFilters(status: {TaskStatus.inProgress}),
      SortOrder.updated,
      false,
    ),
    (
      'No Due Date',
      'calendar',
      TaskletColor.slate,
      BoardFilters(
        due: {DueFilter.none},
        status: {TaskStatus.backlog, TaskStatus.todo, TaskStatus.inProgress},
      ),
      SortOrder.priority,
      false,
    ),
  ];
  return [
    for (final (i, (name, icon, color, filters, order, pinned))
        in specs.indexed)
      SavedView(
        id: newId(),
        name: name,
        color: color,
        icon: icon,
        filters: filters,
        display: ViewDisplay(order: order, direction: order.defaultDirection),
        inSidebar: pinned,
        sidebarOrder: i * sortOrderGap,
        createdAt: now,
        updatedAt: now,
      ),
  ];
}

/// The sample project: Tasklet's own plan, so a new user sees done, in progress, todo and backlog work at once.
/// [labels] are the starter labels (by name) the tasks use.
Project starterProject(
  String Function() newId,
  DateTime now,
  List<Label> labels,
) {
  final labelId = {for (final l in labels) l.name: l.id};
  final tasks = <Task>[];
  void add(
    String title,
    TaskStatus status, {
    String? label,
    Priority priority = Priority.none,
    String description = '',
    int doneDaysAgo = 0,
  }) {
    final number = tasks.length + 1;
    final completed = status == TaskStatus.done
        ? now.subtract(Duration(days: doneDaysAgo, hours: number))
        : null;
    tasks.add(
      Task(
        id: newId(),
        number: number,
        title: title,
        description: description,
        status: status,
        priority: priority,
        labelIds: [?labelId[label]],
        sortOrder: tasks.where((t) => t.status == status).length * sortOrderGap,
        createdAt: completed ?? now,
        updatedAt: completed ?? now,
        completedAt: completed,
      ),
    );
  }

  add(
    "Welcome: this project shows Tasklet's plan",
    TaskStatus.todo,
    priority: Priority.high,
    description:
        "These tasks are Tasklet's own roadmap: what's done, what's in progress, and what's next. Drag a card "
        'to another column to change its status, or open it to edit. Rename or delete this project, and the '
        'bug, feature, refactor and security labels, whenever you like.',
  );
  add(
    'Organizations: one folder each for work, freelance and open source',
    TaskStatus.done,
    label: 'feature',
    doneDaysAgo: 0,
  );
  add(
    'Icons and 16 colors for projects, labels and quick filters',
    TaskStatus.done,
    label: 'feature',
    doneDaysAgo: 1,
  );
  add(
    'Merge edits made on two computers instead of overwriting',
    TaskStatus.done,
    label: 'feature',
    doneDaysAgo: 2,
  );
  add(
    'Backups and Restore Previous Version',
    TaskStatus.done,
    label: 'feature',
    doneDaysAgo: 4,
  );
  add(
    'Fast boards and search with 100,000 tasks',
    TaskStatus.done,
    label: 'refactor',
    doneDaysAgo: 5,
  );
  add(
    'Smoother dragging and searchable pickers',
    TaskStatus.inProgress,
    label: 'refactor',
    priority: Priority.medium,
  );
  add(
    'macOS signing and notarization',
    TaskStatus.inProgress,
    label: 'security',
    priority: Priority.high,
  );
  add(
    'Signed Windows installer',
    TaskStatus.todo,
    label: 'security',
    priority: Priority.medium,
  );
  add('Export Diagnostics in the Help menu', TaskStatus.todo, label: 'feature');
  add(
    'Import from CSV, Trello and Linear',
    TaskStatus.backlog,
    label: 'feature',
  );
  add('iPhone and Android apps', TaskStatus.backlog, label: 'feature');
  add(
    'Local search index for very large workspaces',
    TaskStatus.backlog,
    label: 'refactor',
  );
  add(
    'Stress tests with 100,000 and 500,000 tasks',
    TaskStatus.backlog,
    label: 'refactor',
  );

  return Project(
    id: newId(),
    name: 'Tasklet',
    key: keyForNewProject('Tasklet', const []),
    color: TaskletColor.blue,
    icon: 'rocket',
    createdAt: now,
    updatedAt: now,
    tasks: tasks,
  );
}
