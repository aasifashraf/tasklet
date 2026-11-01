import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identifies a task by its project and id.
@immutable
class TaskRef {
  const TaskRef(this.projectId, this.taskId);
  final String projectId;
  final String taskId;

  @override
  bool operator ==(Object other) =>
      other is TaskRef &&
      other.projectId == projectId &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(projectId, taskId);
}

/// The task shown in the detail panel (SPEC §7.2); null when closed. Opening another task replaces it.
class OpenTaskNotifier extends Notifier<TaskRef?> {
  @override
  TaskRef? build() => null;

  void open(TaskRef ref) => state = ref;
  void close() => state = null;
}

final openTaskProvider = NotifierProvider<OpenTaskNotifier, TaskRef?>(
  OpenTaskNotifier.new,
);

/// A monotonically increasing signal; widgets react when it changes (e.g. "start inline project creation").
class Signal extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

/// Ask the Projects page to start an inline "New Project" row.
final newProjectRequestProvider = NotifierProvider<Signal, int>(Signal.new);

/// Ask the current board to open and focus its search field (Ctrl+F).
final searchRequestProvider = NotifierProvider<Signal, int>(Signal.new);

/// Notices dismissed for this app session (sync conflicts, hidden entries…).
class DismissedNotices extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void dismiss(String key) => state = {...state, key};
}

final dismissedNoticesProvider =
    NotifierProvider<DismissedNotices, Set<String>>(DismissedNotices.new);

/// Whether a modal (New Task dialog, menu, other dialog) is open; keyboard shortcuts stand down (SPEC §12).
class ModalDepth extends Notifier<int> {
  @override
  int build() => 0;
  void push() => state++;
  void pop() => state = state > 0 ? state - 1 : 0;
}

final modalDepthProvider = NotifierProvider<ModalDepth, int>(ModalDepth.new);

/// Whether the New Task dialog is open (Ctrl+N is a no-op then, SPEC §12).
class NewTaskOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool open) => state = open;
}

final newTaskOpenProvider = NotifierProvider<NewTaskOpen, bool>(
  NewTaskOpen.new,
);
