import 'colors.dart';
import 'local_date.dart';

// Entities from SPEC §2.2. Every entity preserves unrecognized JSON fields in `extra` and writes them back
// unchanged (SPEC §2.5), so data written by a newer Tasklet on another machine is never stripped.

/// Reserved id of the built-in "No Project" bucket (SPEC §2.3). Also used as the Project filter value for
/// "No Project".
const String noProjectId = 'no-project';

/// Reserved task-ID key of the "No Project" bucket.
const String noProjectKey = 'TSK';

/// Label filter value meaning "tasks with zero labels".
const String noLabelFilterId = 'no-label';

const Object _unset = Object();

enum TaskStatus {
  backlog('backlog', 'Backlog'),
  todo('todo', 'Todo'),
  inProgress('in_progress', 'In Progress'),
  done('done', 'Done');

  const TaskStatus(this.json, this.label);
  final String json;
  final String label;

  static TaskStatus fromJson(Object? value) =>
      values.firstWhere((s) => s.json == value, orElse: () => throw FormatException('Unknown status: $value'));
}

enum Priority {
  none(0, 'No priority'),
  urgent(1, 'Urgent'),
  high(2, 'High'),
  medium(3, 'Medium'),
  low(4, 'Low');

  const Priority(this.value, this.label);
  final int value;
  final String label;

  /// Sort rank: Urgent 1 … Low 4, None 5 (SPEC §5.3).
  int get rank => this == none ? 5 : value;

  static Priority fromJson(Object? value) =>
      values.firstWhere((p) => p.value == value, orElse: () => throw FormatException('Unknown priority: $value'));
}

enum SortOrder {
  manual('manual', 'Manual'),
  priority('priority', 'Priority'),
  dueDate('dueDate', 'Due Date'),
  updated('updated', 'Updated'),
  newest('newest', 'Newest');

  const SortOrder(this.json, this.label);
  final String json;
  final String label;

  /// Direction applied when this order is first picked (SPEC §5.3).
  SortDirection get defaultDirection => switch (this) {
    manual || priority || dueDate => SortDirection.asc,
    updated || newest => SortDirection.desc,
  };
}

enum SortDirection { asc, desc }

enum BoardLayout { board, list }

enum DisplayProperty { id, statusIcon, priority, startDate, dueDate, labels, project }

enum DueFilter {
  overdue('overdue', 'Overdue'),
  today('today', 'Due Today'),
  week('week', 'Due in Next 7 Days'),
  none('none', 'No Due Date');

  const DueFilter(this.json, this.label);
  final String json;
  final String label;
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

Map<String, Object?> _extra(Map<String, Object?> json, Set<String> known) => {
  for (final e in json.entries)
    if (!known.contains(e.key)) e.key: e.value,
};

T _req<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Missing or invalid "$key"');
}

T _opt<T>(Map<String, Object?> json, String key, T fallback) {
  final value = json[key];
  return value is T ? value : fallback;
}

double _double(Map<String, Object?> json, String key) => switch (json[key]) {
  final num n => n.toDouble(),
  _ => 0,
};

DateTime _time(Map<String, Object?> json, String key) {
  final value = _req<String>(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid timestamp "$key": $value');
  return parsed;
}

DateTime? _timeOrNull(Map<String, Object?> json, String key) => json[key] == null ? null : _time(json, key);

String _timeJson(DateTime t) => t.toUtc().toIso8601String();

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) throw FormatException('"$key" must be a list');
  return [
    for (final item in value)
      if (item is Map<String, Object?>) item else throw FormatException('"$key" items must be objects'),
  ];
}

List<String> _strings(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String) v,
      ]
    : const [];

class Task {
  Task({
    required this.id,
    required this.number,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = Priority.none,
    this.startDate,
    this.dueDate,
    List<String> labelIds = const [],
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    Map<String, Object?> extra = const {},
  }) : labelIds = List.unmodifiable(labelIds),
       extra = Map.unmodifiable(extra);

  static const _known = {
    'id',
    'number',
    'title',
    'description',
    'status',
    'priority',
    'startDate',
    'dueDate',
    'labelIds', //
    'sortOrder', 'createdAt', 'updatedAt', 'completedAt',
  };

  factory Task.fromJson(Map<String, Object?> json) {
    final createdAt = _time(json, 'createdAt');
    return Task(
      id: _req<String>(json, 'id'),
      number: _req<int>(json, 'number'),
      title: _req<String>(json, 'title'),
      description: _opt(json, 'description', ''),
      status: TaskStatus.fromJson(json['status']),
      priority: Priority.fromJson(json['priority'] ?? 0),
      startDate: LocalDate.fromJson(json['startDate']),
      dueDate: LocalDate.fromJson(json['dueDate']),
      labelIds: _strings(json['labelIds']),
      sortOrder: _double(json, 'sortOrder'),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null ? createdAt : _time(json, 'updatedAt'),
      completedAt: _timeOrNull(json, 'completedAt'),
      extra: _extra(json, _known),
    );
  }

  final String id;
  final int number;
  final String title;
  final String description;
  final TaskStatus status;
  final Priority priority;
  final LocalDate? startDate;
  final LocalDate? dueDate;
  final List<String> labelIds;
  final double sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final Map<String, Object?> extra;

  bool get isDone => status == TaskStatus.done;

  Task copyWith({
    String? id,
    int? number,
    String? title,
    String? description,
    TaskStatus? status,
    Priority? priority,
    Object? startDate = _unset,
    Object? dueDate = _unset,
    List<String>? labelIds,
    double? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _unset,
  }) => Task(
    id: id ?? this.id,
    number: number ?? this.number,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    startDate: startDate == _unset ? this.startDate : startDate as LocalDate?,
    dueDate: dueDate == _unset ? this.dueDate : dueDate as LocalDate?,
    labelIds: labelIds ?? this.labelIds,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: completedAt == _unset ? this.completedAt : completedAt as DateTime?,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'number': number,
    'title': title,
    'description': description,
    'status': status.json,
    'priority': priority.value,
    'startDate': startDate?.toJson(),
    'dueDate': dueDate?.toJson(),
    'labelIds': labelIds,
    'sortOrder': sortOrder,
    'createdAt': _timeJson(createdAt),
    'updatedAt': _timeJson(updatedAt),
    'completedAt': completedAt == null ? null : _timeJson(completedAt!),
  };
}

class Label {
  Label({required this.id, required this.name, required this.color, Map<String, Object?> extra = const {}})
    : extra = Map.unmodifiable(extra);

  static const maxNameLength = 40;
  static const _known = {'id', 'name', 'color'};

  factory Label.fromJson(Map<String, Object?> json) => Label(
    id: _req<String>(json, 'id'),
    name: _req<String>(json, 'name'),
    color: TaskletColor.fromJson(json['color']),
    extra: _extra(json, _known),
  );

  final String id;
  final String name;
  final TaskletColor color;
  final Map<String, Object?> extra;

  Label copyWith({String? name, TaskletColor? color}) =>
      Label(id: id, name: name ?? this.name, color: color ?? this.color, extra: extra);

  Map<String, Object?> toJson() => {...extra, 'id': id, 'name': name, 'color': color.toJson()};
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.key,
    this.color = TaskletColor.blue,
    this.archived = false,
    this.favorite = false,
    this.sortOrder = 0,
    this.favoriteOrder = 0,
    List<Label> labels = const [],
    int? nextNumber,
    required this.createdAt,
    required this.updatedAt,
    List<Task> tasks = const [],
    Map<String, Object?> extra = const {},
  }) : labels = List.unmodifiable(labels),
       tasks = List.unmodifiable(tasks),
       // Never hand out a number already used by a task in this file, even if the stored counter is behind.
       nextNumber = [nextNumber ?? 1, for (final t in tasks) t.number + 1].reduce((a, b) => a > b ? a : b),
       extra = Map.unmodifiable(extra);

  /// The built-in "No Project" bucket (SPEC §2.3).
  factory Project.noProject(DateTime now) => Project(
    id: noProjectId,
    name: 'No Project',
    key: noProjectKey,
    color: TaskletColor.neutral,
    createdAt: now,
    updatedAt: now,
  );

  static const _known = {
    'id',
    'name',
    'key',
    'color',
    'archived',
    'favorite',
    'sortOrder',
    'favoriteOrder',
    'labels', //
    'nextNumber', 'createdAt', 'updatedAt', 'tasks',
  };

  factory Project.fromJson(Map<String, Object?> json) {
    final createdAt = _time(json, 'createdAt');
    return Project(
      id: _req<String>(json, 'id'),
      name: _req<String>(json, 'name'),
      key: _opt(json, 'key', ''),
      color: json['color'] == null ? TaskletColor.neutral : TaskletColor.fromJson(json['color']),
      archived: _opt(json, 'archived', false),
      favorite: _opt(json, 'favorite', false),
      sortOrder: _double(json, 'sortOrder'),
      favoriteOrder: _double(json, 'favoriteOrder'),
      labels: [for (final l in _objects(json, 'labels')) Label.fromJson(l)],
      nextNumber: _opt<int?>(json, 'nextNumber', null),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null ? createdAt : _time(json, 'updatedAt'),
      tasks: [for (final t in _objects(json, 'tasks')) Task.fromJson(t)],
      extra: _extra(json, _known),
    );
  }

  final String id;
  final String name;

  /// Task-ID prefix (SPEC §2.4). Empty only for a legacy file not yet assigned a key.
  final String key;
  final TaskletColor color;
  final bool archived;
  final bool favorite;
  final double sortOrder;
  final double favoriteOrder;
  final List<Label> labels;
  final int nextNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Task> tasks;
  final Map<String, Object?> extra;

  bool get isNoProject => id == noProjectId;

  Task? taskById(String taskId) {
    for (final t in tasks) {
      if (t.id == taskId) return t;
    }
    return null;
  }

  String displayIdOf(Task task) => '$key-${task.number}';

  Project copyWith({
    String? name,
    String? key,
    TaskletColor? color,
    bool? archived,
    bool? favorite,
    double? sortOrder,
    double? favoriteOrder,
    List<Label>? labels,
    int? nextNumber,
    DateTime? updatedAt,
    List<Task>? tasks,
  }) => Project(
    id: id,
    name: name ?? this.name,
    key: key ?? this.key,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    favorite: favorite ?? this.favorite,
    sortOrder: sortOrder ?? this.sortOrder,
    favoriteOrder: favoriteOrder ?? this.favoriteOrder,
    labels: labels ?? this.labels,
    nextNumber: nextNumber ?? this.nextNumber,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tasks: tasks ?? this.tasks,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'key': key,
    'color': color.toJson(),
    'archived': archived,
    'favorite': favorite,
    'sortOrder': sortOrder,
    'favoriteOrder': favoriteOrder,
    'labels': [for (final l in labels) l.toJson()],
    'nextNumber': nextNumber,
    'createdAt': _timeJson(createdAt),
    'updatedAt': _timeJson(updatedAt),
    'tasks': [for (final t in tasks) t.toJson()],
  };
}

/// Board/view filters (SPEC §6). An empty category means "don't filter on this".
class BoardFilters {
  BoardFilters({
    Set<TaskStatus> status = const {},
    Set<Priority> priorities = const {},
    Set<String> projects = const {},
    Set<String> labels = const {},
    Set<DueFilter> due = const {},
    Map<String, Object?> extra = const {},
  }) : status = Set.unmodifiable(status),
       priorities = Set.unmodifiable(priorities),
       projects = Set.unmodifiable(projects),
       labels = Set.unmodifiable(labels),
       due = Set.unmodifiable(due),
       extra = Map.unmodifiable(extra);

  static final empty = BoardFilters();
  static const _known = {'status', 'priorities', 'projects', 'labels', 'due'};

  /// Lenient: unknown values (e.g. from a newer version) are dropped rather than failing the whole file.
  factory BoardFilters.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return empty;
    final json = value;
    return BoardFilters(
      status: {
        for (final s in _strings(json['status']))
          for (final st in TaskStatus.values)
            if (st.json == s) st,
      },
      priorities: {
        if (json['priorities'] case final List<Object?> list)
          for (final p in list)
            for (final pr in Priority.values)
              if (pr.value == p) pr,
      },
      projects: _strings(json['projects']).toSet(),
      labels: _strings(json['labels']).toSet(),
      due: {
        for (final d in _strings(json['due']))
          for (final df in DueFilter.values)
            if (df.json == d) df,
      },
      extra: _extra(json, _known),
    );
  }

  final Set<TaskStatus> status;
  final Set<Priority> priorities;
  final Set<String> projects;
  final Set<String> labels;
  final Set<DueFilter> due;
  final Map<String, Object?> extra;

  /// Number of non-empty categories (SPEC §4.6 filter summary).
  int get activeCategoryCount => [status, priorities, projects, labels, due].where((c) => c.isNotEmpty).length;

  bool get isEmpty => activeCategoryCount == 0;

  BoardFilters copyWith({
    Set<TaskStatus>? status,
    Set<Priority>? priorities,
    Set<String>? projects,
    Set<String>? labels,
    Set<DueFilter>? due,
  }) => BoardFilters(
    status: status ?? this.status,
    priorities: priorities ?? this.priorities,
    projects: projects ?? this.projects,
    labels: labels ?? this.labels,
    due: due ?? this.due,
    extra: extra,
  );

  BoardFilters cleared() => BoardFilters(extra: extra);

  Map<String, Object?> toJson() => {
    ...extra,
    'status': [for (final s in status) s.json],
    'priorities': [for (final p in priorities) p.value],
    'projects': projects.toList(),
    'labels': labels.toList(),
    'due': [for (final d in due) d.json],
  };
}

/// Display options for a board (SPEC §5.3).
class ViewDisplay {
  ViewDisplay({
    this.order = SortOrder.manual,
    this.direction = SortDirection.asc,
    this.layout = BoardLayout.board,
    this.hideEmptySections = false,
    Set<DisplayProperty> properties = allProperties,
    Map<String, Object?> extra = const {},
  }) : properties = Set.unmodifiable(properties),
       extra = Map.unmodifiable(extra);

  static const allProperties = {...DisplayProperty.values};
  static const _known = {'order', 'direction', 'layout', 'hideEmptySections', 'properties'};

  /// Today's own defaults (SPEC §4.2): list layout, Priority and Start Date hidden.
  static final todayDefaults = ViewDisplay(
    layout: BoardLayout.list,
    properties: {...DisplayProperty.values}..removeAll({DisplayProperty.priority, DisplayProperty.startDate}),
  );

  factory ViewDisplay.fromJson(Map<String, Object?> json) => ViewDisplay(
    order: SortOrder.values.firstWhere((o) => o.json == json['order'], orElse: () => SortOrder.manual),
    direction: _byName(SortDirection.values, json['direction'], SortDirection.asc),
    layout: _byName(BoardLayout.values, json['layout'], BoardLayout.board),
    hideEmptySections: _opt(json, 'hideEmptySections', false),
    properties: json['properties'] is List
        ? {
            for (final p in _strings(json['properties']))
              for (final dp in DisplayProperty.values)
                if (dp.name == p) dp,
          }
        : allProperties,
    extra: _extra(json, _known),
  );

  final SortOrder order;
  final SortDirection direction;
  final BoardLayout layout;
  final bool hideEmptySections;
  final Set<DisplayProperty> properties;
  final Map<String, Object?> extra;

  bool shows(DisplayProperty p) => properties.contains(p);

  /// Picking an order also resets direction to that order's default (SPEC §5.3).
  ViewDisplay withOrder(SortOrder order) => copyWith(order: order, direction: order.defaultDirection);

  ViewDisplay copyWith({
    SortOrder? order,
    SortDirection? direction,
    BoardLayout? layout,
    bool? hideEmptySections,
    Set<DisplayProperty>? properties,
  }) => ViewDisplay(
    order: order ?? this.order,
    direction: direction ?? this.direction,
    layout: layout ?? this.layout,
    hideEmptySections: hideEmptySections ?? this.hideEmptySections,
    properties: properties ?? this.properties,
    extra: extra,
  );

  /// Same visible settings as [other] (ignores `extra`) — used for "Reset to Default" enablement.
  bool sameAs(ViewDisplay other) =>
      order == other.order &&
      direction == other.direction &&
      layout == other.layout &&
      hideEmptySections == other.hideEmptySections &&
      properties.length == other.properties.length &&
      properties.containsAll(other.properties);

  Map<String, Object?> toJson() => {
    ...extra,
    'order': order.json,
    'direction': direction.name,
    'layout': layout.name,
    'hideEmptySections': hideEmptySections,
    'properties': [
      for (final p in DisplayProperty.values)
        if (properties.contains(p)) p.name,
    ],
  };
}

class SavedView {
  SavedView({
    required this.id,
    required this.name,
    this.color = TaskletColor.blue,
    BoardFilters? filters,
    this.display,
    this.inSidebar = false,
    this.sidebarOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    Map<String, Object?> extra = const {},
  }) : filters = filters ?? BoardFilters.empty,
       extra = Map.unmodifiable(extra);

  static const _known = {
    'id',
    'name',
    'color',
    'filters',
    'display',
    'inSidebar',
    'sidebarOrder',
    'createdAt',
    'updatedAt', //
  };

  factory SavedView.fromJson(Map<String, Object?> json) {
    final createdAt = _time(json, 'createdAt');
    return SavedView(
      id: _req<String>(json, 'id'),
      name: _req<String>(json, 'name'),
      color: json['color'] == null ? TaskletColor.neutral : TaskletColor.fromJson(json['color']),
      filters: BoardFilters.fromJson(json['filters']),
      display: json['display'] is Map<String, Object?>
          ? ViewDisplay.fromJson(json['display']! as Map<String, Object?>)
          : null,
      inSidebar: _opt(json, 'inSidebar', false),
      sidebarOrder: _double(json, 'sidebarOrder'),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null ? createdAt : _time(json, 'updatedAt'),
      extra: _extra(json, _known),
    );
  }

  final String id;
  final String name;
  final TaskletColor color;
  final BoardFilters filters;

  /// Null means "use the defaults".
  final ViewDisplay? display;
  final bool inSidebar;
  final double sidebarOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> extra;

  SavedView copyWith({
    String? name,
    TaskletColor? color,
    BoardFilters? filters,
    Object? display = _unset,
    bool? inSidebar,
    double? sidebarOrder,
    DateTime? updatedAt,
  }) => SavedView(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    filters: filters ?? this.filters,
    display: display == _unset ? this.display : display as ViewDisplay?,
    inSidebar: inSidebar ?? this.inSidebar,
    sidebarOrder: sidebarOrder ?? this.sidebarOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'color': color.toJson(),
    'filters': filters.toJson(),
    'display': display?.toJson(),
    'inSidebar': inSidebar,
    'sidebarOrder': sidebarOrder,
    'createdAt': _timeJson(createdAt),
    'updatedAt': _timeJson(updatedAt),
  };
}

/// A project file the sync provider duplicated (SPEC §2.5). [file] is the untouched extra copy.
class SyncConflict {
  const SyncConflict({required this.file, required this.projectName});
  final String file;
  final String projectName;
}

/// A task together with the project that owns it.
class ProjectTask {
  const ProjectTask(this.project, this.task);
  final Project project;
  final Task task;

  String get displayId => project.displayIdOf(task);
}

/// Everything read from a data folder (SPEC §2.2).
class Workspace {
  Workspace({
    required this.folder,
    required List<Project> projects,
    required this.noProject,
    required this.noProjectOnDisk,
    List<Label> labels = const [],
    this.labelsReadable = true,
    List<SavedView> views = const [],
    this.viewsReadable = true,
    List<SyncConflict> conflicts = const [],
  }) : projects = List.unmodifiable(projects),
       labels = List.unmodifiable(labels),
       views = List.unmodifiable(views),
       conflicts = List.unmodifiable(conflicts);

  final String folder;

  /// Real projects (never includes the No-Project bucket).
  final List<Project> projects;

  /// The No-Project bucket; virtual (empty) until its file is first written.
  final Project noProject;
  final bool noProjectOnDisk;
  final List<Label> labels;
  final bool labelsReadable;
  final List<SavedView> views;
  final bool viewsReadable;
  final List<SyncConflict> conflicts;

  /// Real projects plus the No-Project bucket.
  Iterable<Project> get allProjects sync* {
    yield* projects;
    yield noProject;
  }

  Project? projectById(String id) {
    if (id == noProjectId) return noProject;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Tasks from non-archived projects plus No-Project tasks.
  Iterable<ProjectTask> get activeTasks sync* {
    for (final p in allProjects) {
      if (p.archived) continue;
      for (final t in p.tasks) {
        yield ProjectTask(p, t);
      }
    }
  }

  /// Labels a task in [project] may use: the project's own, then workspace-wide (SPEC §2.2).
  List<Label> labelsFor(Project project) => [...project.labels, ...labels];

  Label? labelById(String id) {
    for (final l in labels) {
      if (l.id == id) return l;
    }
    for (final p in projects) {
      for (final l in p.labels) {
        if (l.id == id) return l;
      }
    }
    return null;
  }

  Workspace copyWith({
    List<Project>? projects,
    Project? noProject,
    bool? noProjectOnDisk,
    List<Label>? labels,
    List<SavedView>? views,
    List<SyncConflict>? conflicts,
  }) => Workspace(
    folder: folder,
    projects: projects ?? this.projects,
    noProject: noProject ?? this.noProject,
    noProjectOnDisk: noProjectOnDisk ?? this.noProjectOnDisk,
    labels: labels ?? this.labels,
    labelsReadable: labelsReadable,
    views: views ?? this.views,
    viewsReadable: viewsReadable,
    conflicts: conflicts ?? this.conflicts,
  );
}
