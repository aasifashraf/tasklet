import 'models.dart';

/// Help > Export Diagnostics: a plain-text report a user can attach to a bug report. Only versions, counts, sizes
/// and the error log: never task titles or descriptions, or project, label, quick-filter or workspace names.
String diagnosticsReport({
  required DateTime now,
  required String appVersion,
  required String os,
  required String dart,
  required int workspaceCount,
  required Workspace? workspace,
  required String? syncedBy,
  required Map<String, int> fileSizes,
  required String log,
}) {
  final out = StringBuffer()
    ..writeln('Tasklet diagnostics')
    ..writeln('Created: ${now.toIso8601String()}')
    ..writeln(
      'Contains versions, counts, file sizes and the error log; no task text and no project, label or '
      'workspace names. Error messages in the log can include file paths.',
    )
    ..writeln()
    ..writeln('== App')
    ..writeln('Tasklet: $appVersion')
    ..writeln('OS: $os')
    ..writeln('Dart: $dart')
    ..writeln('Workspaces on this computer: $workspaceCount')
    ..writeln();

  final ws = workspace;
  out.writeln('== Open workspace');
  if (ws == null) {
    out.writeln('None open.');
  } else {
    var tasks = 0, done = 0, largest = 0;
    for (final p in ws.allProjects) {
      tasks += p.tasks.length;
      done += p.tasks.where((t) => t.isDone).length;
      if (p.tasks.length > largest) largest = p.tasks.length;
    }
    final archived = ws.projects.where((p) => p.archived).length;
    final projectLabels = ws.projects.fold(0, (n, p) => n + p.labels.length);
    out
      ..writeln('Synced by: ${syncedBy ?? 'not detected'}')
      ..writeln('Read-only: ${ws.readOnly ? 'yes' : 'no'}')
      ..writeln('Projects: ${ws.projects.length} ($archived archived)')
      ..writeln('Tasks: $tasks (${tasks - done} open, $done done)')
      ..writeln('No Project tasks: ${ws.noProject.tasks.length}')
      ..writeln('Largest project: $largest tasks')
      ..writeln(
        'Workspace labels: ${ws.labels.length}'
        '${ws.labelsReadable ? '' : ' (labels.json unreadable)'}',
      )
      ..writeln('Project labels: $projectLabels')
      ..writeln(
        'Quick filters: ${ws.views.length}'
        '${ws.viewsReadable ? '' : ' (views.json unreadable)'}',
      )
      ..writeln(
        'Hidden entries (newer version or damaged): ${ws.hiddenEntryCount}',
      )
      ..writeln('Sync conflict copies: ${ws.conflicts.length}')
      ..writeln('Repairs on the last read: ${ws.repairs.length}');
  }
  out.writeln();

  final total = fileSizes.values.fold(0, (a, b) => a + b);
  out.writeln('== Files (${fileSizes.length}, ${_size(total)})');
  final names = fileSizes.keys.toList()..sort();
  for (final name in names) {
    out.writeln('${_size(fileSizes[name]!).padLeft(9)}  $name');
  }
  out
    ..writeln()
    ..writeln('== Error log')
    ..writeln(log.trim().isEmpty ? 'Empty.' : log.trimRight());
  return out.toString();
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
