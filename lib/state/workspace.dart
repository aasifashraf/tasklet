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
import '../data/folder_watcher.dart';
import '../data/workspace_store.dart';
import '../platform/trash.dart';
import 'prefs.dart';
import 'toast.dart';

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
      final store = WorkspaceStore(folder);
      final ws = await store.read();
      if (generation != _generation) return;
      _store = store;
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
      await watcher.start();
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

  /// Re-reads the folder (watcher event, window focus, wake). Skipped while saves are in flight (SPEC §9).
  Future<void> refresh() async {
    final store = _store;
    if (store == null) return;
    if (store.queue.inFlight > 0) {
      _refreshPending = true;
      return;
    }
    _refreshPending = false;
    final generation = _generation;
    try {
      final ws = await store.read();
      // A save that started during the read supersedes it.
      if (generation != _generation || store.queue.inFlight > 0) {
        _refreshPending = true;
        return;
      }
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

  // ---------------------------------------------------------------- saving

  void _set(Workspace next) => state = ReadyState(next);

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

  Future<void> _putProjects(List<Project> changed) {
    final ws = _ws;
    final byId = {for (final p in changed) p.id: p};
    _set(
      ws.copyWith(
        projects: [for (final p in ws.projects) byId[p.id] ?? p],
        noProject: byId[noProjectId] ?? ws.noProject,
      ),
    );
    return _save(
      (s) => Future.wait([for (final p in changed) s.writeProject(p)]),
    );
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

  Future<void> updateProject(String id, Project Function(Project p) change) {
    final updated = change(_project(id)).copyWith(updatedAt: _now);
    return _putProject(updated);
  }

  Future<void> renameProject(String id, String name) =>
      updateProject(id, (p) => p.copyWith(name: name.trim()));

  Future<void> setProjectColor(String id, TaskletColor color) =>
      updateProject(id, (p) => p.copyWith(color: color));

  Future<void> setArchived(String id, bool archived) =>
      updateProject(id, (p) => p.copyWith(archived: archived));

  Future<void> setFavorite(String id, bool favorite) {
    final ws = _ws;
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
    double orderOf(String? pid) {
      final p = pid == null ? null : _ws.projectById(pid);
      return favorites ? p!.favoriteOrder : p!.sortOrder;
    }

    final value = sortOrderBetween(
      before == null ? null : orderOf(before),
      after == null ? null : orderOf(after),
    );
    return updateProject(
      id,
      (p) => favorites
          ? p.copyWith(favoriteOrder: value)
          : p.copyWith(sortOrder: value),
    );
  }

  /// Deletes a project file (to the Recycle Bin/Trash; see docs/DECISIONS.md D4). Callers confirm first.
  Future<void> deleteProject(String id) async {
    final ws = _ws;
    final project = _project(id);
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

  /// Applies [change] to a task; bumps updatedAt and maintains completedAt when the status changes.
  Future<void> updateTask(
    String projectId,
    String taskId,
    Task Function(Task t) change,
  ) {
    final project = _project(projectId);
    final current = project.taskById(taskId);
    if (current == null) return Future.value();
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

  /// Restores an exact earlier snapshot of a task (Undo).
  Future<void> restoreTaskSnapshot(String projectId, Task snapshot) {
    final project = _ws.projectById(projectId);
    if (project == null) return Future.value();
    return _putProject(ops.putTask(project, snapshot, _now));
  }

  Future<Task?> deleteTask(String projectId, String taskId) async {
    final project = _project(projectId);
    final task = project.taskById(taskId);
    if (task == null) return null;
    _recentlyDeleted.remove(taskId);
    _recentlyDeleted[taskId] = (projectId, task);
    if (_recentlyDeleted.length > 50) {
      _recentlyDeleted.remove(_recentlyDeleted.keys.first);
    }
    await _putProject(ops.removeTask(project, taskId, _now));
    return task;
  }

  /// Puts a deleted task back with its exact id, number and fields.
  Future<void> undoDelete(String taskId) async {
    final entry = _recentlyDeleted.remove(taskId);
    if (entry == null) return;
    final (projectId, task) = entry;
    final project = _ws.projectById(projectId);
    if (project == null) return;
    await _putProject(ops.putTask(project, task, _now));
  }

  Future<ProjectTask> duplicateTask(String projectId, String taskId) async {
    final project = _project(projectId);
    final (updated, copy) = ops.duplicateTask(
      project,
      project.taskById(taskId)!,
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
    if (fromId == toId) return null;
    final ws = _ws;
    final from = _project(fromId);
    final to = _project(toId);
    final task = from.taskById(taskId);
    if (task == null) return null;
    final (newFrom, newTo, moved) = ops.moveTask(
      from,
      to,
      task,
      allowedLabelIds: {for (final l in ws.labelsFor(to)) l.id},
      restoreNumber: restoreNumber,
      now: _now,
    );
    await _putProjects([newFrom, newTo]);
    return moved;
  }

  /// Undo of a project move: takes the task out of [currentId] and puts [snapshot] back into [originalId] with its
  /// original number if that is still free there (SPEC §7.3), otherwise a fresh one.
  Future<void> restoreMovedTask(
    String originalId,
    String currentId,
    Task snapshot,
  ) async {
    final original = _ws.projectById(originalId);
    final current = _ws.projectById(currentId);
    if (original == null || current == null) return;
    final numberFree = original.tasks.every(
      (t) => t.id == snapshot.id || t.number != snapshot.number,
    );
    final restored = numberFree
        ? snapshot
        : snapshot.copyWith(number: original.nextNumber);
    await _putProjects([
      ops.removeTask(current, snapshot.id, _now),
      ops
          .putTask(original, restored, _now)
          .copyWith(
            nextNumber: numberFree
                ? original.nextNumber
                : original.nextNumber + 1,
          ),
    ]);
  }

  /// Drag-and-drop: set status and/or manual position.
  Future<void> placeTask(
    String projectId,
    String taskId, {
    TaskStatus? status,
    double? sortOrder,
  }) => updateTask(
    projectId,
    taskId,
    (t) => t.copyWith(
      status: status ?? t.status,
      sortOrder: sortOrder ?? t.sortOrder,
    ),
  );

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
      final labels = [
        for (final l in _ws.labels) l.id == labelId ? change(l) : l,
      ];
      _set(_ws.copyWith(labels: labels));
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
    final ws = _ws;
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

  /// Number of tasks carrying [labelId].
  int labelUsage(String labelId) => _ws.allProjects
      .expand((p) => p.tasks)
      .where((t) => t.labelIds.contains(labelId))
      .length;

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

  Future<void> updateView(String id, SavedView Function(SavedView v) change) =>
      _putViews([
        for (final v in _ws.views)
          v.id == id ? change(v).copyWith(updatedAt: _now) : v,
      ]);

  Future<void> deleteView(String id) => _putViews([
    for (final v in _ws.views)
      if (v.id != id) v,
  ]);

  Future<void> setViewPinned(String id, bool pinned) {
    final maxOrder = _ws.views
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
    double? orderOf(String? vid) => vid == null
        ? null
        : _ws.views.firstWhere((v) => v.id == vid).sidebarOrder;
    final value = sortOrderBetween(orderOf(before), orderOf(after));
    return updateView(id, (v) => v.copyWith(sidebarOrder: value));
  }
}

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
