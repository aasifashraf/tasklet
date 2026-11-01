import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/clock.dart';
import '../../state/task_actions.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pickers.dart';

/// The task context menu: identical on cards, list rows and Dashboard rows, in this exact order (SPEC §7.3).
List<Widget> taskMenuChildren(
  BuildContext context,
  WidgetRef ref,
  ProjectTask e,
) {
  final ws = ref.read(workspaceDataProvider);
  if (ws == null) return const [];
  final actions = ref.read(taskActionsProvider);
  final today = ref.read(todayProvider);
  final t = Tokens.of(context);
  final task = e.task;
  final readOnly = ws.readOnly;
  final available = [
    for (final l in e.project.labels) (l, e.project),
    for (final l in ws.labels) (l, null),
  ];

  return [
    menuItem(
      'Open',
      onPressed: () => ref
          .read(openTaskProvider.notifier)
          .open(TaskRef(e.project.id, task.id)),
    ),
    const Divider(),
    SubmenuButton(
      menuChildren: statusMenuItems(
        task.status,
        (s) => actions.setStatus(e, s),
      ),
      leadingIcon: const SizedBox(width: 16),
      child: const Text('Status', style: TextStyle(fontSize: 12)),
    ),
    SubmenuButton(
      menuChildren: priorityMenuItems(
        task.priority,
        (p) => actions.setPriority(e, p),
      ),
      leadingIcon: const SizedBox(width: 16),
      child: const Text('Priority', style: TextStyle(fontSize: 12)),
    ),
    SubmenuButton(
      menuChildren: [
        ...quickDateItems(
          today,
          task.dueDate,
          (d, phrase) => actions.setDue(e, d, phrase: phrase),
          earliest: task.startDate,
        ),
        const Divider(),
        menuItem(
          'Remove Due Date',
          onPressed: task.dueDate == null
              ? null
              : () => actions.setDue(e, null),
        ),
      ],
      leadingIcon: const SizedBox(width: 16),
      child: const Text('Due Date', style: TextStyle(fontSize: 12)),
    ),
    SubmenuButton(
      menuChildren: available.isEmpty
          ? const []
          : labelMenuItems(
              available,
              task.labelIds,
              (l) => actions.toggleLabel(e, l),
              t,
            ),
      leadingIcon: const SizedBox(width: 16),
      child: Text(
        'Labels',
        style: TextStyle(
          fontSize: 12,
          color: available.isEmpty ? t.tertiary : null,
        ),
      ),
    ),
    SubmenuButton(
      menuChildren: projectMenuItems(
        projectOptions(ws, alsoInclude: e.project.id),
        e.project.id,
        (p) => actions.moveToProject(e, p),
        t,
      ),
      leadingIcon: const SizedBox(width: 16),
      child: const Text('Move to Project', style: TextStyle(fontSize: 12)),
    ),
    const Divider(),
    menuItem(
      'Duplicate',
      onPressed: readOnly ? null : () => actions.duplicate(e),
    ),
    menuItem('Copy ID', onPressed: () => actions.copyId(e)),
    const Divider(),
    menuItem(
      'Delete',
      danger: true,
      shortcut: const SingleActivator(LogicalKeyboardKey.delete),
      onPressed: readOnly ? null : () => actions.delete(e),
    ),
  ];
}
