part of 'workspace.dart';

/// Every user action on the open workspace (SPEC §2, §7). Each one looks things up, applies a pure rule from
/// lib/core and saves through the session in [WorkspaceController] (docs/SYSTEM_DESIGN.md section 7.2).
extension WorkspaceActions on WorkspaceController {
  // ---------------------------------------------------------------- projects

  Future<Project> createProject(
    String name,
    TaskletColor color, {
    String? icon,
  }) async {
    final ws = _ws;
    final project = wops.newProject(
      id: newId(),
      name: name,
      color: color,
      icon: icon,
      existing: ws.projects,
      now: _now,
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

  /// Sets the icon (null: the default cube) and color together, as the icon picker does. An unchanged color is
  /// left alone, so a color from a newer version survives picking only an icon.
  Future<void> setProjectIcon(String id, String? icon, TaskletColor color) =>
      updateProject(
        id,
        (p) => p.copyWith(
          icon: icon,
          clearIcon: icon == null,
          color: color == p.color ? null : color,
        ),
      );

  Future<void> setArchived(String id, bool archived) =>
      updateProject(id, (p) => p.copyWith(archived: archived));

  Future<void> setFavorite(String id, bool favorite) {
    final ws = workspace;
    if (ws == null) return Future.value();
    final last = wops.orderAfterAll([
      for (final p in ws.projects)
        if (p.favorite) p.favoriteOrder,
    ]);
    return updateProject(
      id,
      (p) => p.copyWith(
        favorite: favorite,
        favoriteOrder: favorite ? last : p.favoriteOrder,
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
    final (:project, :leftOut) = wops.restoredFromBackup(
      current: current,
      backup: restored,
      elsewhere: {
        for (final p in ws.allProjects)
          if (p.id != projectId)
            for (final t in p.tasks) t.id,
      },
      now: _now,
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
    return leftOut;
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
    final next = ops.editTask(current, change, _now);
    if (next == null) {
      _datesOutOfOrder();
      return Future.value();
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
    final (back, out) = ops.restoreMovedTask(original, current, snapshot, _now);
    await _putProjects([back, out], inOrder: true);
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
    String? icon,
    String? projectId,
  }) async {
    final label = Label(
      id: newId(),
      name: name.trim(),
      color: color,
      icon: icon,
    );
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
    final affected = [
      for (final p in ws.allProjects)
        if (projectId == null || p.id == projectId)
          ?wops.stripLabel(p, labelId, now),
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
    final last = wops.orderAfterAll([
      for (final v in workspace?.views ?? const <SavedView>[])
        if (v.inSidebar) v.sidebarOrder,
    ]);
    return updateView(
      id,
      (v) => v.copyWith(
        inSidebar: pinned,
        sidebarOrder: pinned ? last : v.sidebarOrder,
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
