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

/// A write was refused because it could destroy data this instance couldn't read or doesn't understand.
class UnsafeWriteException implements Exception {
  const UnsafeWriteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Moves a file to the OS Recycle Bin/Trash; returns false (touching nothing) if that isn't possible there.
typedef MoveToTrash = Future<bool> Function(String path);

/// Reads and writes one data folder (SPEC §2.1, §2.5). The only code that touches workspace files.
/// Decisions behind these rules: docs/DECISIONS.md.
class WorkspaceStore {
  WorkspaceStore(this.folder, {SaveQueue? queue, DateTime Function()? clock})
    : queue = queue ?? SaveQueue(clock: clock),
      _now = clock ?? DateTime.now;

  static const markerFileName = 'tasklet-workspace.json';
  static const labelsFileName = 'labels.json';
  static const viewsFileName = 'views.json';
  static const projectsDirName = 'projects';

  /// Recoverable holding area for deleted project files on volumes without a Recycle Bin/Trash.
  static const trashDirName = '.trash';

  /// Bumped only for changes older versions can't safely write (additive changes rely on field preservation).
  static const formatVersion = 1;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final _windowsReserved = RegExp(
    r'^(con|prn|aux|nul|com\d|lpt\d)$',
    caseSensitive: false,
  );

  /// Project ids become file names: anything else could escape the folder or be unwritable on Windows.
  static bool isSafeProjectId(String id) =>
      _safeId.hasMatch(id) && !_windowsReserved.hasMatch(id);

  final String folder;
  final SaveQueue queue;
  final DateTime Function() _now;

  bool _readOnly = false;
  bool _labelsReadable = true;
  bool _viewsReadable = true;
  List<Object?> _opaqueLabels = const [];
  List<Object?> _opaqueViews = const [];

  /// Canonical project files that exist but failed to parse at the last read; never overwritten.
  final _unreadableProjects = <String>{};

  /// Sync conflict copies per project id, from the last read.
  final _copiesByProject = <String, List<String>>{};

  /// Projects deleted in this session; saving them again would resurrect the file.
  final _deletedProjects = <String>{};

  String get _projectsDir => p.join(folder, projectsDirName);
  String projectPath(String projectId) =>
      p.join(_projectsDir, '$projectId.json');
  String get labelsPath => p.join(folder, labelsFileName);
  String get viewsPath => p.join(folder, viewsFileName);
  String get _markerPath => p.join(folder, markerFileName);

  /// Prepares an existing folder for use: writes the marker file (once) and the projects directory. Used when the
  /// user chooses or creates a folder. Adds no demo data (SPEC §10).
  static Future<void> initialize(String folder) async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    final marker = File(p.join(folder, markerFileName));
    if (!await marker.exists()) {
      await writeFileAtomic(
        marker.path,
        encodeJson({'app': 'tasklet', 'formatVersion': formatVersion}),
      );
    }
    await Directory(p.join(folder, projectsDirName)).create();
  }

  /// Reads the whole folder.
  ///
  /// - Unreadable files are skipped and remembered so they're never overwritten.
  /// - Sync conflict copies are reported and never touched; if a project's main file is missing, its newest copy
  ///   is shown instead (first save recreates the main file).
  /// - Project keys are resolved and changed keys persisted.
  Future<Workspace> read() async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    _readOnly = await _markerIsNewerOrUnreadable();

    final (labels, labelsReadable) = await _readList(
      labelsPath,
      Label.fromJson,
      (l) => l.id,
    );
    final (views, viewsReadable) = await _readList(
      viewsPath,
      SavedView.fromJson,
      (v) => v.id,
    );
    _labelsReadable = labelsReadable;
    _viewsReadable = viewsReadable;
    _opaqueLabels = labels.opaque;
    _opaqueViews = views.opaque;

    final conflicts = <SyncConflict>[...await _rootConflicts()];
    final canonical = <String, Project>{};
    final copies = <String, List<(String, Project)>>{};
    _unreadableProjects.clear();
    final dir = Directory(_projectsDir);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            name.startsWith('.')) {
          continue;
        }
        final stem = p.basenameWithoutExtension(name);
        final project = await _readProject(entity);
        if (project == null) {
          if (isSafeProjectId(stem)) _unreadableProjects.add(_key(entity.path));
        } else if (stem == project.id) {
          canonical[project.id] = project;
        } else {
          (copies[project.id] ??= []).add((entity.path, project));
        }
      }
    }

    // Only canonical <id>.json files are ever written; copies stay untouched (SPEC §2.5). A project whose main
    // file is gone (and not merely unreadable) is shown from its newest copy rather than hidden.
    _copiesByProject.clear();
    for (final MapEntry(key: id, value: list) in copies.entries) {
      _copiesByProject[id] = [for (final (path, _) in list) path];
      final mainMissing =
          !canonical.containsKey(id) &&
          !_unreadableProjects.contains(_key(projectPath(id)));
      if (mainMissing) {
        final newest = [...list]
          ..sort((a, b) {
            final byUpdated = b.$2.updatedAt.compareTo(a.$2.updatedAt);
            return byUpdated != 0 ? byUpdated : a.$1.compareTo(b.$1);
          });
        canonical[id] = newest.first.$2;
      }
      for (final (path, project) in list) {
        conflicts.add(
          SyncConflict(
            file: path,
            projectName: project.name,
            mainFileMissing: mainMissing,
          ),
        );
      }
    }
    conflicts.sort((a, b) => a.file.compareTo(b.file));
    _deletedProjects.removeAll(
      canonical.keys,
    ); // a project restored by sync is editable again

    final storedNoProject = canonical.remove(noProjectId);
    final noProject = storedNoProject == null
        ? Project.noProject(_now())
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
        for (final pr in projects)
          changedKeys.containsKey(pr.id)
              ? pr.copyWith(key: changedKeys[pr.id])
              : pr,
      ];
      if (!_readOnly) {
        // Persist self-healed keys; a failure here is retried on the next read.
        await Future.wait([
          for (final pr in projects)
            if (changedKeys.containsKey(pr.id))
              writeProject(pr).catchError((Object _) {}),
        ]);
      }
    }
    projects.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

    final hidden = [
      for (final pr in projects) pr.hiddenEntryCount,
      noProject.hiddenEntryCount,
      labels.opaque.length,
      views.opaque.length,
    ].fold(0, (a, b) => a + b);

    return Workspace(
      folder: folder,
      projects: projects,
      noProject: noProject,
      noProjectOnDisk: await File(projectPath(noProjectId)).exists(),
      labels: labels.items,
      labelsReadable: labelsReadable,
      views: views.items,
      viewsReadable: viewsReadable,
      conflicts: conflicts,
      readOnly: _readOnly,
      hiddenEntryCount: hidden,
    );
  }

  /// Saves one project file atomically. The No-Project file is only created once it has a task (SPEC §2.3).
  Future<void> writeProject(Project project) async {
    _checkWritable();
    if (!isSafeProjectId(project.id)) {
      throw UnsafeWriteException('Invalid project id: ${project.id}');
    }
    if (_deletedProjects.contains(project.id)) {
      throw UnsafeWriteException(
        'Not saving "${project.name}": it was deleted.',
      );
    }
    final path = projectPath(project.id);
    if (_unreadableProjects.contains(_key(path))) {
      throw UnsafeWriteException(
        'Not saving "${project.name}": its file could not be read and might be mid-sync.',
      );
    }
    if (project.isNoProject &&
        project.tasks.isEmpty &&
        !await File(path).exists()) {
      return;
    }
    await queue.enqueue(path, () async {
      await Directory(_projectsDir).create(recursive: true);
      await writeFileAtomic(path, encodeJson(project.toJson()));
    });
  }

  Future<void> writeLabels(List<Label> labels) {
    _checkWritable();
    if (!_labelsReadable) {
      throw const UnsafeWriteException(
        'Not saving labels: labels.json could not be read and might be mid-sync.',
      );
    }
    final json = [for (final l in labels) l.toJson(), ..._opaqueLabels];
    return queue.enqueue(
      labelsPath,
      () => writeFileAtomic(labelsPath, encodeJson(json)),
    );
  }

  Future<void> writeViews(List<SavedView> views) {
    _checkWritable();
    if (!_viewsReadable) {
      throw const UnsafeWriteException(
        'Not saving views: views.json could not be read and might be mid-sync.',
      );
    }
    final json = [for (final v in views) v.toJson(), ..._opaqueViews];
    return queue.enqueue(
      viewsPath,
      () => writeFileAtomic(viewsPath, encodeJson(json)),
    );
  }

  /// Deletes a project (SPEC §4.5): its file (and any sync conflict copies of it, so it doesn't reappear from
  /// one) goes to the OS Recycle Bin/Trash, or to `<folder>/.trash/` on volumes without one. Never a permanent
  /// delete. Runs after any queued save of the same project.
  Future<void> deleteProject(
    Project project, {
    required MoveToTrash moveToTrash,
  }) async {
    _checkWritable();
    if (project.isNoProject) {
      throw const UnsafeWriteException(
        'The No Project bucket cannot be deleted.',
      );
    }
    if (!isSafeProjectId(project.id)) {
      throw UnsafeWriteException('Invalid project id: ${project.id}');
    }
    _deletedProjects.add(project.id);
    final paths = [projectPath(project.id), ...?_copiesByProject[project.id]];
    await queue.enqueue(projectPath(project.id), () async {
      for (final path in paths) {
        if (!await File(path).exists()) continue;
        if (!await moveToTrash(path)) await _moveToFolderTrash(path);
      }
    });
  }

  Future<void> _moveToFolderTrash(String path) async {
    final dir = Directory(p.join(folder, trashDirName));
    await dir.create(recursive: true);
    final stamp = _now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    await File(path).rename(p.join(dir.path, '$stamp ${p.basename(path)}'));
  }

  void _checkWritable() {
    if (_readOnly) {
      throw const UnsafeWriteException(
        'This folder was saved by a newer version of Tasklet (or is mid-sync). Update Tasklet to make changes.',
      );
    }
  }

  static String _key(String path) => p.canonicalize(path);

  /// A missing marker is a fresh or legacy folder (writable). An unreadable marker might be mid-sync, and a newer
  /// format version can't be written safely. Both make this read read-only.
  Future<bool> _markerIsNewerOrUnreadable() async {
    final marker = File(_markerPath);
    try {
      if (!await marker.exists()) return false;
      final json = jsonDecode(await marker.readAsString());
      if (json is! Map<String, Object?>) return true;
      final version = json['formatVersion'];
      return version is! int || version > formatVersion;
    } on FormatException {
      return true;
    } on FileSystemException {
      return true;
    }
  }

  /// Conflict copies of labels.json / views.json (e.g. "labels (conflicted copy).json", "views-LAPTOP.json").
  Future<List<SyncConflict>> _rootConflicts() async {
    final result = <SyncConflict>[];
    await for (final entity in Directory(folder).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File || !name.endsWith('.json') || name.startsWith('.')) {
        continue;
      }
      if (name == labelsFileName ||
          name == viewsFileName ||
          name == markerFileName) {
        continue;
      }
      final lower = name.toLowerCase();
      if (lower.startsWith('labels')) {
        result.add(SyncConflict(file: entity.path, projectName: 'Labels'));
      }
      if (lower.startsWith('views')) {
        result.add(SyncConflict(file: entity.path, projectName: 'Quick Filters'));
      }
    }
    return result;
  }

  Future<Project?> _readProject(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return null;
      final project = Project.fromJson(json);
      return isSafeProjectId(project.id) ? project : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null; // locked or still downloading
    }
  }

  /// (entries, readable). A missing file is an empty, readable list. Individual entries this version can't parse
  /// are preserved as opaque rather than making the whole file unreadable.
  Future<(LenientList<T>, bool)> _readList<T>(
    String path,
    T Function(Map<String, Object?>) parse,
    String Function(T) idOf,
  ) async {
    final empty = LenientList<T>(const [], const []);
    final file = File(path);
    try {
      if (!await file.exists()) return (empty, true);
      return (
        LenientList.parse(jsonDecode(await file.readAsString()), parse, idOf),
        true,
      );
    } on FormatException {
      return (empty, false);
    } on FileSystemException {
      return (empty, false);
    }
  }
}
