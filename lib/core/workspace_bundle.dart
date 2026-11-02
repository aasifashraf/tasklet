import 'models.dart';
import 'workspace_info.dart';

/// One file holding a whole workspace (docs/DECISIONS.md D15): Export Workspace writes it, Import
/// Workspace makes a new workspace folder from it. Labels, quick filters and projects are kept as their file
/// JSON, so fields from newer versions and entries this version can't show survive the round trip.
class WorkspaceBundle {
  WorkspaceBundle({
    required this.info,
    required this.exportedAt,
    required this.labels,
    required this.views,
    required this.projects,
  });

  static const kind = 'workspace';

  /// What 1.1.0 wrote (workspaces were called organizations then); still imported.
  static const legacyKind = 'organization';
  static const formatVersion = 1;
  static const fileExtension = '.tasklet.json';

  final WorkspaceInfo info;
  final DateTime exportedAt;

  /// labels.json and views.json, as stored.
  final List<Object?> labels;
  final List<Object?> views;

  /// Each project file (No Project included when it has tasks), as stored.
  final List<Map<String, Object?>> projects;

  int get taskCount => projects.fold(
    0,
    (n, p) => n + (p['tasks'] is List ? (p['tasks']! as List).length : 0),
  );

  Map<String, Object?> toJson() => {
    'app': 'tasklet',
    'kind': kind,
    'formatVersion': formatVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'workspace': info.toJson(),
    'labels': labels,
    'views': views,
    'projects': projects,
  };

  /// Reads a bundle. Anything that isn't a Tasklet workspace export, comes from a newer format, or has a
  /// project that can't be read throws a [FormatException] whose message can be shown as is. [isSafeId] checks a
  /// project id is usable as a file name.
  factory WorkspaceBundle.fromJson(
    Object? json, {
    required bool Function(String id) isSafeId,
  }) {
    if (json is! Map<String, Object?> ||
        json['app'] != 'tasklet' ||
        (json['kind'] != kind && json['kind'] != legacyKind)) {
      throw const FormatException("This isn't a Tasklet workspace export.");
    }
    final version = json['formatVersion'];
    if (version is! num || version != version.truncate()) {
      throw const FormatException("This export's format can't be read.");
    }
    if (version > formatVersion) {
      throw const FormatException(
        'This export was made by a newer version of Tasklet. Update Tasklet to import it.',
      );
    }
    final labels = json['labels'] ?? const <Object?>[];
    final views = json['views'] ?? const <Object?>[];
    final projects = json['projects'] ?? const <Object?>[];
    if (labels is! List || views is! List || projects is! List) {
      throw const FormatException('This export is damaged.');
    }
    final ids = <String>{};
    final read = <Map<String, Object?>>[];
    for (final p in projects) {
      final id = p is Map<String, Object?> ? p['id'] : null;
      if (p is! Map<String, Object?> || id is! String || !isSafeId(id)) {
        throw const FormatException('This export has a damaged project.');
      }
      if (!ids.add(id)) {
        throw const FormatException('This export lists a project twice.');
      }
      try {
        Project.fromJson(p);
      } on Object {
        throw FormatException(
          'This export has a project that can\'t be read ("${p['name'] ?? id}").',
        );
      }
      read.add(p);
    }
    final exported = DateTime.tryParse('${json['exportedAt']}');
    return WorkspaceBundle(
      info: WorkspaceInfo.fromMarker(switch (json['workspace'] ??
          json['organization']) {
        final Map<String, Object?> info => info,
        _ => null,
      }, 'Imported Workspace'),
      exportedAt:
          exported ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      labels: labels,
      views: views,
      projects: read,
    );
  }
}
