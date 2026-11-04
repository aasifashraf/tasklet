import 'local_date.dart';
import 'models.dart';

// CSV import and export (docs/DECISIONS.md D17). RFC 4180: comma separated, fields with a comma, quote or line
// break are quoted, quotes doubled; reading also accepts a UTF-8 BOM, CRLF or LF, and semicolons when the header
// uses them (spreadsheets in some locales).

/// Rows of [text]; the first row is the header.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final sep =
      ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      quoted = true;
    } else if (c == sep) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.isNotEmpty)) rows.add(row);
  return rows;
}

String _quote(String value) =>
    value.contains(RegExp(r'[",\r\n]')) || value != value.trim()
    ? '"${value.replaceAll('"', '""')}"'
    : value;

/// One row per task: ID, title, description, status, priority, project, labels (comma separated), start, due,
/// created, completed. CRLF line ends and a BOM, so Excel opens it as UTF-8.
String tasksToCsv(Workspace ws, Iterable<ProjectTask> tasks) {
  final lines = [
    'ID,Title,Description,Status,Priority,Project,Labels,Start Date,Due Date,Created,Completed',
    for (final e in tasks)
      [
        e.displayId,
        e.task.title,
        e.task.description,
        e.task.status.label,
        e.task.priority == Priority.none ? '' : e.task.priority.label,
        e.project.isNoProject ? '' : e.project.name,
        [for (final id in e.task.labelIds) ?ws.labelById(id)?.name].join(', '),
        e.task.startDate?.toString() ?? '',
        e.task.dueDate?.toString() ?? '',
        e.task.createdAt.toUtc().toIso8601String(),
        e.task.completedAt?.toUtc().toIso8601String() ?? '',
      ].map(_quote).join(','),
  ];
  return '﻿${lines.join('\r\n')}\r\n';
}

/// A task read from a CSV row, before it is given an id, number and project.
class ImportedTask {
  const ImportedTask({
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = Priority.none,
    this.due,
    this.start,
    this.labels = const [],
    this.project,
  });
  final String title;
  final String description;
  final TaskStatus status;
  final Priority priority;
  final LocalDate? due;
  final LocalDate? start;

  /// Label names; matched to existing labels (case-insensitively) or created.
  final List<String> labels;

  /// Project name from the file, if it has one.
  final String? project;
}

/// The column names each field is read from (lowercase): Tasklet's own export, Todoist's and Linear's CSV exports
/// and the obvious ones.
const _columns = {
  'title': ['title', 'name', 'content', 'task', 'summary'],
  'description': ['description', 'notes', 'body', 'details'],
  'status': ['status', 'state', 'completed'],
  'priority': ['priority'],
  'due': ['due date', 'due', 'date', 'deadline'],
  'start': ['start date', 'start'],
  'labels': ['labels', 'label', 'tags'],
  'project': ['project', 'list'],
};

/// Tasks from a CSV file; rows without a title are skipped. Null when no column looks like a title.
List<ImportedTask>? importTasks(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) return null;
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  int? col(String field) {
    for (final name in _columns[field]!) {
      final i = header.indexOf(name);
      if (i >= 0) return i;
    }
    return null;
  }

  final title = col('title');
  if (title == null) return null;
  // Todoist's CSV mixes in section and note rows; only tasks are imported.
  final type = header.indexOf('type');
  final c = {for (final f in _columns.keys) f: col(f)};
  String at(List<String> row, String field) {
    final i = c[field];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  return [
    for (final row in rows.skip(1))
      if (at(row, 'title').isNotEmpty &&
          (type < 0 ||
              type >= row.length ||
              row[type].trim().toLowerCase() == 'task'))
        ImportedTask(
          title: at(row, 'title'),
          description: at(row, 'description'),
          status: _status(at(row, 'status')),
          priority: _priority(at(row, 'priority')),
          due: _date(at(row, 'due')),
          start: _date(at(row, 'start')),
          labels: [
            for (final l in at(row, 'labels').split(RegExp(r'[,;]')))
              if (l.trim().isNotEmpty) l.trim().replaceFirst('@', ''),
          ],
          project: at(row, 'project').isEmpty ? null : at(row, 'project'),
        ),
  ];
}

TaskStatus _status(String v) => switch (v.toLowerCase()) {
  'done' ||
  'completed' ||
  'complete' ||
  'closed' ||
  'true' ||
  'yes' => TaskStatus.done,
  'in progress' || 'started' || 'doing' || 'in review' => TaskStatus.inProgress,
  'backlog' || 'icebox' || 'someday' => TaskStatus.backlog,
  _ => TaskStatus.todo,
};

/// Tasklet's and Linear's names, and Todoist's 1-4 / p1-p4 where 1 is the highest (Todoist's CSV format). Todoist's
/// 4 (p4) is its default, "no priority".
Priority _priority(String v) => switch (v.toLowerCase()) {
  'urgent' || 'p1' || '1' => Priority.urgent,
  'high' || 'p2' || '2' => Priority.high,
  'medium' || 'normal' || 'p3' || '3' => Priority.medium,
  'low' => Priority.low,
  _ => Priority.none,
};

LocalDate? _date(String v) {
  if (v.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (iso != null) {
    return _valid(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final parsed = DateTime.tryParse(v);
  return parsed == null ? null : LocalDate.fromDateTime(parsed);
}

LocalDate? _valid(int y, int m, int d) {
  final date = DateTime.utc(y, m, d);
  return date.month == m && date.day == d ? LocalDate(y, m, d) : null;
}
