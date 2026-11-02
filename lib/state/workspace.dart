import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/colors.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import '../core/ordering.dart';
import '../core/project_keys.dart';
import '../core/task_ops.dart' as ops;
import '../data/backups.dart';
import '../data/folder_watcher.dart';
import '../data/workspace_store.dart';
import '../platform/trash.dart';
import 'prefs.dart';
import 'toast.dart';
import 'ui_state.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Set with `--dart-define=TASKLET_DATA_DIR=...` to open a folder directly (development and automated runs).
const _dataDirOverride = String.fromEnvironment('TASKLET_DATA_DIR');

sealed class WorkspaceState {
  const WorkspaceState();
}

/// No data folder chosen yet → onboarding (SPEC §10).
final class NoFolderState extends WorkspaceState {
  const NoFolderState();
}

final class LoadingState extends WorkspaceState {
  const LoadingState(this.folder);
  final String folder;
}

final class ReadyState extends WorkspaceState {
  const ReadyState(this.workspace);
  final Workspace workspace;
}

final class FailedState extends WorkspaceState {
  const FailedState(this.folder, this.message, {this.missing = false});
  final String folder;
  final String message;
  final bool missing;
}

/// Owns the open data folder: loading, refreshing, and every mutation (SPEC §2, §9).
///
/// Mutations are optimistic: state updates first, then the file is saved through the store's save queue.
/// External refreshes (watcher, window focus) are skipped while any save is in flight and run once it drains, so a
/// stale read can never clobber an edit that is still being written.
class WorkspaceController extends Notifier<WorkspaceState> {
  WorkspaceStore? _store;
  FolderWatcher? _watcher;
  StreamSubscription<void>? _watchSub;
  StreamSubscription<int>? _inFlightSub;
  bool _refreshPending = false;
  int _generation = 0;

  /// Bumped by every optimistic change; a refresh read that overlapped one is stale and dropped.
  int _mutations = 0;

  /// Recently deleted tasks for Undo (SPEC §2.5): in memory only, capped at 50.
  final _recentlyDeleted = <String, (String, Task)>{};

  @override
  WorkspaceState build() {
    ref.onDispose(_closeFolder);
    final folder = _dataDirOverride.isNotEmpty
        ? _dataDirOverride
        : ref.read(prefsProvider).dataFolder;
    if (folder == null) return const NoFolderState();
    Future.microtask(
      () => _open(folder, initialize: _dataDirOverride.isNotEmpty),
    );
    return LoadingState(folder);
  }

  Workspace? get workspace => switch (state) {
    ReadyState(:final workspace) => workspace,
    _ => null,
  };

  Workspace get _ws => workspace ?? (throw StateError('No workspace open'));
  DateTime get _now => DateTime.now();

  // ---------------------------------------------------------------- folder

  /// Points the app at [folder] (onboarding, Settings → Data → Change…). Prepares it (marker file) first.
  Future<void> chooseFolder(String folder) async {
    await ref.read(prefsProvider.notifier).set(PrefKeys.dataFolder, folder);
    await _open(folder, initialize: true);
  }

  Future<void> retry() async {
    final folder = switch (state) {
      FailedState(:final folder) || LoadingState(:final folder) => folder,
      ReadyState(:final workspace) => workspace.folder,
      NoFolderState() => null,
    };
    if (folder != null) await _open(folder);
  }

  Future<void> _open(String folder, {bool initialize = false}) async {
    await _closeFolder();
    final generation = ++_generation;
    state = LoadingState(folder);
    try {
      if (initialize) await WorkspaceStore.initialize(folder);
      final backupRoot = ref.read(backupDirProvider);
      final store = WorkspaceStore(
        folder,
        backups: backupRoot == null ? null : Backups(backupRoot, folder),
      );
      final ws = await store.read();
      if (generation != _generation) return;
      _store = store;
      _noteRepairs(ws);
      state = ReadyState(ws);
      _inFlightSub = store.queue.inFlightChanges.listen((n) {
        if (n == 0 && _refreshPending) unawaited(refresh());
      });
      final watcher = FolderWatcher(
        folder,
        isOwnWrite: store.queue.isRecentOwnWrite,
      );
      _watcher = watcher;
      _watchSub = watcher.changes.listen((_) => refresh());
      try {
        await watcher.start();
      } catch (_) {
        // The folder is open and usable; it just won't live-update (window focus still refreshes).
      }
    } on WorkspaceFolderMissing {
      if (generation == _generation) {
        state = FailedState(
          folder,
          "Can't find your Tasklet folder.",
          missing: true,
        );
      }
    } on FileSystemException catch (e) {
      if (generation == _generation) {
        state = FailedState(
          folder,
          "Tasklet can't read this folder: ${e.message}",
        );
      }
    } catch (e) {
      if (generation == _generation) {
        state = FailedState(folder, 'Could not open the folder: $e');
      }
    }
  }

  Future<void> _closeFolder() async {
    await _watchSub?.cancel();
    await _inFlightSub?.cancel();
    await _watcher?.dispose();
    _watchSub = null;
    _inFlightSub = null;
    _watcher = null;
    _store = null;
  }

  /// Editors with unsaved, debounced text (the task panel) register here so Quit can save it first.
  final pendingEditFlushers = <void Function()>{};

  /// Saves debounced edits now and waits until every queued write has landed (before quitting).
  Future<void> flushSaves() async {
    for (final flush in [...pendingEditFlushers]) {
      flush();
    }
    await _store?.queue.drain();
  }

  /// Re-reads the folder (watcher event, window focus, wake). Skipped while saves are in flight (SPEC §9). Only
  /// changed files are parsed again; [full] re-parses everything (the Refresh command).
  Future<void> refresh({bool full = false}) async {
    final store = _store;
    if (store == null) return;
    if (store.queue.inFlight > 0) {
      _refreshPending = true;
      return;
    }
    _refreshPending = false;
    final generation = _generation;
    final mutations = _mutations;
    try {
      final ws = await store.read(reparse: full);
      // Repairs are saved by the read itself, so report them even if this snapshot is then discarded.
      if (generation == _generation) _noteRepairs(ws);
      // An edit or save that happened during the read supersedes it.
      if (generation != _generation ||
          mutations != _mutations ||
          store.queue.inFlight > 0) {
        _refreshPending = true;
        if (store.queue.inFlight == 0) unawaited(refresh());
        return;
      }
      // An unchanged folder returns the same instance: nothing to rebuild.
      if (identical(ws, workspace)) return;
      state = ReadyState(ws);
    } on WorkspaceFolderMissing {
      state = FailedState(
        store.folder,
        "Can't find your Tasklet folder.",
        missing: true,
      );
    } catch (_) {
      // Transient (e.g. mid-sync); keep showing the last good state.
    }
  }

  void _noteRepairs(Workspace ws) {
    if (ws.repairs.isNotEmpty) {
      ref.read(repairNotesProvider.notifier).add(ws.repairs);
    }
  }

  // ---------------------------------------------------------------- saving

  void _set(Workspace next) {
    _mutations++;
    state = ReadyState(next);
  }

  Future<void> _save(Future<void> Function(WorkspaceStore store) write) async {
    final store = _store;
    if (store == null) return;
    try {
      await write(store);
    } catch (e) {
      ref
          .read(toastProvider.notifier)
          .show(
            e is UnsafeWriteException
                ? e.message
                : "Couldn't save your change: $e",
            duration: const Duration(seconds: 8),
          );
      _refreshPending = true;
      if (store.queue.inFlight == 0) unawaited(refresh());
    }
  }

  /// Replaces [project] (real or No-Project) in state and saves its file.
  Future<void> _putProject(Project project) {
    final ws = _ws;
    _set(
      project.isNoProject
          ? ws.copyWith(noProject: project)
          : ws.copyWith(
              projects: [
                for (final p in ws.projects) p.id == project.id ? project : p,
              ],
            ),
    );
    return _save((s) => s.writeProject(project));
  }

  /// Replaces several projects and saves them. [inOrder] writes one file after another and stops at the first
  /// failure: a task move lists the destination first, so a failed write can never leave the task in neither file.
  Future<void> _putProjects(List<Project> changed, {bool inOrder = false}) {
    final ws = _ws;
    final byId = {for (final p in changed) p.id: p};
    _set(
      ws.copyWith(
        projects: [for (final p in ws.projects) byId[p.id] ?? p],
        noProject: byId[noProjectId] ?? ws.noProject,
      ),
    );
    return _save((s) async {
      if (!inOrder) {
        await Future.wait([for (final p in changed) s.writeProject(p)]);
        return;
      }
      for (final p in changed) {
        await s.writeProject(p);
      }
    });
  }

  Project _project(String id) =>
      _ws.projectById(id) ?? (throw StateError('Unknown project $id'));

  // ---------------------------------------------------------------- projects

  Future<Project> createProject(String name, TaskletColor color) async {
    final ws = _ws;
    final now = _now;
    final project = Project(
      id: newId(),
      name: name.trim(),
      key: keyForNewProject(name, ws.projects),
      color: color,
      sortOrder: ws.projects.isEmpty
          ? 0
          : ws.projects
                    .map((p) => p.sortOrder)
                    .reduce((a, b) => a > b ? a : b) +
                sortOrderGap,
      createdAt: now,
      updatedAt: now,
    );
    _set(ws.copyWith(projects: [...ws.projects, project]));
    await _save((s) => s.writeProject(project));
    return project;
  }

  /// Changes a project; does nothing if it's gone (deleted here or by sync while a menu was open).
  Future<void> updateProject(String id, Project Function(Project p) change) {
    final project = workspace?.projectById(id);
    if (project == null) return Future.value();
    return _putProject(change(project).copyWith(updatedAt: _now));
  }

  Future<void> renameProject(String id, String name) =>
      updateProject(id, (p) => p.copyWith(name: name.trim()));

  Future<void> setProjectColor(String id, TaskletColor color) =>
      updateProject(id, (p) => p.copyWith(color: color));

  Future<void> setArchived(String id, bool archived) =>
      updateProject(id, (p) => p.copyWith(archived: archived));

  Future<void> setFavorite(String id, bool favorite) {
    final ws = workspace;
    if (ws == null) return Future.value();
    final maxFav = ws.projects
        .where((p) => p.favorite)
        .fold<double>(
          -sortOrderGap,
          (m, p) => p.favoriteOrder > m ? p.favoriteOrder : m,
        );
    return updateProject(
      id,
      (p) => p.copyWith(
        favorite: favorite,
        favoriteOrder: favorite ? maxFav + sortOrderGap : p.favoriteOrder,
      ),
    );
  }

  /// Moves a project between [before] and [after] (ids of its new neighbors) within the Projects or Favorites list.
  Future<void> moveProject(
    String id, {
    String? before,
    String? after,
    required bool favorites,
  }) {
    // A neighbour that vanished meanwhile counts as an open end.
    double? orderOf(String? pid) {
      final p = pid == null ? null : workspace?.projectById(pid);
      if (p == null) return null;
      return favorites ? p.favoriteOrder : p.sortOrder;
    }

    final value = sortOrderBetween(orderOf(before), orderOf(after));
    return updateProject(
      id,
      (p) => favorites
          ? p.copyWith(favoriteOrder: value)
          : p.copyWith(sortOrder: value),
    );
  }

  /// Earlier versions of a project kept by the local backups (docs/DECISIONS.md D12), newest first.
  Future<List<Backup>> projectBackups(String projectId) async =>
      await _store?.projectBackups(projectId) ?? const [];

  /// Replaces a project with an earlier version. The current version is backed up first, so this can itself be
  /// restored. The project keeps its current key and never hands out a task number again (SPEC §2.4). Tasks that
  /// have since moved to another project stay there (restoring them would put one task in two projects).
  ///
  /// Returns how many such tasks were left out, or null if the backup can't be read or belongs to another project.
  Future<int?> restoreProjectBackup(String projectId, Backup backup) async {
    final store = _store;
    final current = workspace?.projectById(projectId);
    if (store == null || current == null) return null;
    final restored = await store.readBackup(backup);
    final ws = workspace;
    if (ws == null || restored == null || restored.id != projectId) return null;
    final elsewhere = {
      for (final p in ws.allProjects)
        if (p.id != projectId)
          for (final t in p.tasks) t.id,
    };
    final tasks = [
      for (final t in restored.tasks)
        if (!elsewhere.contains(t.id)) t,
    ];
    final project = restored.copyWith(
      key: current.key,
      tasks: tasks,
      nextNumber: restored.nextNumber > current.nextNumber
          ? restored.nextNumber
          : current.nextNumber,
      updatedAt: _now,
    );
    _set(
      ws.copyWith(
        projects: [
          for (final p in ws.projects) p.id == projectId ? project : p,
        ],
        noProject: projectId == noProjectId ? project : ws.noProject,
      ),
    );
    await _save((s) => s.writeProject(project, backupFirst: true));
    return restored.tasks.length - tasks.length;
  }

  /// Earlier versions of the workspace labels or quick filters file, newest first.
  Future<List<Backup>> listBackups({required bool labels}) async =>
      await (labels ? _store?.labelsBackups() : _store?.viewsBackups()) ??
      const [];

  /// Restores workspace labels or quick filters from a backup (the current file is backed up first) and re-reads
  /// it. Returns false if it couldn't be restored (a toast says why).
  Future<bool> restoreListBackup(Backup backup, {required bool labels}) async {
    final store = _store;
    if (store == null) return false;
    var ok = true;
    await _save((s) async {
      try {
        await s.restoreListFile(backup, labels: labels);
      } catch (_) {
        ok = false;
        rethrow;
      }
    });
    if (ok) await refresh();
    return ok;
  }

  /// Deletes a project file (to the Recycle Bin/Trash; see docs/DECISIONS.md D4). Callers confirm first.
  Future<void> deleteProject(String id) async {
    final ws = workspace;
    final project = ws?.projectById(id);
    if (ws == null || project == null) return;
    _set(
      ws.copyWith(
        projects: [
          for (final p in ws.projects)
            if (p.id != id) p,
        ],
      ),
    );
    await _save((s) => s.deleteProject(project, moveToTrash: moveToOsTrash));
  }

  // ---------------------------------------------------------------- tasks

  void _datesOutOfOrder() => ref
      .read(toastProvider.notifier)
      .show("The start date can't be after the due date.");

  Future<ProjectTask> createTask({
    required String projectId,
    required String title,
    String description = '',
    TaskStatus status = TaskStatus.todo,
    Priority priority = Priority.none,
    LocalDate? startDate,
    LocalDate? dueDate,
    List<String> labelIds = const [],
  }) async {
    if (!ops.datesInOrder(startDate, dueDate)) {
      _datesOutOfOrder();
      startDate = null;
    }
    final (project, task) = ops.createTask(
      _project(projectId),
      id: newId(),
      title: title.trim(),
      description: description,
      status: status,
      priority: priority,
      startDate: startDate,
      dueDate: dueDate,
      labelIds: labelIds,
      now: _now,
    );
    await _putProject(project);
    return ProjectTask(project, task);
  }

  /// Applies [change] to a task; bumps updatedAt and maintains completedAt when the status changes. A task or
  /// project that is gone (deleted here or by sync while a menu was open) is left alone.
  Future<void> updateTask(
    String projectId,
    String taskId,
    Task Function(Task t) change,
  ) {
    final project = workspace?.projectById(projectId);
    final current = project?.taskById(taskId);
    if (project == null || current == null) return Future.value();
    var next = change(current).copyWith(updatedAt: _now);
    // Never save a start date after the due date (data that already arrived that way from sync stays editable).
    if (!ops.datesInOrder(next.startDate, next.dueDate) &&
        ops.datesInOrder(current.startDate, current.dueDate)) {
      _datesOutOfOrder();
      return Future.value();
    }
    if (next.status != current.status) {
      next = next.copyWith(completedAt: next.isDone ? _now : null);
    }
    return _putProject(ops.putTask(project, next, _now));
  }

  /// Undo of a field edit: applies [revert] to the task as it is now, wherever it lives, so fields changed since
  /// (e.g. by sync on another computer) are kept. Returns false, changing nothing, if the task no longer exists.
  Future<bool> revertTask(String taskId, Task Function(Task now) revert) async {
    final entry = workspace?.findTask(taskId);
    if (entry == null) return false;
    await _putProject(
      ops.putTask(
        entry.project,
        revert(entry.task).copyWith(updatedAt: _now),
        _now,
      ),
    );
    return true;
  }

  Future<Task?> deleteTask(String projectId, String taskId) async {
    final project = workspace?.projectById(projectId);
    final task = project?.taskById(taskId);
    if (project == null || task == null) return null;
    _recentlyDeleted.remove(taskId);
    _recentlyDeleted[taskId] = (projectId, task);
    if (_recentlyDeleted.length > 50) {
      _recentlyDeleted.remove(_recentlyDeleted.keys.first);
    }
    await _putProject(ops.removeTask(project, taskId, _now));
    return task;
  }

  /// Puts a deleted task back with its exact id, number and fields. Returns false if that's no longer possible
  /// (its project was deleted, or the workspace was closed).
  Future<bool> undoDelete(String taskId) async {
    final entry = _recentlyDeleted.remove(taskId);
    if (entry == null) return false;
    final (projectId, task) = entry;
    final project = workspace?.projectById(projectId);
    if (project == null) return false;
    await _putProject(ops.putTask(project, task, _now));
    return true;
  }

  Future<ProjectTask?> duplicateTask(String projectId, String taskId) async {
    final project = workspace?.projectById(projectId);
    final source = project?.taskById(taskId);
    if (project == null || source == null) return null;
    final (updated, copy) = ops.duplicateTask(
      project,
      source,
      newId: newId(),
      now: _now,
    );
    await _putProject(updated);
    return ProjectTask(updated, copy);
  }

  /// Re-files a task into another project. Returns the moved task (with its new number).
  Future<Task?> moveTaskToProject(
    String fromId,
    String taskId,
    String toId, {
    int? restoreNumber,
  }) async {
    final ws = workspace;
    final from = ws?.projectById(fromId);
    final to = ws?.projectById(toId);
    final task = from?.taskById(taskId);
    if (fromId == toId || ws == null || to == null || task == null) {
      return null;
    }
    final (newFrom, newTo, moved) = ops.moveTask(
      from!,
      to,
      task,
      allowedLabelIds: {for (final l in ws.labelsFor(to)) l.id},
      restoreNumber: restoreNumber,
      now: _now,
    );
    await _putProjects([newTo, newFrom], inOrder: true);
    return moved;
  }

  /// Undo of a project move: takes the task out of [currentId] and puts [snapshot] back into [originalId] with its
  /// original number if that is still free there (SPEC §7.3), otherwise a fresh one. Returns false, changing
  /// nothing, if either project or the moved task is gone.
  Future<bool> restoreMovedTask(
    String originalId,
    String currentId,
    Task snapshot,
  ) async {
    final original = workspace?.projectById(originalId);
    final current = workspace?.projectById(currentId);
    if (original == null ||
        current == null ||
        current.taskById(snapshot.id) == null) {
      return false;
    }
    final numberFree = ops.isNumberFree(
      original,
      snapshot.number,
      exceptTaskId: snapshot.id,
    );
    final restored = numberFree
        ? snapshot
        : snapshot.copyWith(number: original.nextNumber);
    await _putProjects([
      ops
          .putTask(original, restored, _now)
          .copyWith(
            nextNumber: numberFree
                ? original.nextNumber
                : original.nextNumber + 1,
          ),
      ops.removeTask(current, snapshot.id, _now),
    ], inOrder: true);
    return true;
  }

  /// Drag-and-drop: sets the dropped task's status and/or manual position, plus new positions for neighbours that
  /// had to be re-spaced to make room (see `placeInColumn`). Re-spacing isn't an edit, so those tasks keep their
  /// `updatedAt`.
  Future<void> placeTask(
    ProjectTask dropped, {
    TaskStatus? status,
    required double sortOrder,
    Map<ProjectTask, double> respaced = const {},
  }) async {
    final ws = workspace;
    if (ws == null) return;
    final changed = <String, Project>{};
    Project? projectOf(String id) => changed[id] ?? ws.projectById(id);
    for (final MapEntry(key: e, value: value) in respaced.entries) {
      final project = projectOf(e.project.id);
      final task = project?.taskById(e.task.id);
      if (project == null || task == null) continue;
      changed[project.id] = ops.putTask(
        project,
        task.copyWith(sortOrder: value),
        _now,
      );
    }
    final project = projectOf(dropped.project.id);
    final current = project?.taskById(dropped.task.id);
    if (project == null || current == null) return;
    final moved = ops.withStatus(
      current.copyWith(sortOrder: sortOrder, updatedAt: _now),
      status ?? current.status,
      _now,
    );
    changed[project.id] = ops.putTask(project, moved, _now);
    await _putProjects(changed.values.toList());
  }

  // ---------------------------------------------------------------- labels

  /// Creates a label in the workspace ([projectId] null) or in a project.
  Future<Label> createLabel(
    String name,
    TaskletColor color, {
    String? projectId,
  }) async {
    final label = Label(id: newId(), name: name.trim(), color: color);
    if (projectId == null) {
      final labels = [..._ws.labels, label];
      _set(_ws.copyWith(labels: labels));
      await _save((s) => s.writeLabels(labels));
    } else {
      await updateProject(
        projectId,
        (p) => p.copyWith(labels: [...p.labels, label]),
      );
    }
    return label;
  }

  Future<void> updateLabel(
    String labelId,
    Label Function(Label l) change, {
    String? projectId,
  }) async {
    if (projectId == null) {
      final ws = workspace;
      if (ws == null) return;
      final labels = [
        for (final l in ws.labels) l.id == labelId ? change(l) : l,
      ];
      _set(ws.copyWith(labels: labels));
      await _save((s) => s.writeLabels(labels));
    } else {
      await updateProject(
        projectId,
        (p) => p.copyWith(
          labels: [for (final l in p.labels) l.id == labelId ? change(l) : l],
        ),
      );
    }
  }

  /// Deletes a label and strips it from every task that had it (SPEC §4.8). Callers confirm first.
  Future<void> deleteLabel(String labelId, {String? projectId}) async {
    final ws = workspace;
    if (ws == null) return;
    final now = _now;
    Project strip(Project p) => p.copyWith(
      labels: [
        for (final l in p.labels)
          if (l.id != labelId) l,
      ],
      tasks: [
        for (final t in p.tasks)
          t.labelIds.contains(labelId)
              ? t.copyWith(
                  labelIds: [
                    for (final id in t.labelIds)
                      if (id != labelId) id,
                  ],
                  updatedAt: now,
                )
              : t,
      ],
      updatedAt: now,
    );
    final affected = [
      for (final p in ws.allProjects)
        if ((projectId == null || p.id == projectId) &&
            (p.labels.any((l) => l.id == labelId) ||
                p.tasks.any((t) => t.labelIds.contains(labelId))))
          strip(p),
    ];
    if (projectId == null) {
      final labels = [
        for (final l in ws.labels)
          if (l.id != labelId) l,
      ];
      _set(ws.copyWith(labels: labels));
      await _save((s) => s.writeLabels(labels));
    }
    if (affected.isNotEmpty) await _putProjects(affected);
  }

  // ---------------------------------------------------------------- views

  Future<void> _putViews(List<SavedView> views) {
    _set(_ws.copyWith(views: views));
    return _save((s) => s.writeViews(views));
  }

  Future<SavedView> createView(String name, TaskletColor color) async {
    final now = _now;
    final view = SavedView(
      id: newId(),
      name: name.trim(),
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _putViews([..._ws.views, view]);
    return view;
  }

  /// Edits and deletes of quick filters; nothing happens when no workspace is open.
  Future<void> _changeViews(
    List<SavedView> Function(List<SavedView> views) change,
  ) {
    final ws = workspace;
    if (ws == null) return Future.value();
    return _putViews(change(ws.views));
  }

  Future<void> updateView(String id, SavedView Function(SavedView v) change) =>
      _changeViews(
        (views) => [
          for (final v in views)
            v.id == id ? change(v).copyWith(updatedAt: _now) : v,
        ],
      );

  Future<void> deleteView(String id) => _changeViews(
    (views) => [
      for (final v in views)
        if (v.id != id) v,
    ],
  );

  Future<void> setViewPinned(String id, bool pinned) {
    final maxOrder = (workspace?.views ?? const <SavedView>[])
        .where((v) => v.inSidebar)
        .fold<double>(
          -sortOrderGap,
          (m, v) => v.sidebarOrder > m ? v.sidebarOrder : m,
        );
    return updateView(
      id,
      (v) => v.copyWith(
        inSidebar: pinned,
        sidebarOrder: pinned ? maxOrder + sortOrderGap : v.sidebarOrder,
      ),
    );
  }

  Future<void> moveView(String id, {String? before, String? after}) {
    // A neighbour that vanished meanwhile counts as an open end.
    double? orderOf(String? vid) => vid == null
        ? null
        : workspace?.views.where((v) => v.id == vid).firstOrNull?.sidebarOrder;
    final value = sortOrderBetween(orderOf(before), orderOf(after));
    return updateView(id, (v) => v.copyWith(sidebarOrder: value));
  }
}

/// Where local backups of workspace files are kept (`<app support>/backups`); overridden in main(). Null = none.
final backupDirProvider = Provider<String?>((ref) => null);

final workspaceProvider = NotifierProvider<WorkspaceController, WorkspaceState>(
  WorkspaceController.new,
);

/// The open workspace, or null while not ready. Most widgets watch this.
final workspaceDataProvider = Provider<Workspace?>(
  (ref) => switch (ref.watch(workspaceProvider)) {
    ReadyState(:final workspace) => workspace,
    _ => null,
  },
);
