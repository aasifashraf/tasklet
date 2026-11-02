import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/colors.dart';
import '../core/local_date.dart';
import '../core/merge.dart' show jsonEquals;
import '../core/models.dart';
import '../core/org_bundle.dart';
import '../core/ordering.dart';
import '../core/organization.dart';
import '../core/starter.dart';
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
  String? _openFolder;

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

  /// Points the app at [folder] (onboarding, or Settings → Organizations → Change Folder… for the open
  /// organization, which then lives there). Prepares it (marker file) first.
  Future<void> chooseFolder(String folder) async {
    final current = workspace?.folder ?? ref.read(prefsProvider).dataFolder;
    final orgs = _organizations;
    if (current != null && !orgs.any((o) => sameFolder(o.folder, folder))) {
      await _saveOrganizations([
        for (final o in orgs)
          sameFolder(o.folder, current) ? (folder: folder, info: o.info) : o,
      ]);
    }
    final starter = _starter();
    await ref.read(prefsProvider.notifier).set(PrefKeys.dataFolder, folder);
    await _open(folder, initialize: true, starter: starter);
  }

  /// Starter content for a folder about to become an organization (docs/DECISIONS.md D16); the store writes it only
  /// if the folder is empty. The sample project goes only into the first organization on this computer.
  StarterContent _starter() => starterContent(
    newId: newId,
    now: _now,
    withSampleProject: _organizations.isEmpty,
  );

  // ---------------------------------------------------------------- organizations (docs/DECISIONS.md D15)

  List<OrgEntry> get _organizations => ref.read(prefsProvider).organizations;

  Future<void> _saveOrganizations(List<OrgEntry> orgs) => ref
      .read(prefsProvider.notifier)
      .set(PrefKeys.organizations, encodeOrganizations(orgs));

  /// Opens another organization. Debounced edits are saved into the current one first.
  Future<void> switchOrganization(String folder) async {
    final current = workspace?.folder;
    if (current != null && sameFolder(current, folder)) return;
    await flushSaves();
    await ref.read(prefsProvider.notifier).set(PrefKeys.dataFolder, folder);
    await _open(folder);
  }

  /// Makes [folder] an organization on this computer and opens it: a new folder gets [identity] in its marker; an
  /// existing Tasklet folder keeps its own. Throws if the folder can't be prepared.
  Future<void> addOrganization(String folder, {OrgInfo? identity}) async {
    await WorkspaceStore.initialize(
      folder,
      organization: identity,
      starter: _starter(),
    );
    final orgs = _organizations;
    if (!orgs.any((o) => sameFolder(o.folder, folder))) {
      await _saveOrganizations([
        ...orgs,
        (folder: folder, info: identity ?? OrgInfo(name: folderName(folder))),
      ]);
    }
    await switchOrganization(folder);
  }

  /// Forgets an organization on this computer; its folder and files are untouched. The open one can't be removed.
  Future<void> removeOrganization(String folder) async {
    final current = workspace?.folder ?? ref.read(prefsProvider).dataFolder;
    if (current != null && sameFolder(current, folder)) return;
    await _saveOrganizations([
      for (final o in _organizations)
        if (!sameFolder(o.folder, folder)) o,
    ]);
  }

  /// Moves an organization up (-1) or down (1) in the switcher.
  Future<void> moveOrganization(String folder, int delta) async {
    final orgs = [..._organizations];
    final i = orgs.indexWhere((o) => sameFolder(o.folder, folder));
    final j = i + delta;
    if (i < 0 || j < 0 || j >= orgs.length) return;
    orgs.insert(j, orgs.removeAt(i));
    await _saveOrganizations(orgs);
  }

  /// Renames or re-icons an organization. The open one saves through its store (and shows at once); another one
  /// writes its folder's marker directly.
  Future<void> updateOrganization(String folder, OrgInfo info) async {
    final ws = workspace;
    if (ws != null && sameFolder(ws.folder, folder)) {
      _set(ws.copyWith(organization: info));
      unawaited(_rememberOrganization(_ws));
      return _save((s) => s.writeOrganization(info));
    }
    final before = _organizations
        .where((o) => sameFolder(o.folder, folder))
        .firstOrNull
        ?.info;
    if (before == null) return;
    try {
      await WorkspaceStore.writeOrganizationAt(folder, info, before: before);
      await _saveOrganizations([
        for (final o in _organizations)
          sameFolder(o.folder, folder) ? (folder: o.folder, info: info) : o,
      ]);
    } catch (e) {
      ref
          .read(toastProvider.notifier)
          .show(
            e is UnsafeWriteException
                ? e.message
                : e is WorkspaceFolderMissing
                ? "Can't find that organization's folder."
                : "Couldn't save the organization: $e",
            duration: const Duration(seconds: 8),
          );
    }
  }

  /// Keeps this computer's list current with the open folder's identity (it may have been renamed on another
  /// computer, or opened before organizations existed).
  Future<void> _rememberOrganization(Workspace ws) async {
    final orgs = _organizations;
    final i = orgs.indexWhere((o) => sameFolder(o.folder, ws.folder));
    final updated = [
      for (final (k, o) in orgs.indexed)
        k == i ? (folder: o.folder, info: ws.organization) : o,
      if (i < 0) (folder: ws.folder, info: ws.organization),
    ];
    final encoded = encodeOrganizations(updated);
    if (!jsonEquals(encoded, ref.read(prefsProvider)[PrefKeys.organizations])) {
      await _saveOrganizations(updated);
    }
  }

  /// Filters, search, the open task, Undo and notices belong to the folder they were made in.
  void _resetSession() {
    _recentlyDeleted.clear();
    ref.read(openTaskProvider.notifier).close();
    ref.read(repairNotesProvider.notifier).clear();
  }

  Future<void> retry() async {
    final folder = switch (state) {
      FailedState(:final folder) || LoadingState(:final folder) => folder,
      ReadyState(:final workspace) => workspace.folder,
      NoFolderState() => null,
    };
    if (folder != null) await _open(folder);
  }

  Future<void> _open(
    String folder, {
    bool initialize = false,
    StarterContent? starter,
  }) async {
    await _closeFolder();
    if (_openFolder == null || !sameFolder(_openFolder!, folder)) {
      _resetSession();
    }
    _openFolder = folder;
    final generation = ++_generation;
    state = LoadingState(folder);
    try {
      if (initialize) {
        await WorkspaceStore.initialize(folder, starter: starter);
      }
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
      unawaited(_rememberOrganization(ws));
      _inFlightSub = store.queue.inFlightChanges.listen((n) {
        if (n == 0 && _refreshPending) unawaited(refresh());
      });
      final watcher = FolderWatcher(folder, isOwnWrite: store.isOwnWrite);
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
      if (ws.organization != workspace?.organization) {
        unawaited(_rememberOrganization(ws));
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

  MoveToTrash get _trash => ref.read(trashProvider);

  // Shown when an edit would put a start date after the due date.
  void _datesOutOfOrder() => ref
      .read(toastProvider.notifier)
      .show("The start date can't be after the due date.");
}

/// Moves a deleted project's file to the Recycle Bin or Trash (false: the store keeps it in the folder's `.trash`).
/// Tests override it so they never touch the real Recycle Bin.
final trashProvider = Provider<MoveToTrash>((ref) => moveToOsTrash);

/// Where local backups of workspace files are kept (`<app support>/backups`); overridden in main(). Null = none.
final backupDirProvider = Provider<String?>((ref) => null);

final workspaceProvider = NotifierProvider<WorkspaceController, WorkspaceState>(
  WorkspaceController.new,
);

/// The folder being opened or open (the current organization), or null before one is chosen. Session state that
/// belongs to one folder (board filters, search) watches this to start empty in another organization.
final openFolderProvider = Provider<String?>(
  (ref) => switch (ref.watch(workspaceProvider)) {
    ReadyState(:final workspace) => workspace.folder,
    LoadingState(:final folder) || FailedState(:final folder) => folder,
    NoFolderState() => null,
  },
);

/// The open workspace, or null while not ready. Most widgets watch this.
final workspaceDataProvider = Provider<Workspace?>(
  (ref) => switch (ref.watch(workspaceProvider)) {
    ReadyState(:final workspace) => workspace,
    _ => null,
  },
);
