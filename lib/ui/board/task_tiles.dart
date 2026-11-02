import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../state/clock.dart';
import '../../state/task_actions.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../task/pickers.dart';
import '../task/task_menu.dart';
import '../theme.dart';
import '../widgets.dart';

/// The task whose card/row has keyboard focus (for the Delete shortcut, SPEC §12).
class FocusedTask extends Notifier<TaskRef?> {
  @override
  TaskRef? build() => null;
  void set(TaskRef? ref) => state = ref;

  /// Clears the focused task if it is still [ref].
  void clearIf(TaskRef ref) {
    if (state == ref) state = null;
  }
}

final focusedTaskProvider = NotifierProvider<FocusedTask, TaskRef?>(
  FocusedTask.new,
);

/// Color for a due date: red if overdue (and not done), orange if due today (SPEC §4.1, §9).
Color? dueColor(Task task, LocalDate today, Tokens t) {
  final due = task.dueDate;
  if (due == null || task.isDone) return null;
  if (due.isBefore(today)) return t.danger;
  if (due == today) return t.warning;
  return null;
}

/// The combined date pill (SPEC §8.6).
Widget? datePill(
  BuildContext context,
  Task task,
  LocalDate today, {
  required bool start,
  required bool due,
}) {
  final label = datePillLabel(
    start ? task.startDate : null,
    due ? task.dueDate : null,
    today,
  );
  if (label == null) return null;
  final t = Tokens.of(context);
  final color = due ? dueColor(task, today, t) : null;
  return Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 11,
          color: color ?? t.secondary,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: color ?? t.secondary),
        ),
      ],
    ),
  );
}

List<Label> labelsOf(Workspace ws, Task task) => [
  for (final id in task.labelIds) ?ws.labelById(id),
];

/// What a card or row needs from the workspace, compared by value so a tile rebuilds only when its own labels
/// change (renamed, recolored, deleted) or the folder turns read-only, not on every edit elsewhere.
typedef _TileWorkspace = ({bool readOnly, String labels});

_TileWorkspace? _tileWorkspace(Workspace? ws, Task task) => ws == null
    ? null
    : (
        readOnly: ws.readOnly,
        labels: [
          for (final l in labelsOf(ws, task))
            '${l.id}/${l.name}/${l.color.name}',
        ].join('|'),
      );

/// Kanban card content (SPEC §8.6). Interaction (drag/click) is added by the board.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.entry,
    required this.display,
    required this.crossProject,
    this.lifted = false,
  });
  final ProjectTask entry;
  final ViewDisplay display;
  final bool crossProject;
  final bool lifted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final today = ref.watch(todayProvider);
    ref.watch(
      workspaceDataProvider.select((ws) => _tileWorkspace(ws, entry.task)),
    );
    final ws = ref.read(workspaceDataProvider);
    final isOpen = ref.watch(
      openTaskProvider.select((open) => open?.taskId == entry.task.id),
    );
    final actions = ref.read(taskActionsProvider);
    final task = entry.task;
    final readOnly = ws?.readOnly ?? true;
    final labels = ws == null ? <Label>[] : labelsOf(ws, task);

    final chips = <Widget>[
      if (display.shows(DisplayProperty.priority))
        PriorityPicker(
          priority: task.priority,
          iconOnly: true,
          enabled: !readOnly,
          onPick: (p) => actions.setPriority(entry, p),
        ),
      ?datePill(
        context,
        task,
        today,
        start: display.shows(DisplayProperty.startDate),
        due: display.shows(DisplayProperty.dueDate),
      ),
      if (display.shows(DisplayProperty.labels) && labels.isNotEmpty)
        labelsChipContent(context, labels),
      if (crossProject &&
          display.shows(DisplayProperty.project) &&
          !entry.project.isNoProject)
        PropChip(
          icon: ProjectGlyph(entry.project, size: 12),
          label: entry.project.name,
          maxLabelWidth: 120,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isOpen ? Color.alphaBlend(t.openHighlight, t.raised) : t.raised,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (display.shows(DisplayProperty.id)) ...[
            Text(entry.displayId, style: TextStyles.meta(context)),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (display.shows(DisplayProperty.statusIcon)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: StatusPicker(
                    status: task.status,
                    iconOnly: true,
                    enabled: !readOnly,
                    onPick: (s) => actions.setStatus(entry, s),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Tooltip(
                  message: task.title,
                  waitDuration: const Duration(milliseconds: 800),
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.primary,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (final (i, c) in chips.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      c,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// List-layout row (SPEC §5.2).
class TaskRow extends ConsumerWidget {
  const TaskRow({
    super.key,
    required this.entry,
    required this.display,
    required this.crossProject,
  });
  final ProjectTask entry;
  final ViewDisplay display;
  final bool crossProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final today = ref.watch(todayProvider);
    ref.watch(
      workspaceDataProvider.select((ws) => _tileWorkspace(ws, entry.task)),
    );
    final ws = ref.read(workspaceDataProvider);
    final isOpen = ref.watch(
      openTaskProvider.select((open) => open?.taskId == entry.task.id),
    );
    final actions = ref.read(taskActionsProvider);
    final task = entry.task;
    final readOnly = ws?.readOnly ?? true;
    final labels = ws == null ? <Label>[] : labelsOf(ws, task);
    final taskRef = TaskRef(entry.project.id, task.id);

    return ContextMenuRegion(
      menuChildren: () => taskMenuChildren(context, ref, entry),
      child: TaskFocus(
        taskRef: taskRef,
        builder: (focused) => Hoverable(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(openTaskProvider.notifier).open(taskRef),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isOpen
                    ? t.openHighlight
                    : (hovered ? t.hover : Colors.transparent),
                border: focused
                    ? Border.all(color: t.accent.withValues(alpha: 0.6))
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (display.shows(DisplayProperty.priority)) ...[
                    NoDragZone(
                      child: PriorityPicker(
                        priority: task.priority,
                        iconOnly: true,
                        enabled: !readOnly,
                        onPick: (p) => actions.setPriority(entry, p),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (display.shows(DisplayProperty.statusIcon)) ...[
                    StatusPicker(
                      status: task.status,
                      iconOnly: true,
                      enabled: !readOnly,
                      onPick: (s) => actions.setStatus(entry, s),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (display.shows(DisplayProperty.id)) ...[
                    SizedBox(
                      width: 64,
                      child: Text(
                        entry.displayId,
                        style: TextStyles.meta(context),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: t.primary),
                    ),
                  ),
                  ?datePill(
                    context,
                    task,
                    today,
                    start: display.shows(DisplayProperty.startDate),
                    due: display.shows(DisplayProperty.dueDate),
                  ),
                  if (display.shows(DisplayProperty.labels) &&
                      labels.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    labelsChipContent(context, labels),
                  ],
                  if (crossProject &&
                      display.shows(DisplayProperty.project) &&
                      !entry.project.isNoProject) ...[
                    const SizedBox(width: 6),
                    PropChip(
                      icon: ProjectGlyph(entry.project, size: 12),
                      label: entry.project.name,
                      maxLabelWidth: 120,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes a card/row keyboard-focusable and reports focus for the Delete shortcut; restores focus after the detail
/// panel closes (SPEC §7.2).
class TaskFocus extends ConsumerStatefulWidget {
  const TaskFocus({super.key, required this.taskRef, required this.builder});
  final TaskRef taskRef;
  final Widget Function(bool focused) builder;

  @override
  ConsumerState<TaskFocus> createState() => _TaskFocusState();
}

class _TaskFocusState extends ConsumerState<TaskFocus> {
  final _node = FocusNode();
  bool _focused = false;

  // Held directly: focus can change while this widget is being torn down, when `ref` is no longer usable.
  late final FocusedTask _focusedTask = ref.read(focusedTaskProvider.notifier);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _focusedTask;
  }

  @override
  Widget build(BuildContext context) {
    // When the panel for this task closes, put focus back here.
    ref.listen(openTaskProvider, (prev, next) {
      if (prev?.taskId == widget.taskRef.taskId && next == null) {
        _node.requestFocus();
      }
    });
    return Focus(
      focusNode: _node,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
        if (f) {
          _focusedTask.set(widget.taskRef);
        } else {
          _focusedTask.clearIf(widget.taskRef);
        }
      },
      child: Listener(
        onPointerDown: (_) => _node.requestFocus(),
        child: widget.builder(_focused),
      ),
    );
  }
}
