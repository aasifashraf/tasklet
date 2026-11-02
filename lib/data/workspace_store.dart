import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../core/colors.dart';
import '../core/merge.dart';
import '../core/models.dart';
import '../core/org_bundle.dart';
import '../core/organization.dart';
import '../core/project_keys.dart';
import '../core/task_ops.dart'
    show resolveDuplicateNumbers, resolveDuplicateTaskIds;
import 'atomic_file.dart';
import 'backups.dart';
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
  WorkspaceStore(
    this.folder, {
    SaveQueue? queue,
    DateTime Function()? clock,
    this.maxFileBytes = 100 * 1024 * 1024,
    this.backups,
  }) : queue = queue ?? SaveQueue(clock: clock),
       _now = clock ?? DateTime.now;

  /// Local version history taken before files are overwritten; null keeps none (tests, read-only tools).
  final Backups? backups;

  /// Larger project, label or view files are treated as unreadable: never loaded (protects memory against a huge
  /// or hostile file in a shared folder) and never overwritten.
  final int maxFileBytes;

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
  OrgInfo _organization = const OrgInfo(name: '');
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

  /// The last parse of each project file and the (modified, size) it had then. A refresh re-parses only files whose
  /// stamp changed and keeps the same [Project] instances for the rest.
  final _parsed = <String, ({DateTime modified, int size, Project? project})>{};

  /// Stamps of the files this store wrote last (see [isOwnWrite]).
  final _ownStamps = <String, ({DateTime modified, int size})>{};

  /// Merge notes from saves, collected by [takeMergeNotes].
  final _mergeNotes = <String>[];

  /// What the last [read] saw (every file's stamp) and returned; an unchanged folder returns the same [Workspace].
  String? _lastSignature;
  Workspace? _last;

  /// Changed project files larger than this in total are parsed on a background isolate, so a big folder never
  /// freezes the UI. Smaller reads stay on the async file API (no isolate start-up cost).
  static const _isolateParseBytes = 256 * 1024;

  /// Projects with more tasks than this are encoded on a background isolate when saved.
  static const _isolateEncodeTasks = 2000;

  String get _projectsDir => p.join(folder, projectsDirName);
  String projectPath(String projectId) =>
      p.join(_projectsDir, '$projectId.json');
  String get labelsPath => p.join(folder, labelsFileName);
  String get viewsPath => p.join(folder, viewsFileName);
  String get _markerPath => p.join(folder, markerFileName);

  /// Prepares an existing folder for use: writes the marker file (once) and the projects directory. Used when the
  /// user chooses or creates a folder. Adds no demo data (SPEC §10). A new marker gets [organization] as the
  /// folder's identity (D15); an existing one is left alone.
  static Future<void> initialize(String folder, {OrgInfo? organization}) async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    final marker = File(p.join(folder, markerFileName));
    if (!await marker.exists()) {
      await writeFileAtomic(
        marker.path,
        encodeJson({
          'app': 'tasklet',
          'formatVersion': formatVersion,
          ...?organization?.toJson(),
        }),
      );
    }
    await Directory(p.join(folder, projectsDirName)).create();
  }

  /// Reads the whole folder.
  ///
  /// - Unreadable files are skipped and remembered so they're never overwritten.
  /// - Sync conflict copies are reported and never touched; if a project's main file is missing, its newest copy
  ///   is shown instead (first save recreates the main file).
  /// - A task found in two project files is kept once, then project keys and duplicate task numbers are resolved;
  ///   the repairs are persisted and described in [Workspace.repairs].
  /// - Files over [maxFileBytes] are treated as unreadable (never loaded, never overwritten).
  /// - Only files that changed since the last read are parsed again; if nothing changed, the previous [Workspace]
  ///   instance is returned. [reparse] forces a full read (explicit Refresh).
  Future<Workspace> read({bool reparse = false}) async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    if (reparse) {
      _parsed.clear();
      _last = null;
    }
    final signature = StringBuffer();
    final (:readOnly, :marker) = await _readMarker();
    _readOnly = readOnly;
    _organization = OrgInfo.fromMarker(marker, folderName(folder));

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

    final conflicts = <SyncConflict>[...await _rootConflicts(signature)];
    final canonical = <String, Project>{};
    final copies = <String, List<(String, Project)>>{};
    _unreadableProjects.clear();
    final dir = Directory(_projectsDir);
    final files = <(File, FileStat)>[];
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            name.startsWith('.')) {
          continue;
        }
        files.add((entity, await entity.stat()));
      }
    }
    files.sort((a, b) => a.$1.path.compareTo(b.$1.path));
    await _parseChanged(files);
    for (final (file, stat) in files) {
      signature.write('${file.path}|${stat.modified}|${stat.size}\n');
      final stem = p.basenameWithoutExtension(file.path);
      final project = _parsed[file.path]!.project;
      if (project == null) {
        if (isSafeProjectId(stem)) _unreadableProjects.add(_key(file.path));
      } else if (stem == project.id) {
        canonical[project.id] = project;
      } else {
        (copies[project.id] ??= []).add((file.path, project));
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
    var noProject = storedNoProject == null
        ? Project.noProject(_now())
        : storedNoProject.copyWith(
            name: 'No Project',
            key: noProjectKey,
            color: TaskletColor.neutral,
            archived: false,
            favorite: false,
          );

    // Self-heal what syncing two computers can break: one task in two project files, duplicate project keys and
    // duplicate task numbers. Each repair is saved and described in `repairs` for a notice.
    final duplicates = resolveDuplicateTaskIds([
      ...canonical.values,
      if (storedNoProject != null) noProject,
    ]);
    final changedKeys = resolveProjectKeys(canonical.values);
    final healed = <Project>[];
    final renumberNotes = <String>[];
    Project heal(Project pr) {
      var next = duplicates.changed[pr.id] ?? pr;
      if (changedKeys.containsKey(pr.id)) {
        next = next.copyWith(key: changedKeys[pr.id]);
      }
      final renumbered = resolveDuplicateNumbers(next);
      if (renumbered != null) {
        for (final t in renumbered.tasks) {
          final before = next.taskById(t.id)!.number;
          if (before != t.number) {
            renumberNotes.add(
              'Two computers both created ${next.key}-$before; the newer one is now ${next.key}-${t.number}.',
            );
          }
        }
        next = renumbered;
      }
      if (!identical(next, pr)) healed.add(next);
      return next;
    }

    final projects = [for (final pr in canonical.values) heal(pr)];
    if (storedNoProject != null) noProject = heal(noProject);
    final nameOf = {
      for (final pr in [...projects, noProject]) pr.id: pr.name,
    };
    final repairs = _readOnly
        ? const <String>[]
        : [
            for (final d in duplicates.dropped)
              '"${d.task.title}" was in both ${nameOf[d.keptIn]} and ${nameOf[d.droppedFrom]}; the most recently '
                  'edited copy was kept in ${nameOf[d.keptIn]}.',
            ...renumberNotes,
          ];

    final last = _last;
    if (last != null &&
        healed.isEmpty &&
        signature.toString() == _lastSignature) {
      return last;
    }
    if (healed.isNotEmpty && !_readOnly) {
      // Persist the repairs; a failure here is retried on the next read.
      await Future.wait([
        for (final pr in healed) writeProject(pr).catchError((Object _) {}),
      ]);
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

    final workspace = Workspace(
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
      repairs: repairs,
      organization: _organization,
    );
    // Self-heal writes change files, so that read is never reused.
    _last = healed.isEmpty ? workspace : null;
    _lastSignature = signature.toString();
    return workspace;
  }

  /// Re-parses the project [files] whose stamp differs from the last parse and forgets files that are gone.
  Future<void> _parseChanged(List<(File, FileStat)> files) async {
    final stale = <String>[];
    var staleBytes = 0;
    for (final (file, stat) in files) {
      final cached = _parsed[file.path];
      if (cached != null &&
          cached.modified == stat.modified &&
          cached.size == stat.size) {
        continue;
      }
      if (stat.size > maxFileBytes) {
        // A huge file in a shared folder (damaged, or not ours) must not exhaust memory: unreadable, untouched.
        _parsed[file.path] = (
          modified: stat.modified,
          size: stat.size,
          project: null,
        );
        continue;
      }
      stale.add(file.path);
      staleBytes += stat.size;
    }
    final current = {for (final (file, _) in files) file.path};
    _parsed.removeWhere((path, _) => !current.contains(path));
    if (stale.isEmpty) return;
    final results = staleBytes > _isolateParseBytes
        ? await _parseOnIsolate(stale)
        : [for (final path in stale) await _readProject(File(path))];
    final stats = {for (final (file, stat) in files) file.path: stat};
    for (final (i, path) in stale.indexed) {
      final stat = stats[path]!;
      _parsed[path] = (
        modified: stat.modified,
        size: stat.size,
        project: results[i],
      );
    }
  }

  static Future<List<Project?>> _parseOnIsolate(List<String> paths) =>
      Isolate.run(() => [for (final path in paths) _parseProjectSync(path)]);

  static Project? _parseProjectSync(String path) {
    try {
      return _projectFrom(jsonDecode(File(path).readAsStringSync()));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null; // locked or still downloading
    }
  }

  static Project? _projectFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final project = Project.fromJson(json);
    return isSafeProjectId(project.id) ? project : null;
  }

  static Future<String> _encodeProject(Project project) =>
      project.tasks.length > _isolateEncodeTasks
      ? Isolate.run(() => encodeJson(project.toJson()))
      : Future.value(encodeJson(project.toJson()));

  /// Saves one project file atomically. The No-Project file is only created once it has a task (SPEC §2.3).
  /// The version being replaced goes to [backups] first ([backupFirst]: even if a recent backup exists).
  Future<void> writeProject(Project project, {bool backupFirst = false}) async {
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
    // Everything below runs in the queue, so it sees the effect of earlier saves of the same file.
    await queue.enqueue(path, () async {
      if (project.isNoProject &&
          project.tasks.isEmpty &&
          !await File(path).exists()) {
        return;
      }
      // A vanished folder (unplugged drive, sync not ready) is never recreated (SPEC §2.5).
      if (!await Directory(folder).exists()) {
        throw WorkspaceFolderMissing(folder);
      }
      await Directory(_projectsDir).create();
      // Changed on another computer since we last read or wrote it? Merge instead of overwriting.
      final merged = await _mergeIfChangedOnDisk(path, project);
      final toWrite = merged ?? project;
      await _backUp(path, force: backupFirst || merged != null);
      await writeFileAtomic(path, await _encodeProject(toWrite));
      _remember(path, toWrite);
    });
  }

  /// Compare-before-write (docs/SYSTEM_DESIGN.md section 14): if the file's stamp differs from what this store last
  /// read or wrote, another computer (or tool) changed it. Returns [mine] merged with that version, or null when the
  /// file is unchanged (or new). Refuses to write over a version it can't read.
  Future<Project?> _mergeIfChangedOnDisk(String path, Project mine) async {
    final known = _parsed[path];
    final file = File(path);
    if (known == null || !await file.exists()) return null;
    final stat = await file.stat();
    if (stat.modified == known.modified && stat.size == known.size) return null;
    final theirs = stat.size > _isolateParseBytes
        ? (await _parseOnIsolate([path])).single
        : await _readProject(file);
    if (theirs == null || theirs.id != mine.id) {
      throw UnsafeWriteException(
        "Couldn't save \"${mine.name}\": it was just changed on another computer and is still syncing. "
        'Try again in a moment.',
      );
    }
    final result = mergeProject(
      base: known.project ?? theirs,
      mine: mine,
      theirs: theirs,
      now: _now(),
    );
    _mergeNotes
      ..add(
        '"${mine.name}" was also changed on another computer; both sets of changes were combined.',
      )
      ..addAll(result.notes);
    return result.project;
  }

  /// Records what this store just wrote: the file's stamp (so the watcher recognises its own save and the next
  /// write can detect foreign changes) and, for project files, the written project as the next merge base.
  void _remember(String path, [Project? written]) {
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) return;
    _ownStamps[_key(path)] = (modified: stat.modified, size: stat.size);
    if (written != null) {
      _parsed[path] = (
        modified: stat.modified,
        size: stat.size,
        project: written,
      );
    }
  }

  /// Notes about merges done by saves since the last call (shown as repair notices).
  List<String> takeMergeNotes() {
    final notes = [..._mergeNotes];
    _mergeNotes.clear();
    return notes;
  }

  /// Whether a change the folder watcher reports at [path] is this store's own save: pending in the queue, or the
  /// file still has the stamp of our last write. Unlike a time window, a foreign change right after our save is
  /// recognised as foreign.
  bool isOwnWrite(String path) {
    if (queue.isPending(path)) return true;
    final own = _ownStamps[_key(path)];
    if (own == null) return false;
    final stat = FileStat.statSync(path);
    return stat.modified == own.modified && stat.size == own.size;
  }

  /// Keeps the current version of [path] in [backups]. A backup failure never blocks the save itself.
  Future<void> _backUp(String path, {bool force = false}) async {
    try {
      await backups?.beforeOverwrite(path, force: force);
    } on FileSystemException {
      // Out of space or locked: saving the user's change matters more than the history.
    }
  }

  /// Earlier versions of labels.json, newest first.
  Future<List<Backup>> labelsBackups() async =>
      await backups?.list(labelsPath) ?? const [];

  /// Earlier versions of views.json (quick filters), newest first.
  Future<List<Backup>> viewsBackups() async =>
      await backups?.list(viewsPath) ?? const [];

  /// Puts a labels.json or views.json backup back exactly as it was, after backing up the current file. Refused
  /// like any write when the current file can't be read right now (it might be mid-sync). Callers re-read after.
  Future<void> restoreListFile(Backup backup, {required bool labels}) {
    _checkWritable();
    final path = labels ? labelsPath : viewsPath;
    if (!(labels ? _labelsReadable : _viewsReadable)) {
      throw UnsafeWriteException(
        'Not restoring: ${p.basename(path)} could not be read and might be mid-sync.',
      );
    }
    return queue.enqueue(path, () async {
      final contents = await File(backup.path).readAsString();
      if (jsonDecode(contents) is! List) {
        throw const FormatException('This backup is damaged.');
      }
      await _backUp(path, force: true);
      await writeFileAtomic(path, contents);
      _remember(path);
    });
  }

  /// Earlier versions of a project's file, newest first.
  Future<List<Backup>> projectBackups(String projectId) async =>
      await backups?.list(projectPath(projectId)) ?? const [];

  /// Reads a backup taken by [projectBackups]; null if it can't be parsed.
  Future<Project?> readBackup(Backup backup) async =>
      backup.bytes > _isolateParseBytes
      ? (await _parseOnIsolate([backup.path])).single
      : await _readProject(File(backup.path));

  Future<void> writeLabels(List<Label> labels) {
    _checkWritable();
    if (!_labelsReadable) {
      throw const UnsafeWriteException(
        'Not saving labels: labels.json could not be read and might be mid-sync.',
      );
    }
    final json = [for (final l in labels) l.toJson(), ..._opaqueLabels];
    return queue.enqueue(labelsPath, () async {
      await _backUp(labelsPath);
      await writeFileAtomic(labelsPath, encodeJson(json));
      _remember(labelsPath);
    });
  }

  Future<void> writeViews(List<SavedView> views) {
    _checkWritable();
    if (!_viewsReadable) {
      throw const UnsafeWriteException(
        'Not saving views: views.json could not be read and might be mid-sync.',
      );
    }
    final json = [for (final v in views) v.toJson(), ..._opaqueViews];
    return queue.enqueue(viewsPath, () async {
      await _backUp(viewsPath);
      await writeFileAtomic(viewsPath, encodeJson(json));
      _remember(viewsPath);
    });
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

  /// The marker's JSON (null when missing or unreadable) and whether it makes the folder read-only. A missing
  /// marker is a fresh or legacy folder (writable). An unreadable marker might be mid-sync, and a newer format
  /// version can't be written safely: both make this read read-only.
  Future<({bool readOnly, Map<String, Object?>? marker})> _readMarker() =>
      _readMarkerAt(folder);

  static Future<({bool readOnly, Map<String, Object?>? marker})> _readMarkerAt(
    String folder,
  ) async {
    final marker = File(p.join(folder, markerFileName));
    try {
      if (!await marker.exists()) return (readOnly: false, marker: null);
      final json = jsonDecode(await marker.readAsString());
      if (json is! Map<String, Object?>) return (readOnly: true, marker: null);
      // No version (hand-made or legacy marker) means format 1; `1.0` from another JSON writer is 1. Anything
      // else that isn't a whole number can't be judged, so it stays read-only.
      final version = json['formatVersion'] ?? 1;
      final readOnly =
          version is! num ||
          version != version.truncate() ||
          version > formatVersion;
      return (readOnly: readOnly, marker: json);
    } on FormatException {
      return (readOnly: true, marker: null);
    } on FileSystemException {
      return (readOnly: true, marker: null);
    }
  }

  /// Saves an organization's identity into [folder]'s marker, replacing only the fields that differ from [before]
  /// (what the user saw), so anything else there (a newer version's values, another computer's change to another
  /// field) survives. For an organization that isn't open; the open one saves through [writeOrganization].
  static Future<void> writeOrganizationAt(
    String folder,
    OrgInfo organization, {
    required OrgInfo before,
  }) async {
    if (!await Directory(folder).exists()) throw WorkspaceFolderMissing(folder);
    final (:readOnly, :marker) = await _readMarkerAt(folder);
    if (readOnly) {
      throw const UnsafeWriteException(
        "Not saving the organization: its folder was saved by a newer version of Tasklet, or its marker file can't "
        'be read right now.',
      );
    }
    await writeFileAtomic(
      p.join(folder, markerFileName),
      encodeJson(
        organization.applyTo(
          marker ?? {'app': 'tasklet', 'formatVersion': formatVersion},
          before,
        ),
      ),
    );
  }

  /// [ws] (this folder's last read, plus edits) as one export (D15). Entries this version can't show are included
  /// as stored. Refuses while a file couldn't be read (mid-sync or damaged): the export would silently miss it.
  OrgBundle exportBundle(Workspace ws, DateTime now) {
    if (!ws.labelsReadable ||
        !ws.viewsReadable ||
        _unreadableProjects.isNotEmpty) {
      throw const UnsafeWriteException(
        "Can't export yet: some files in this organization's folder can't be read right now (still syncing, or "
        'damaged). Try again in a moment.',
      );
    }
    final noProject = ws.noProject;
    return OrgBundle(
      organization: ws.organization,
      exportedAt: now,
      labels: [for (final l in ws.labels) l.toJson(), ..._opaqueLabels],
      views: [for (final v in ws.views) v.toJson(), ..._opaqueViews],
      projects: [
        for (final p in ws.projects) p.toJson(),
        if (noProject.tasks.isNotEmpty || noProject.hiddenEntryCount > 0)
          noProject.toJson(),
      ],
    );
  }

  /// Writes [bundle] into [folder], which must exist and be empty (New Organization creates it), as a new
  /// organization named [organization]. On failure the files written so far are removed again.
  static Future<void> importBundle(
    String folder,
    OrgBundle bundle,
    OrgInfo organization,
  ) async {
    final dir = Directory(folder);
    if (!await dir.exists()) throw WorkspaceFolderMissing(folder);
    if (!await dir.list().isEmpty) {
      throw const UnsafeWriteException(
        'Import needs a new, empty folder for the organization.',
      );
    }
    try {
      await initialize(folder, organization: organization);
      if (bundle.labels.isNotEmpty) {
        await writeFileAtomic(
          p.join(folder, labelsFileName),
          encodeJson(bundle.labels),
        );
      }
      if (bundle.views.isNotEmpty) {
        await writeFileAtomic(
          p.join(folder, viewsFileName),
          encodeJson(bundle.views),
        );
      }
      for (final project in bundle.projects) {
        final id = project['id']! as String;
        if (!isSafeProjectId(id)) {
          throw UnsafeWriteException('Invalid project id: $id');
        }
        await writeFileAtomic(
          p.join(folder, projectsDirName, '$id.json'),
          encodeJson(project),
        );
      }
    } catch (_) {
      for (final entity in await dir.list().toList()) {
        await entity.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Saves the open organization's name, icon and color into the marker (D15); see [writeOrganizationAt].
  Future<void> writeOrganization(OrgInfo organization) {
    _checkWritable();
    final before = _organization;
    return queue.enqueue(_markerPath, () async {
      await writeOrganizationAt(folder, organization, before: before);
      _organization = organization;
      _remember(_markerPath);
    });
  }

  /// Conflict copies of labels.json / views.json (e.g. "labels (conflicted copy).json", "views-LAPTOP.json"). Adds
  /// every root JSON file's stamp to [signature].
  Future<List<SyncConflict>> _rootConflicts(StringBuffer signature) async {
    final result = <SyncConflict>[];
    final entries = await Directory(folder).list(followLinks: false).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (entity is! File || !name.endsWith('.json') || name.startsWith('.')) {
        continue;
      }
      final stat = await entity.stat();
      signature.write('$name|${stat.modified}|${stat.size}\n');
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
        result.add(
          SyncConflict(file: entity.path, projectName: 'Quick Filters'),
        );
      }
    }
    return result;
  }

  Future<Project?> _readProject(File file) async {
    try {
      return _projectFrom(jsonDecode(await file.readAsString()));
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
      if (await file.length() > maxFileBytes) return (empty, false);
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
