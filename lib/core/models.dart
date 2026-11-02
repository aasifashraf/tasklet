import 'colors.dart';
import 'local_date.dart';

// Entities from SPEC §2.2.
//
// Forward compatibility (SPEC §2.5, docs/DECISIONS.md):
// - unrecognized fields are kept in `extra` and written back unchanged;
// - a list entry this version can't understand (e.g. a task with a status added by a newer Tasklet, or a
//   hand-edited task with a broken field) is kept verbatim as "opaque", hidden from the UI, and written back
//   unchanged, so one odd entry never hides the rest of its project;
// - an unknown color shows as neutral but its original value is written back until the user picks a color.
// Only damage to the file itself (invalid JSON, missing project id/name/createdAt) makes a whole file unreadable.

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

  static TaskStatus fromJson(Object? value) => values.firstWhere(
    (s) => s.json == value,
    orElse: () => throw FormatException('Unknown status: $value'),
  );
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

  static Priority fromJson(Object? value) => values.firstWhere(
    (p) => p.value == value,
    orElse: () => throw FormatException('Unknown priority: $value'),
  );
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

enum DisplayProperty {
  id,
  statusIcon,
  priority,
  startDate,
  dueDate,
  labels,
  project,
}

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

/// Non-finite values (e.g. `1e999` parses as Infinity) can't be written back as JSON, so they read as 0.
double _double(Map<String, Object?> json, String key) => switch (json[key]) {
  final num n when n.isFinite => n.toDouble(),
  _ => 0,
};

DateTime _time(Map<String, Object?> json, String key) {
  final value = _req<String>(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid timestamp "$key": $value');
  return parsed;
}

DateTime? _timeOrNull(Map<String, Object?> json, String key) =>
    json[key] == null ? null : _time(json, key);

String _timeJson(DateTime t) => t.toUtc().toIso8601String();

List<String> _strings(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String) v,
      ]
    : const [];

/// Color with forward compatibility: an unknown value displays as neutral and is remembered for write-back.
(TaskletColor, String?) _color(Map<String, Object?> json) {
  final raw = json['color'];
  if (raw == null) return (TaskletColor.neutral, null);
  final known = TaskletColor.tryParse(raw);
  if (known != null) return (known, null);
  if (raw is String) return (TaskletColor.neutral, raw);
  throw FormatException('Invalid color: $raw');
}

/// A project or label icon name; any other value (from a newer version) stays in `extra`, see [_iconKnown].
String? _icon(Map<String, Object?> json) => switch (json['icon']) {
  final String name => name,
  _ => null,
};

Set<String> _iconKnown(Map<String, Object?> json, Set<String> known) =>
    json['icon'] is String ? {...known, 'icon'} : known;

/// Entries of a JSON list that parse with [parse] and have a unique id, plus every other entry verbatim.
class LenientList<T> {
  LenientList(this.items, this.opaque);

  /// Parses [value] (a JSON list; null means empty). Throws only if [value] isn't a list at all.
  factory LenientList.parse(
    Object? value,
    T Function(Map<String, Object?>) parse,
    String Function(T) idOf,
  ) {
    if (value == null) return LenientList(const [], const []);
    if (value is! List) throw const FormatException('Expected a list');
    final items = <T>[];
    final opaque = <Object?>[];
    final seen = <String>{};
    for (final entry in value) {
      T? item;
      if (entry is Map<String, Object?>) {
        try {
          item = parse(entry);
        } on FormatException {
          item = null;
        }
      }
      if (item != null && seen.add(idOf(item))) {
        items.add(item);
      } else {
        opaque.add(entry);
      }
    }
    return LenientList(items, opaque);
  }

  final List<T> items;

  /// Entries this version doesn't understand (or duplicates of an id), preserved for write-back.
  final List<Object?> opaque;
}

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
      updatedAt: json['updatedAt'] == null
          ? createdAt
          : _time(json, 'updatedAt'),
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

  /// Local calendar days of [createdAt] and [completedAt], converted once per task instance: a timezone conversion
  /// per use was a measurable cost across 100k tasks (docs/SYSTEM_DESIGN.md, P1).
  late final LocalDate createdDay = LocalDate.fromDateTime(createdAt);
  late final LocalDate? completedDay = completedAt == null
      ? null
      : LocalDate.fromDateTime(completedAt!);

  /// Lowercased title + description for search, built on the first search and kept with this instance.
  late final String searchText = '$title\n$description'.toLowerCase();

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
    completedAt: completedAt == _unset
        ? this.completedAt
        : completedAt as DateTime?,
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
  Label({
    required this.id,
    required this.name,
    required this.color,
    this.unknownColor,
    this.icon,
    Map<String, Object?> extra = const {},
  }) : extra = Map.unmodifiable(extra);

  static const maxNameLength = 40;
  static const _known = {'id', 'name', 'color'};

  factory Label.fromJson(Map<String, Object?> json) {
    final (color, unknownColor) = _color(json);
    return Label(
      id: _req<String>(json, 'id'),
      name: _req<String>(json, 'name'),
      color: color,
      unknownColor: unknownColor,
      icon: _icon(json),
      extra: _extra(json, _iconKnown(json, _known)),
    );
  }

  final String id;
  final String name;
  final TaskletColor color;

  /// A color value from a newer version, written back until the user picks a color.
  final String? unknownColor;

  /// A Lucide icon name (lib/ui/icons); null draws the dot. A name this version doesn't know also draws the dot
  /// and is written back unchanged.
  final String? icon;
  final Map<String, Object?> extra;

  Label copyWith({
    String? name,
    TaskletColor? color,
    String? icon,
    bool clearIcon = false,
  }) => Label(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    unknownColor: color == null ? unknownColor : null,
    icon: clearIcon ? null : (icon ?? this.icon),
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'color': unknownColor ?? color.toJson(),
    if (icon != null) 'icon': icon,
  };
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.key,
    this.color = TaskletColor.blue,
    this.unknownColor,
    this.icon,
    this.archived = false,
    this.favorite = false,
    this.sortOrder = 0,
    this.favoriteOrder = 0,
    List<Label> labels = const [],
    int? nextNumber,
    required this.createdAt,
    required this.updatedAt,
    List<Task> tasks = const [],
    List<Object?> opaqueTasks = const [],
    List<Object?> opaqueLabels = const [],
    Map<String, Object?> extra = const {},
  }) : labels = List.unmodifiable(labels),
       tasks = List.unmodifiable(tasks),
       opaqueTasks = List.unmodifiable(opaqueTasks),
       opaqueLabels = List.unmodifiable(opaqueLabels),
       // Never hand out a number already used by any task in this file (including ones this version can't
       // display), even if the stored counter is behind.
       nextNumber = [
         nextNumber ?? 1,
         for (final t in tasks) t.number + 1,
         for (final o in opaqueTasks)
           if (o case {'number': final int n}) n + 1,
       ].reduce((a, b) => a > b ? a : b),
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
    final (color, unknownColor) = _color(json);
    final labels = LenientList.parse(
      json['labels'],
      Label.fromJson,
      (l) => l.id,
    );
    final tasks = LenientList.parse(json['tasks'], Task.fromJson, (t) => t.id);
    return Project(
      id: _req<String>(json, 'id'),
      name: _req<String>(json, 'name'),
      key: _opt(json, 'key', ''),
      color: color,
      unknownColor: unknownColor,
      icon: _icon(json),
      archived: _opt(json, 'archived', false),
      favorite: _opt(json, 'favorite', false),
      sortOrder: _double(json, 'sortOrder'),
      favoriteOrder: _double(json, 'favoriteOrder'),
      labels: labels.items,
      opaqueLabels: labels.opaque,
      nextNumber: _opt<int?>(json, 'nextNumber', null),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null
          ? createdAt
          : _time(json, 'updatedAt'),
      tasks: tasks.items,
      opaqueTasks: tasks.opaque,
      extra: _extra(json, _iconKnown(json, _known)),
    );
  }

  final String id;
  final String name;

  /// Task-ID prefix (SPEC §2.4). Empty only for a legacy file not yet assigned a key.
  final String key;
  final TaskletColor color;

  /// A color value from a newer version, written back until the user picks a color.
  final String? unknownColor;

  /// A Lucide icon name (lib/ui/icons); null draws the cube. A name this version doesn't know also draws the cube
  /// and is written back unchanged.
  final String? icon;
  final bool archived;
  final bool favorite;
  final double sortOrder;
  final double favoriteOrder;
  final List<Label> labels;
  final int nextNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Task> tasks;

  /// Task/label entries this version can't display; preserved verbatim on save.
  final List<Object?> opaqueTasks;
  final List<Object?> opaqueLabels;
  final Map<String, Object?> extra;

  bool get isNoProject => id == noProjectId;

  /// Entries hidden because they come from a newer version or are damaged.
  int get hiddenEntryCount => opaqueTasks.length + opaqueLabels.length;

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
    String? icon,
    bool clearIcon = false,
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
    unknownColor: color == null ? unknownColor : null,
    icon: clearIcon ? null : (icon ?? this.icon),
    archived: archived ?? this.archived,
    favorite: favorite ?? this.favorite,
    sortOrder: sortOrder ?? this.sortOrder,
    favoriteOrder: favoriteOrder ?? this.favoriteOrder,
    labels: labels ?? this.labels,
    nextNumber: nextNumber ?? this.nextNumber,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tasks: tasks ?? this.tasks,
    opaqueTasks: opaqueTasks,
    opaqueLabels: opaqueLabels,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'key': key,
    'color': unknownColor ?? color.toJson(),
    if (icon != null) 'icon': icon,
    'archived': archived,
    'favorite': favorite,
    'sortOrder': sortOrder,
    'favoriteOrder': favoriteOrder,
    'labels': [for (final l in labels) l.toJson(), ...opaqueLabels],
    'nextNumber': nextNumber,
    'createdAt': _timeJson(createdAt),
    'updatedAt': _timeJson(updatedAt),
    'tasks': [for (final t in tasks) t.toJson(), ...opaqueTasks],
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
    Map<String, List<Object?>> unknownValues = const {},
  }) : status = Set.unmodifiable(status),
       priorities = Set.unmodifiable(priorities),
       projects = Set.unmodifiable(projects),
       labels = Set.unmodifiable(labels),
       due = Set.unmodifiable(due),
       extra = Map.unmodifiable(extra),
       unknownValues = Map.unmodifiable(unknownValues);

  static final empty = BoardFilters();
  static const _known = {'status', 'priorities', 'projects', 'labels', 'due'};

  /// Lenient: values this version doesn't know (e.g. a status added by a newer version) don't filter here but are
  /// kept in [unknownValues] and written back, so a newer version still sees its filter.
  factory BoardFilters.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return empty;
    final json = value;
    final unknown = <String, List<Object?>>{};
    Set<T> parse<T>(String key, T? Function(Object?) known) {
      final result = <T>{};
      if (json[key] case final List<Object?> list) {
        for (final raw in list) {
          final v = known(raw);
          if (v != null) {
            result.add(v);
          } else {
            (unknown[key] ??= []).add(raw);
          }
        }
      }
      return result;
    }

    return BoardFilters(
      status: parse(
        'status',
        (s) => TaskStatus.values.where((st) => st.json == s).firstOrNull,
      ),
      priorities: parse(
        'priorities',
        (p) => Priority.values.where((pr) => pr.value == p).firstOrNull,
      ),
      projects: _strings(json['projects']).toSet(),
      labels: _strings(json['labels']).toSet(),
      due: parse(
        'due',
        (d) => DueFilter.values.where((df) => df.json == d).firstOrNull,
      ),
      extra: _extra(json, _known),
      unknownValues: unknown,
    );
  }

  /// Filter values from a newer version, by category key; preserved until the filters are cleared.
  final Map<String, List<Object?>> unknownValues;

  final Set<TaskStatus> status;
  final Set<Priority> priorities;
  final Set<String> projects;
  final Set<String> labels;
  final Set<DueFilter> due;
  final Map<String, Object?> extra;

  /// Number of non-empty categories (SPEC §4.6 filter summary).
  int get activeCategoryCount => [
    status,
    priorities,
    projects,
    labels,
    due,
  ].where((c) => c.isNotEmpty).length;

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
    unknownValues: unknownValues,
  );

  BoardFilters cleared() => BoardFilters(extra: extra);

  Map<String, Object?> toJson() => {
    ...extra,
    'status': [for (final s in status) s.json, ...?unknownValues['status']],
    'priorities': [
      for (final p in priorities) p.value,
      ...?unknownValues['priorities'],
    ],
    'projects': projects.toList(),
    'labels': labels.toList(),
    'due': [for (final d in due) d.json, ...?unknownValues['due']],
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
  static const _known = {
    'order',
    'direction',
    'layout',
    'hideEmptySections',
    'properties',
  };

  /// Today's own defaults (SPEC §4.2): list layout, Priority and Start Date hidden.
  static final todayDefaults = ViewDisplay(
    layout: BoardLayout.list,
    properties: {...DisplayProperty.values}
      ..removeAll({DisplayProperty.priority, DisplayProperty.startDate}),
  );

  factory ViewDisplay.fromJson(Map<String, Object?> json) => ViewDisplay(
    order: SortOrder.values.firstWhere(
      (o) => o.json == json['order'],
      orElse: () => SortOrder.manual,
    ),
    direction: _byName(
      SortDirection.values,
      json['direction'],
      SortDirection.asc,
    ),
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
  ViewDisplay withOrder(SortOrder order) =>
      copyWith(order: order, direction: order.defaultDirection);

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

  /// Same visible settings as [other] (ignores `extra`), used for "Reset to Default" enablement.
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
    this.unknownColor,
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
    final (color, unknownColor) = _color(json);
    return SavedView(
      id: _req<String>(json, 'id'),
      name: _req<String>(json, 'name'),
      color: color,
      unknownColor: unknownColor,
      filters: BoardFilters.fromJson(json['filters']),
      display: json['display'] is Map<String, Object?>
          ? ViewDisplay.fromJson(json['display']! as Map<String, Object?>)
          : null,
      inSidebar: _opt(json, 'inSidebar', false),
      sidebarOrder: _double(json, 'sidebarOrder'),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null
          ? createdAt
          : _time(json, 'updatedAt'),
      extra: _extra(json, _known),
    );
  }

  final String id;
  final String name;
  final TaskletColor color;

  /// A color value from a newer version, written back until the user picks a color.
  final String? unknownColor;
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
    unknownColor: color == null ? unknownColor : null,
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
    'color': unknownColor ?? color.toJson(),
    'filters': filters.toJson(),
    'display': display?.toJson(),
    'inSidebar': inSidebar,
    'sidebarOrder': sidebarOrder,
    'createdAt': _timeJson(createdAt),
    'updatedAt': _timeJson(updatedAt),
  };
}

/// A file the sync provider duplicated (SPEC §2.5). [file] is the extra copy, always left untouched.
class SyncConflict {
  const SyncConflict({
    required this.file,
    required this.projectName,
    this.mainFileMissing = false,
  });
  final String file;

  /// The project's name, or "Labels" / "Quick Filters" for copies of labels.json / views.json.
  final String projectName;

  /// The canonical file doesn't exist, so this copy's contents are shown; the first edit recreates the canonical
  /// file and the copy stays untouched.
  final bool mainFileMissing;
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
    this.readOnly = false,
    this.hiddenEntryCount = 0,
    List<String> repairs = const [],
  }) : projects = List.unmodifiable(projects),
       labels = List.unmodifiable(labels),
       views = List.unmodifiable(views),
       conflicts = List.unmodifiable(conflicts),
       repairs = List.unmodifiable(repairs);

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

  /// The folder was written by a newer Tasklet format (or its marker is unreadable right now): show everything,
  /// save nothing.
  final bool readOnly;

  /// Tasks, labels and views hidden because they come from a newer version or are damaged (preserved on disk).
  final int hiddenEntryCount;

  /// What the read that produced this snapshot repaired and saved (duplicate task numbers or tasks), in plain
  /// words for a notice. Empty for snapshots made by edits.
  final List<String> repairs;

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

  /// The task with [taskId] wherever it lives now (it may have moved project since a reference was taken).
  ProjectTask? findTask(String taskId) {
    for (final p in allProjects) {
      final t = p.taskById(taskId);
      if (t != null) return ProjectTask(p, t);
    }
    return null;
  }

  /// Every label (workspace first, so its id wins a clash) by id. Built once per workspace snapshot.
  late final Map<String, Label> _labelsById = {
    for (final p in projects.reversed)
      for (final l in p.labels.reversed) l.id: l,
    for (final l in labels.reversed) l.id: l,
  };

  Label? labelById(String id) => _labelsById[id];

  /// How many tasks carry each label id, counted in one pass. Built once per workspace snapshot.
  late final Map<String, int> labelUsage = () {
    final counts = <String, int>{};
    for (final p in allProjects) {
      for (final t in p.tasks) {
        for (final id in t.labelIds) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
    }
    return counts;
  }();

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
    readOnly: readOnly,
    hiddenEntryCount: hiddenEntryCount,
  );
}
