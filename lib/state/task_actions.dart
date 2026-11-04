import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_format.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import '../core/recurrence.dart';
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
    final repeat = e.task.repeat;
    final completesRepeat =
        repeat != null && !e.task.isDone && status == TaskStatus.done;
    if (toast) {
      final before = e.task;
      _toast.show(
        completesRepeat
            ? '${e.displayId} done; the next one is due ${_nextDueLabel(e.task)}'
            : '${e.displayId} moved to ${status.label}',
        onUndo: () async {
          // Undo of a repeating completion also takes back the occurrence it created, and the rule.
          final next = completesRepeat
              ? _c.workspace?.findTask(_nextIdOf(before))
              : null;
          if (next != null) {
            await _c.deleteTask(next.project.id, next.task.id);
          }
          await _undo(
            _c.revertTask(
              before.id,
              (t) => t.copyWith(
                status: before.status,
                completedAt: before.completedAt,
                repeat: before.repeat,
              ),
            ),
          );
        },
      );
    }
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

  String _nextIdOf(Task task) => nextOccurrenceId(
    task.id,
    nextOccurrence(
      task.repeat!,
      task.repeat!.from == RepeatFrom.due ? (task.dueDate ?? _today) : _today,
      _today,
    ),
  );

  String _nextDueLabel(Task task) {
    final rule = task.repeat!;
    final anchor = rule.from == RepeatFrom.due
        ? (task.dueDate ?? _today)
        : _today;
    return relativeDateInText(nextOccurrence(rule, anchor, _today), _today);
  }

  /// Sets or clears how [e] repeats (D17).
  Future<void> setRepeat(ProjectTask e, Repeat? repeat) async {
    _withUndo(
      repeat == null
          ? '${e.displayId} no longer repeats'
          : '${e.displayId} repeats ${repeat.label.toLowerCase()}',
      e,
      (t, before) => t.copyWith(repeat: before.repeat),
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(repeat: repeat),
    );
  }

  /// Replaces [e]'s checklist (from the task panel, which saves as you go, like the title).
  Future<void> setChecklist(ProjectTask e, List<ChecklistItem> checklist) =>
      _c.updateTask(
        e.project.id,
        e.task.id,
        (t) => t.copyWith(checklist: checklist),
      );

  /// Puts [e] away until [until] (null: back now). Snoozed tasks leave boards, Today, the dashboard and reminders.
  Future<void> snooze(ProjectTask e, LocalDate? until, {String? phrase}) async {
    if (e.task.snoozedUntil == until) return;
    _withUndo(
      until == null
          ? '${e.displayId} is back'
          : '${e.displayId} snoozed until ${phrase ?? relativeDateInText(until, _today)}',
      e,
      (t, before) => t.copyWith(snoozedUntil: before.snoozedUntil),
    );
    await _c.updateTask(
      e.project.id,
      e.task.id,
      (t) => t.copyWith(snoozedUntil: until),
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
          : '${e.displayId} due ${phrase ?? relativeDateInText(due, _today)}',
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
          : '${e.displayId} starts ${relativeDateInText(start, _today)}',
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

/// Bulk edit (D17): one change to every selected task, with one Undo that reverts only what it changed on each.
extension BulkTaskActions on TaskActions {
  Future<void> bulkEdit(
    List<ProjectTask> entries,
    String message,
    Task Function(Task t) change,
    Task Function(Task now, Task before) revert,
  ) async {
    if (entries.isEmpty) return;
    final befores = [for (final e in entries) e.task];
    await _c.updateTasks([
      for (final e in entries) TaskRef(e.project.id, e.task.id),
    ], change);
    _toast.show(
      message,
      onUndo: () async {
        final missing = await _c.revertTasks({
          for (final before in befores) before.id: (t) => revert(t, before),
        });
        if (missing > 0) {
          _toast.show("Can't undo for tasks that no longer exist.");
        }
      },
    );
  }

  Future<void> bulkMove(List<ProjectTask> entries, Project to) async {
    final moves = <(String, Task)>[];
    for (final e in entries) {
      if (e.project.id == to.id) continue;
      final before = e.task;
      if (await _c.moveTaskToProject(e.project.id, e.task.id, to.id) != null) {
        moves.add((e.project.id, before));
      }
    }
    if (moves.isEmpty) return;
    _toast.show(
      'Moved ${moves.length} tasks to ${to.name}',
      onUndo: () async {
        for (final (from, before) in moves) {
          await _c.restoreMovedTask(from, to.id, before);
        }
      },
    );
  }

  Future<void> bulkDelete(List<ProjectTask> entries) async {
    final open = _ref.read(openTaskProvider);
    final deleted = <String>[];
    for (final e in entries) {
      if (open?.taskId == e.task.id) {
        _ref.read(openTaskProvider.notifier).close();
      }
      final task = await _c.deleteTask(e.project.id, e.task.id);
      if (task != null) deleted.add(task.id);
    }
    if (deleted.isEmpty) return;
    _toast.show(
      'Deleted ${deleted.length} tasks',
      duration: const Duration(seconds: 8),
      onUndo: () async {
        for (final id in deleted) {
          await _c.undoDelete(id);
        }
      },
    );
  }
}
