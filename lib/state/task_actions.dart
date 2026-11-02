import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_format.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import 'clock.dart';
import 'toast.dart';
import 'ui_state.dart';
import 'workspace.dart';

/// Task edits triggered from menus, card chips and keyboard shortcuts, each with a precise Undo toast (SPEC §7.3).
/// Pass `toast: false` where the change is already visible (detail panel chips).
class TaskActions {
  TaskActions(this._ref);
  final Ref _ref;

  WorkspaceController get _c => _ref.read(workspaceProvider.notifier);
  ToastController get _toast => _ref.read(toastProvider.notifier);
  LocalDate get _today => _ref.read(todayProvider);

  /// Shows [message] with an Undo that reverts only what this action changed (via [revert], given the task as it
  /// is then and as it was before), so edits made meanwhile, e.g. by sync, survive.
  void _withUndo(
    String message,
    ProjectTask e,
    Task Function(Task now, Task before) revert, {
    bool toast = true,
  }) {
    if (!toast) return;
    final before = e.task;
    _toast.show(
      message,
      onUndo: () => _undo(_c.revertTask(before.id, (t) => revert(t, before))),
    );
  }

  /// Runs an undo and says so when it can't apply any more (the task or its project is gone).
  Future<void> _undo(Future<bool> undo) async {
    if (!await undo) _toast.show("Can't undo: the task no longer exists.");
  }

  Future<void> setStatus(
    ProjectTask e,
    TaskStatus status, {
    bool toast = true,
  }) async {
    if (e.task.status == status) return;
    _withUndo(
      '${e.displayId} moved to ${status.label}',
      e,
      (t, before) =>
          t.copyWith(status: before.status, completedAt: before.completedAt),
      toast: toast,
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(status: status),
    );
  }

  Future<void> setPriority(
    ProjectTask e,
    Priority priority, {
    bool toast = true,
  }) async {
    if (e.task.priority == priority) return;
    _withUndo(
      priority == Priority.none
          ? 'Removed priority from ${e.displayId}'
          : '${e.displayId} priority set to ${priority.label}',
      e,
      (t, before) => t.copyWith(priority: before.priority),
      toast: toast,
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(priority: priority),
    );
  }

  Future<void> setDue(
    ProjectTask e,
    LocalDate? due, {
    bool toast = true,
    String? phrase,
  }) async {
    if (e.task.dueDate == due) return;
    _withUndo(
      due == null
          ? 'Removed due date from ${e.displayId}'
          : '${e.displayId} due ${phrase ?? relativeDate(due, _today).toLowerCase()}',
      e,
      (t, before) => t.copyWith(dueDate: before.dueDate),
      toast: toast,
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(dueDate: due),
    );
  }

  Future<void> setStart(
    ProjectTask e,
    LocalDate? start, {
    bool toast = true,
  }) async {
    if (e.task.startDate == start) return;
    _withUndo(
      start == null
          ? 'Removed start date from ${e.displayId}'
          : '${e.displayId} starts ${relativeDate(start, _today).toLowerCase()}',
      e,
      (t, before) => t.copyWith(startDate: before.startDate),
      toast: toast,
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(startDate: start),
    );
  }

  Future<void> toggleLabel(
    ProjectTask e,
    Label label, {
    bool toast = true,
  }) async {
    final has = e.task.labelIds.contains(label.id);
    _withUndo(
      has ? 'Removed label ${label.name}' : 'Added label ${label.name}',
      e,
      // Toggle just this label back; other label changes made meanwhile stay.
      (t, _) => t.copyWith(
        labelIds: has
            ? [...t.labelIds.where((id) => id != label.id), label.id]
            : [
                for (final id in t.labelIds)
                  if (id != label.id) id,
              ],
      ),
      toast: toast,
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(
        labelIds: has
            ? [
                for (final id in t.labelIds)
                  if (id != label.id) id,
              ]
            : [...t.labelIds, label.id],
      ),
    );
  }

  Future<void> moveToProject(
    ProjectTask e,
    Project to, {
    bool toast = true,
  }) async {
    if (e.project.id == to.id) return;
    final before = e.task;
    // The open detail panel follows the task by id (DetailPanelOverlay), so a move or its Undo keeps it open.
    final moved = await _c.moveTaskToProject(e.project.id, e.task.id, to.id);
    if (moved == null || !toast) return;
    _toast.show(
      'Moved to ${to.name} as ${to.key}-${moved.number}',
      onUndo: () => _undo(_c.restoreMovedTask(e.project.id, to.id, before)),
    );
  }

  Future<ProjectTask?> duplicate(ProjectTask e) async {
    final copy = await _c.duplicateTask(e.project.id, e.task.id);
    if (copy == null) return null;
    _toast.show(
      'Duplicated as ${copy.displayId}',
      onUndo: () => _c.deleteTask(copy.project.id, copy.task.id),
    );
    return copy;
  }

  Future<void> copyId(ProjectTask e) async {
    await Clipboard.setData(ClipboardData(text: e.displayId));
    _toast.show('Copied ${e.displayId}');
  }

  /// Deletes immediately and never asks (SPEC §7.4), with an 8-second Undo that restores the exact task.
  Future<void> delete(ProjectTask e) async {
    final open = _ref.read(openTaskProvider);
    if (open?.taskId == e.task.id) _ref.read(openTaskProvider.notifier).close();
    final deleted = await _c.deleteTask(e.project.id, e.task.id);
    if (deleted == null) return;
    _toast.show(
      'Deleted ${e.displayId}',
      duration: const Duration(seconds: 8),
      onUndo: () => _undo(_c.undoDelete(deleted.id)),
    );
  }
}

final taskActionsProvider = Provider<TaskActions>(TaskActions.new);
