import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/colors.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import '../core/ordering.dart';
import '../core/task_ops.dart' as ops;
import '../core/workspace_ops.dart' as wops;
import '../data/backups.dart';
import '../data/folder_watcher.dart';
import '../data/workspace_store.dart';
import '../platform/trash.dart';
import 'prefs.dart';
import 'toast.dart';
import 'ui_state.dart';

part 'workspace_actions.dart';

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
        isOwnWrite: store.isOwnWrite,
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
      // A save that merged with another computer's version wrote more than what's on screen: show it.
      final merged = store.takeMergeNotes();
      if (merged.isNotEmpty) {
        ref.read(repairNotesProvider.notifier).add(merged);
        _refreshPending = true;
        if (store.queue.inFlight == 0) unawaited(refresh());
      }
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

  // Shown when an edit would put a start date after the due date.
  void _datesOutOfOrder() => ref
      .read(toastProvider.notifier)
      .show("The start date can't be after the due date.");
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
