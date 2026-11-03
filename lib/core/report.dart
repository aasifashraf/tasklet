import 'package:intl/intl.dart';

import 'dates.dart';
import 'local_date.dart';
import 'models.dart';

// Reports (SPEC §4.9): pick tasks by period and filters, then build simplified, AI-ready JSON.

enum PeriodPreset {
  thisWeek('This Week'),
  lastWeek('Last Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  last30Days('Last 30 Days'),
  allTime('All Time'),
  custom('Custom Range');

  const PeriodPreset(this.label);
  final String label;
}

/// An inclusive date range with a display name.
/// Longest description copied into the report JSON. Longer ones are cut and end with "…", so one huge description
/// can't crowd the rest of a prompt out.
const reportDescriptionLimit = 1000;

/// A task description as the report shows it: trimmed and at most [reportDescriptionLimit] characters.
String reportDescription(String description) {
  final d = description.trim();
  if (d.length <= reportDescriptionLimit) return d;
  var end = reportDescriptionLimit;
  // Never split a surrogate pair (an emoji) in half.
  final unit = d.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end--;
  return '${d.substring(0, end).trimRight()}…';
}

class ReportPeriod {
  const ReportPeriod(this.from, this.to, this.name);
  final LocalDate from;
  final LocalDate to;
  final String name;

  bool contains(LocalDate d) => !d.isBefore(from) && !d.isAfter(to);
  int get days => from.daysUntil(to) + 1;
}

/// "All Time" spans year 1 → 9999 internally (SPEC §4.9).
final allTimeFrom = LocalDate(1, 1, 1);
final allTimeTo = LocalDate(9999, 12, 31);

ReportPeriod periodFor(
  PeriodPreset preset,
  LocalDate today, {
  required int firstDayOfWeek,
  LocalDate? customFrom,
  LocalDate? customTo,
}) {
  switch (preset) {
    case PeriodPreset.thisWeek:
      final start = startOfWeek(today, firstDayOfWeek);
      return ReportPeriod(start, start.addDays(6), preset.label);
    case PeriodPreset.lastWeek:
      final start = startOfWeek(today, firstDayOfWeek).addDays(-7);
      return ReportPeriod(start, start.addDays(6), preset.label);
    case PeriodPreset.thisMonth:
      return ReportPeriod(startOfMonth(today), endOfMonth(today), preset.label);
    case PeriodPreset.lastMonth:
      final lastMonthDay = startOfMonth(today).addDays(-1);
      return ReportPeriod(
        startOfMonth(lastMonthDay),
        lastMonthDay,
        preset.label,
      );
    case PeriodPreset.last30Days:
      return ReportPeriod(today.addDays(-29), today, preset.label);
    case PeriodPreset.allTime:
      return ReportPeriod(allTimeFrom, allTimeTo, preset.label);
    case PeriodPreset.custom:
      final from = customFrom ?? today;
      final to = customTo ?? today;
      return from.isAfter(to)
          ? ReportPeriod(to, from, preset.label)
          : ReportPeriod(from, to, preset.label);
  }
}

/// The Reports filter card's state.
class ReportFilters {
  const ReportFilters({
    this.projectIds = const {},
    this.includeArchived = false,
    this.labelIds = const {},
    this.statuses = const {},
    this.priorities = const {},
  });

  /// Empty = all projects (active, plus archived when [includeArchived]). May contain [noProjectId].
  final Set<String> projectIds;
  final bool includeArchived;
  final Set<String> labelIds;
  final Set<TaskStatus> statuses;
  final Set<Priority> priorities;
}

/// Projects whose tasks the report can include.
List<Project> reportProjects(Workspace ws, ReportFilters f) {
  final pool = [
    for (final p in ws.projects)
      if (!p.archived || f.includeArchived) p,
    ws.noProject,
  ];
  if (f.projectIds.isEmpty) return pool;
  return [
    for (final p in pool)
      if (f.projectIds.contains(p.id)) p,
  ];
}

LocalDate _day(DateTime t) => LocalDate.fromDateTime(t);

/// The day a done task was completed. A done task without `completedAt` (written by another tool) counts as
/// completed when it was last updated, rather than as open forever.
LocalDate? _completedDay(Task t) =>
    t.isDone ? (t.completedDay ?? _day(t.updatedAt)) : null;

/// A period's bounds as instants (local midnight at its start, and after its last day), so tasks can be compared
/// by timestamp without a timezone conversion each (docs/SYSTEM_DESIGN.md, P1).
typedef _Bounds = ({DateTime from, DateTime until});

_Bounds _boundsOf(ReportPeriod p) =>
    (from: p.from.toLocalDateTime(), until: p.to.addDays(1).toLocalDateTime());

/// A task qualifies if it overlaps the period in ANY way (SPEC §4.9): open at some point during it, completed in
/// it, or its start or due date falls in it.
bool inRange(Task t, ReportPeriod period) =>
    _inRange(t, period, _boundsOf(period));

bool _inRange(Task t, ReportPeriod period, _Bounds b) {
  // Same rule as comparing local days: created on or before the last day, completed on or after the first.
  final completed = t.isDone ? (t.completedAt ?? t.updatedAt) : null;
  final openDuring =
      t.createdAt.isBefore(b.until) &&
      (completed == null || !completed.isBefore(b.from));
  return openDuring ||
      (completed != null &&
          !completed.isBefore(b.from) &&
          completed.isBefore(b.until)) ||
      (t.startDate != null && period.contains(t.startDate!)) ||
      (t.dueDate != null && period.contains(t.dueDate!));
}

/// Tasks the report covers.
List<ProjectTask> reportTasks(
  Workspace ws,
  ReportFilters f,
  ReportPeriod period,
) {
  final bounds = _boundsOf(period);
  return [
    for (final p in reportProjects(ws, f))
      for (final t in p.tasks)
        if (_inRange(t, period, bounds) &&
            (f.statuses.isEmpty || f.statuses.contains(t.status)) &&
            (f.priorities.isEmpty || f.priorities.contains(t.priority)) &&
            (f.labelIds.isEmpty || t.labelIds.any(f.labelIds.contains)))
          ProjectTask(p, t),
  ];
}

/// Builds the simplified JSON (SPEC §4.9): no UUIDs, names instead of ids, YYYY-MM-DD dates, and every
/// empty/zero/not-applicable field omitted. Totals are pre-computed.
Map<String, Object?> buildReportJson({
  required Workspace ws,
  required ReportFilters filters,
  required ReportPeriod period,
  required LocalDate today,
}) {
  final tasks = reportTasks(ws, filters, period);

  // "All Time" is reported as the actual earliest-task-to-today span.
  var span = period;
  if (period.from == allTimeFrom && period.to == allTimeTo) {
    final earliest = tasks.isEmpty
        ? today
        : tasks
              .map((e) => e.task.createdDay)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    span = ReportPeriod(
      earliest.isAfter(today) ? today : earliest,
      today,
      period.name,
    );
  }

  final labelNames = <String, String>{
    for (final l in ws.labels) l.id: l.name,
    for (final p in ws.allProjects)
      for (final l in p.labels) l.id: l.name,
  };
  final projects = reportProjects(ws, filters);
  final nameCounts = <String, int>{};
  for (final p in projects) {
    nameCounts[p.name] = (nameCounts[p.name] ?? 0) + 1;
  }
  String projectName(Project p) =>
      (nameCounts[p.name] ?? 0) > 1 ? '${p.name} (${p.key})' : p.name;

  final taskJson = <String, List<Map<String, Object?>>>{};
  final stats = _Stats();
  final perProject = <String, _Stats>{};
  for (final e in tasks) {
    final s = perProject.putIfAbsent(e.project.id, _Stats.new);
    final json = _taskJson(e.task, span, today, labelNames, [stats, s]);
    (taskJson[e.project.id] ??= []).add(json);
  }

  final usedFilters = <String, Object?>{
    if (filters.projectIds.isNotEmpty)
      'projects': [for (final p in projects) projectName(p)],
    if (filters.labelIds.isNotEmpty)
      'labels': [for (final id in filters.labelIds) ?labelNames[id]],
    if (filters.statuses.isNotEmpty)
      'status': [for (final s in filters.statuses) s.label],
    if (filters.priorities.isNotEmpty)
      'priority': [for (final p in filters.priorities) p.label],
  };

  return _compact({
        'report': {
          'today': today.toString(),
          'period': {
            'from': span.from.toString(),
            'to': span.to.toString(),
            'name': span.name,
          },
          'filters': usedFilters,
          'includesArchivedProjects': filters.includeArchived,
        },
        'totals': stats.toJson(full: true),
        'timeline': _timeline(tasks.map((e) => e.task).toList(), span),
        'projects': [
          for (final p in projects)
            if (taskJson[p.id] != null)
              {
                'name': projectName(p),
                'key': p.key,
                'archived': p.archived,
                'totals': perProject[p.id]!.toJson(full: false),
                'tasks': taskJson[p.id],
              },
        ],
      })!
      as Map<String, Object?>;
}

class _Stats {
  int tasks = 0,
      completedIn = 0,
      createdIn = 0,
      dueIn = 0,
      openAtEnd = 0,
      completedAfter = 0,
      openNow = 0;
  int overdueNow = 0;
  final daysToComplete = <int>[];
  final byStatus = <String, int>{};
  final byPriority = <String, int>{};
  final byLabel = <String, int>{};

  Map<String, Object?> toJson({required bool full}) => {
    'tasks': tasks,
    'completedInPeriod': completedIn,
    if (full) 'createdInPeriod': createdIn,
    if (full) 'dueInPeriod': dueIn,
    'openAtPeriodEnd': openAtEnd,
    if (full) 'completedAfterPeriod': completedAfter,
    'openNow': openNow,
    'overdueNow': overdueNow,
    if (full && daysToComplete.isNotEmpty)
      'averageDaysToCompleteInPeriod': double.parse(
        (daysToComplete.reduce((a, b) => a + b) / daysToComplete.length)
            .toStringAsFixed(1),
      ),
    if (full)
      'byStatusNow': {
        for (final s in TaskStatus.values) s.label: ?byStatus[s.label],
      },
    if (full)
      'byPriority': {
        for (final p in [
          Priority.urgent,
          Priority.high,
          Priority.medium,
          Priority.low,
          Priority.none,
        ])
          p.label: ?byPriority[p.label],
      },
    if (full) 'byLabel': byLabel,
  };
}

Map<String, Object?> _taskJson(
  Task t,
  ReportPeriod span,
  LocalDate today,
  Map<String, String> labelNames,
  List<_Stats> stats,
) {
  final created = t.createdDay;
  final completed = _completedDay(t);
  final atEnd = created.isAfter(span.to)
      ? 'not created yet'
      : (completed != null && !completed.isAfter(span.to) ? 'done' : 'open');
  final inPeriod = [
    if (span.contains(created)) 'created',
    if (t.startDate != null && span.contains(t.startDate!)) 'started',
    if (t.dueDate != null && span.contains(t.dueDate!)) 'due',
    if (completed != null && span.contains(completed)) 'completed',
  ];
  // Clock differences between computers can put completion before creation; never report negative days.
  final daysToComplete = completed == null
      ? null
      : created.daysUntil(completed).clamp(0, 1 << 31);
  final overdueBy = !t.isDone && t.dueDate != null && t.dueDate!.isBefore(today)
      ? t.dueDate!.daysUntil(today)
      : 0;
  final labels = [for (final id in t.labelIds) ?labelNames[id]];

  for (final s in stats) {
    s.tasks++;
    if (inPeriod.contains('completed')) {
      s.completedIn++;
      if (daysToComplete != null) s.daysToComplete.add(daysToComplete);
    }
    if (inPeriod.contains('created')) s.createdIn++;
    if (inPeriod.contains('due')) s.dueIn++;
    if (atEnd == 'open') s.openAtEnd++;
    if (completed != null && completed.isAfter(span.to)) s.completedAfter++;
    if (!t.isDone) s.openNow++;
    if (overdueBy > 0) s.overdueNow++;
    s.byStatus[t.status.label] = (s.byStatus[t.status.label] ?? 0) + 1;
    s.byPriority[t.priority.label] = (s.byPriority[t.priority.label] ?? 0) + 1;
    for (final l in labels) {
      s.byLabel[l] = (s.byLabel[l] ?? 0) + 1;
    }
  }

  return {
    'title': t.title,
    'description': reportDescription(t.description),
    'atPeriodEnd': atEnd,
    'inPeriod': inPeriod,
    'statusNow': t.status.label,
    'priority': t.priority == Priority.none ? null : t.priority.label,
    'labels': labels,
    'startDate': t.startDate?.toString(),
    'dueDate': t.dueDate?.toString(),
    'created': created.toString(),
    'completed': completed?.toString(),
    'daysToComplete': daysToComplete,
    'overdueNowByDays': overdueBy,
  };
}

final _monthLabel = DateFormat('MMM y');
final _weekLabel = DateFormat('MMM d');

/// Month buckets when the span covers more than ~45 days; week buckets when it is ~10–130 days. Each bucket is
/// clipped to the report span. A range longer than two years is first narrowed to the days its tasks actually
/// touch, so a very wide custom range can't produce thousands of empty buckets.
Map<String, Object?> _timeline(List<Task> tasks, ReportPeriod period) {
  LocalDate maxOf(LocalDate a, LocalDate b) => a.isAfter(b) ? a : b;
  LocalDate minOf(LocalDate a, LocalDate b) => a.isBefore(b) ? a : b;

  var span = period;
  if (period.days > 731) {
    final touched = [
      for (final t in tasks) ...[
        t.createdDay,
        ?_completedDay(t),
        ?t.startDate,
        ?t.dueDate,
      ],
    ];
    if (touched.isEmpty) return {'months': const [], 'weeks': const []};
    span = ReportPeriod(
      maxOf(period.from, touched.reduce(minOf)),
      minOf(period.to, touched.reduce(maxOf)),
      period.name,
    );
  }

  final days = span.days;
  List<Map<String, Object?>> buckets(List<ReportPeriod> ranges) => [
    for (final r in ranges)
      {
        'label': r.name,
        'created': tasks.where((t) => r.contains(t.createdDay)).length,
        'completed': tasks.where((t) {
          final completed = _completedDay(t);
          return completed != null && r.contains(completed);
        }).length,
        'due': tasks
            .where((t) => t.dueDate != null && r.contains(t.dueDate!))
            .length,
        'openAtEnd': tasks.where((t) {
          final completed = _completedDay(t);
          return !t.createdDay.isAfter(r.to) &&
              (completed == null || completed.isAfter(r.to));
        }).length,
      },
  ];

  final months = <ReportPeriod>[];
  if (days > 45) {
    for (
      var m = startOfMonth(span.from);
      !m.isAfter(span.to);
      m = endOfMonth(m).addDays(1)
    ) {
      months.add(
        ReportPeriod(
          maxOf(m, span.from),
          minOf(endOfMonth(m), span.to),
          _monthLabel.format(m.toLocalDateTime()),
        ),
      );
    }
  }
  final weeks = <ReportPeriod>[];
  if (days >= 10 && days <= 130) {
    for (var w = span.from; !w.isAfter(span.to); w = w.addDays(7)) {
      weeks.add(
        ReportPeriod(
          w,
          minOf(w.addDays(6), span.to),
          'Week of ${_weekLabel.format(w.toLocalDateTime())}',
        ),
      );
    }
  }
  return {'months': buckets(months), 'weeks': buckets(weeks)};
}

/// Recursively drops null, false, 0, empty strings, empty lists and empty maps (SPEC §4.9 "omit empty").
/// Bucket labels and other non-empty values are kept.
Object? _compact(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      final v = _compact(e.value);
      if (v != null) out[e.key as String] = v;
    }
    return out.isEmpty ? null : out;
  }
  if (value is List) {
    final out = [for (final v in value) ?_compact(v)];
    return out.isEmpty ? null : out;
  }
  if (value == null ||
      value == false ||
      value == 0 ||
      (value is String && value.isEmpty)) {
    return null;
  }
  return value;
}
