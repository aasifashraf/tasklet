import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/models.dart';
import '../../state/clock.dart';
import '../../state/task_actions.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../task/pickers.dart';
import '../theme.dart';
import '../widgets.dart';

/// Bulk edit (D17): while tasks are selected (Ctrl/⌘ or Shift + click), a bar at the bottom sets status, priority,
/// due date or project, or deletes them, with one Undo. Esc or × clears the selection.
class BulkBar extends ConsumerStatefulWidget {
  const BulkBar({super.key});

  @override
  ConsumerState<BulkBar> createState() => _BulkBarState();
}

class _BulkBarState extends ConsumerState<BulkBar> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Esc clears the selection wherever focus is, unless a menu or dialog is on top (Esc closes that first).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        ref.read(taskSelectionProvider).isEmpty ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    ref.read(taskSelectionProvider.notifier).clear();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(taskSelectionProvider);
    final ws = ref.watch(workspaceDataProvider);
    if (selection.isEmpty || ws == null) return const SizedBox.shrink();
    final entries = [
      for (final r in selection)
        if (ws.projectById(r.projectId) case final p?)
          if (p.taskById(r.taskId) case final t?) ProjectTask(p, t),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final actions = ref.read(taskActionsProvider);
    final today = ref.read(todayProvider);
    final readOnly = ws.readOnly;
    void clear() => ref.read(taskSelectionProvider.notifier).clear();
    final n = entries.length;

    Future<void> edit(
      String message,
      Task Function(Task) change,
      Task Function(Task now, Task before) revert,
    ) => actions.bulkEdit(entries, message, change, revert);

    Widget menu(String label, List<Widget> Function() items) => MenuAnchor(
      menuChildren: items(),
      builder: (context, controller, _) => TextButton(
        onPressed: readOnly
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        child: Text('$label ▾'),
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 64,
      child: Center(
        child: Material(
          color: t.raised,
          elevation: 8,
          shadowColor: t.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.medium),
            side: BorderSide(color: t.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  n == 1 ? '1 task selected' : '$n tasks selected',
                  style: TextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                menu(
                  'Status',
                  () => statusMenuItems(
                    TaskStatus.todo,
                    (s) => edit(
                      '$n tasks moved to ${s.label}',
                      (task) => task.copyWith(status: s),
                      (now, before) => now.copyWith(
                        status: before.status,
                        completedAt: before.completedAt,
                      ),
                    ),
                  ),
                ),
                menu(
                  'Priority',
                  () => priorityMenuItems(
                    Priority.none,
                    (p) => edit(
                      '$n tasks set to ${p.label}',
                      (task) => task.copyWith(priority: p),
                      (now, before) => now.copyWith(priority: before.priority),
                    ),
                  ),
                ),
                menu(
                  'Due Date',
                  () => [
                    for (final (label, date) in [
                      ('Today', today),
                      ('Tomorrow', tomorrowOf(today)),
                      ('Next Week', nextMondayAfter(today)),
                    ])
                      menuItem(
                        label,
                        onPressed: () => edit(
                          '$n tasks due ${label.toLowerCase()}',
                          // A start after the new due date would be refused; it moves to the due date.
                          (task) => task.copyWith(
                            dueDate: date,
                            startDate:
                                task.startDate != null &&
                                    task.startDate!.isAfter(date)
                                ? date
                                : task.startDate,
                          ),
                          (now, before) => now.copyWith(
                            dueDate: before.dueDate,
                            startDate: before.startDate,
                          ),
                        ),
                      ),
                    const Divider(),
                    menuItem(
                      'Remove Due Date',
                      onPressed: () => edit(
                        'Removed the due date from $n tasks',
                        (task) => task.copyWith(dueDate: null),
                        (now, before) => now.copyWith(dueDate: before.dueDate),
                      ),
                    ),
                  ],
                ),
                menu(
                  'Move to Project',
                  () => [
                    for (final p in projectOptions(ws))
                      menuItem(
                        p.name,
                        leading: ProjectGlyph(p, size: 12),
                        onPressed: () async {
                          await actions.bulkMove(entries, p);
                          clear();
                        },
                      ),
                  ],
                ),
                TextButton(
                  onPressed: readOnly
                      ? null
                      : () async {
                          await actions.bulkDelete(entries);
                          clear();
                        },
                  style: TextButton.styleFrom(foregroundColor: t.danger),
                  child: const Text('Delete'),
                ),
                IconBtn(
                  icon: Icons.close,
                  tooltip: 'Clear selection (Esc)',
                  onPressed: clear,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
