import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/colors.dart';
import '../core/models.dart';
import '../core/project_keys.dart';
import 'atomic_file.dart';
import 'save_queue.dart';

/// The chosen data folder doesn't exist (deleted, renamed, drive unplugged, sync not ready). Never treated as an
/// empty workspace and never recreated (SPEC §2.5).
class WorkspaceFolderMissing implements Exception {
  const WorkspaceFolderMissing(this.folder);
  final String folder;

  @override
  String toString() => 'Data folder not found: $folder';
}

/// A write was refused because it could destroy data this instance couldn't read.
class UnsafeWriteException implements Exception {
  const UnsafeWriteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads and writes one data folder (SPEC §2.1, §2.5). The only code that touches workspace files.
class WorkspaceStore {
  WorkspaceStore(this.folder, {SaveQueue? queue, DateTime Function()? clock})
    : queue = queue ?? SaveQueue(clock: clock),
      _now = clock ?? DateTime.now;

  static const markerFileName = 'tasklet-workspace.json';
  static const labelsFileName = 'labels.json';
  static const viewsFileName = 'views.json';
  static const projectsDirName = 'projects';
  static const formatVersion = 1;

  /// Project ids become file names, so anything else is rejected (a crafted id could escape the folder).
  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final String folder;
  final SaveQueue queue;
  final DateTime Function() _now;

  /// Canonical project files that exist but failed to parse at the last read; never overwritten.
  final _unreadableProjects = <String>{};
  bool _labelsReadable = true;
  bool _viewsReadable = true;

  String get _projectsDir => p.join(folder, projectsDirName);
  String projectPath(String projectId) => p.join(_projectsDir, '$projectId.json');
  String get labelsPath => p.join(folder, labelsFileName);
  String get viewsPath => p.join(folder, viewsFileName);

  /// Prepares an existing folder for use: writes the marker file (once) and the projects directory. Used when the
  /// user chooses or creates a folder. Adds no demo data (SPEC §10).
  static Future<void> initialize(String folder) async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    final marker = File(p.join(folder, markerFileName));
    if (!await marker.exists()) {
      await writeFileAtomic(marker.path, encodeJson({'app': 'tasklet', 'formatVersion': formatVersion}));
    }
    await Directory(p.join(folder, projectsDirName)).create();
  }

  /// Reads the whole folder. Unreadable files are skipped (and remembered so they're never overwritten), sync
  /// conflict copies are reported but untouched, and project keys are resolved and persisted if they changed.
  Future<Workspace> read() async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);

    final (labels, labelsReadable) = await _readArray(labelsPath, Label.fromJson);
    final (views, viewsReadable) = await _readArray(viewsPath, SavedView.fromJson);
    _labelsReadable = labelsReadable;
    _viewsReadable = viewsReadable;

    final canonical = <String, Project>{};
    final copies = <(String, Project)>[];
    _unreadableProjects.clear();
    final dir = Directory(_projectsDir);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File || !name.endsWith('.json') || name.startsWith('.')) continue;
        final stem = p.basenameWithoutExtension(name);
        final project = await _readProject(entity);
        if (project == null) {
          if (_safeId.hasMatch(stem)) _unreadableProjects.add(p.canonicalize(entity.path));
        } else if (stem == project.id) {
          canonical[project.id] = project;
        } else {
          copies.add((entity.path, project));
        }
      }
    }

    // Only canonical <id>.json files are ever read or written; everything else is a conflict copy (SPEC §2.5).
    final conflicts = [for (final (path, project) in copies) SyncConflict(file: path, projectName: project.name)]
      ..sort((a, b) => a.file.compareTo(b.file));

    final storedNoProject = canonical.remove(noProjectId);
    final now = _now();
    final noProject = storedNoProject == null
        ? Project.noProject(now)
        : storedNoProject.copyWith(
            name: 'No Project',
            key: noProjectKey,
            color: TaskletColor.neutral,
            archived: false,
            favorite: false,
          );

    var projects = canonical.values.toList();
    final changedKeys = resolveProjectKeys(projects);
    if (changedKeys.isNotEmpty) {
      projects = [
        for (final pr in projects) changedKeys.containsKey(pr.id) ? pr.copyWith(key: changedKeys[pr.id]) : pr,
      ];
      // Persist self-healed keys; a failure here is retried on the next read.
      await Future.wait([
        for (final pr in projects)
          if (changedKeys.containsKey(pr.id)) writeProject(pr).catchError((Object _) {}),
      ]);
    }
    projects.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

    return Workspace(
      folder: folder,
      projects: projects,
      noProject: noProject,
      noProjectOnDisk: storedNoProject != null,
      labels: labels,
      labelsReadable: labelsReadable,
      views: views,
      viewsReadable: viewsReadable,
      conflicts: conflicts,
    );
  }

  /// Saves one project file atomically. The No-Project file is only created once it has a task (SPEC §2.3).
  Future<void> writeProject(Project project) async {
    if (!_safeId.hasMatch(project.id)) throw UnsafeWriteException('Invalid project id: ${project.id}');
    final path = projectPath(project.id);
    if (_unreadableProjects.contains(p.canonicalize(path))) {
      throw UnsafeWriteException('Not saving "${project.name}": its file could not be read and might be mid-sync.');
    }
    if (project.isNoProject && project.tasks.isEmpty && !await File(path).exists()) return;
    await queue.enqueue(path, () async {
      await Directory(_projectsDir).create(recursive: true);
      await writeFileAtomic(path, encodeJson(project.toJson()));
    });
  }

  Future<void> writeLabels(List<Label> labels) {
    if (!_labelsReadable) {
      throw const UnsafeWriteException('Not saving labels: labels.json could not be read and might be mid-sync.');
    }
    return queue.enqueue(
      labelsPath,
      () => writeFileAtomic(labelsPath, encodeJson([for (final l in labels) l.toJson()])),
    );
  }

  Future<void> writeViews(List<SavedView> views) {
    if (!_viewsReadable) {
      throw const UnsafeWriteException('Not saving views: views.json could not be read and might be mid-sync.');
    }
    return queue.enqueue(viewsPath, () => writeFileAtomic(viewsPath, encodeJson([for (final v in views) v.toJson()])));
  }

  Future<Project?> _readProject(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return null;
      final project = Project.fromJson(json);
      return _safeId.hasMatch(project.id) ? project : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null; // locked or still downloading
    }
  }

  /// (items, readable). A missing file is an empty, readable list.
  Future<(List<T>, bool)> _readArray<T>(String path, T Function(Map<String, Object?>) parse) async {
    final file = File(path);
    try {
      if (!await file.exists()) return (<T>[], true);
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return (<T>[], false);
      return (
        [for (final item in json) parse(item is Map<String, Object?> ? item : throw const FormatException())],
        true,
      );
    } on FormatException {
      return (<T>[], false);
    } on FileSystemException {
      return (<T>[], false);
    }
  }
}
