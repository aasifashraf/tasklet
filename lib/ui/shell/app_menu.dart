import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../platform/lifecycle.dart';
import '../../platform/native.dart';
import '../../platform/whats_new_notes.dart';
import '../../platform/windows.dart';
import '../../state/prefs.dart';
import '../../state/task_actions.dart';
import '../../state/toast.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../board/task_tiles.dart';
import '../organizations.dart';
import '../task/new_task_dialog.dart';
import '../theme.dart';
import '../whats_new.dart';

/// One menu command: label, accelerator, and action (SPEC §12). The same table builds the Windows in-window menu
/// bar, the macOS native menu bar, and the keyboard shortcuts.
class AppCommand {
  const AppCommand(
    this.label,
    this.run, {
    this.shortcut,
    this.enabled = true,
    this.checked = false,
  });
  final String label;
  final VoidCallback run;
  final SingleActivator? shortcut;
  final bool enabled;

  /// Shows a check mark (the open organization).
  final bool checked;
}

class CommandGroup {
  const CommandGroup(this.label, this.items);
  final String label;

  /// null entries are separators.
  final List<AppCommand?> items;
}

bool get _mac => Platform.isMacOS;

/// Ctrl on Windows, ⌘ on macOS.
SingleActivator accel(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !_mac, meta: _mac, shift: shift);

bool _typingInTextField() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

List<CommandGroup> buildCommands(BuildContext context, WidgetRef ref) {
  final ws = ref.read(workspaceDataProvider);
  final readOnly = ws?.readOnly ?? true;
  final prefs = ref.read(prefsProvider);

  void newTask() {
    if (ref.read(newTaskOpenProvider)) {
      return; // never wipe what's being typed (SPEC §12)
    }
    openNewTaskForLocation(context, ref);
  }

  void newProject() {
    context.go('/projects');
    ref.read(newProjectRequestProvider.notifier).fire();
  }

  void find() {
    final path = GoRouterState.of(context).uri.path;
    final onBoard =
        path == '/my-tasks' ||
        path == '/today' ||
        path.startsWith('/projects/') ||
        path.startsWith('/views/');
    if (!onBoard) context.go('/my-tasks');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(searchRequestProvider.notifier).fire(),
    );
  }

  /// Delete only acts on a focused card/row or the open panel, never while typing (SPEC §12).
  void deleteTask() {
    if (_typingInTextField() || readOnly) return;
    final target = ref.read(openTaskProvider) ?? ref.read(focusedTaskProvider);
    final w = ref.read(workspaceDataProvider);
    final project = target == null ? null : w?.projectById(target.projectId);
    final task = project?.taskById(target!.taskId);
    if (project == null || task == null) return;
    ref.read(taskActionsProvider).delete(ProjectTask(project, task));
  }

  final nav = prefs.visibleNav;
  final digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
  ];

  return [
    CommandGroup('File', [
      AppCommand(
        'New Task',
        newTask,
        shortcut: accel(LogicalKeyboardKey.keyN),
        enabled: !readOnly,
      ),
      AppCommand(
        'New Project…',
        newProject,
        shortcut: accel(LogicalKeyboardKey.keyN, shift: true),
        enabled: !readOnly,
      ),
      null,
      AppCommand(
        'Settings…',
        openSettingsWindow,
        shortcut: accel(LogicalKeyboardKey.comma),
      ),
      AppCommand('Show Data Folder', () {
        final folder = ref.read(workspaceDataProvider)?.folder;
        if (folder != null) openInFileManager(folder);
      }),
      null,
      AppCommand(
        _mac ? 'Quit Tasklet' : 'Exit',
        AppLifecycle.instance.quit,
        shortcut: _mac ? accel(LogicalKeyboardKey.keyQ) : null,
      ),
    ]),
    CommandGroup('Edit', [
      AppCommand(
        'Undo',
        () => ref.read(toastProvider.notifier).undo(),
        enabled: ref.read(toastProvider)?.onUndo != null,
      ),
      null,
      AppCommand('Find', find, shortcut: accel(LogicalKeyboardKey.keyF)),
      null,
      AppCommand(
        'Delete Task',
        deleteTask,
        shortcut: const SingleActivator(LogicalKeyboardKey.delete),
        enabled: !readOnly,
      ),
    ]),
    CommandGroup('View', [
      AppCommand(
        'Refresh',
        () => ref.read(workspaceProvider.notifier).refresh(full: true),
        shortcut: const SingleActivator(LogicalKeyboardKey.f5),
      ),
    ]),
    CommandGroup('Go', [
      for (final (i, item) in nav.indexed)
        AppCommand(
          item.label,
          () => context.go(item.route),
          shortcut: i < digits.length ? accel(digits[i]) : null,
        ),
    ]),
    CommandGroup('Organization', [
      for (final (i, o) in prefs.organizations.indexed)
        AppCommand(
          o.info.name,
          () => switchToOrganization(context, ref, o.folder),
          shortcut: organizationShortcut(i),
          checked: ws != null && sameFolder(o.folder, ws.folder),
        ),
      null,
      AppCommand('New Organization…', () => newOrganization(context, ref)),
      AppCommand('Open Existing Folder…', () => openExistingOrganization(ref)),
      if (ws != null)
        AppCommand(
          'Edit Organization…',
          () => editOrganization(context, ref, (
            folder: ws.folder,
            info: ws.organization,
          )),
          enabled: !readOnly,
        ),
      AppCommand('Manage Organizations…', openSettingsWindow),
    ]),
    CommandGroup('Window', [AppCommand('Settings', openSettingsWindow)]),
    CommandGroup('Help', [
      AppCommand("What's New", () => showWhatsNew(context, ref)),
      AppCommand(
        'About Tasklet',
        () => showAboutDialog(
          context: context,
          applicationName: 'Tasklet',
          applicationVersion: currentRelease.version,
          applicationLegalese: 'Open source under the MIT License.',
        ),
      ),
    ]),
  ];
}

/// Wraps the shell with the menu bar and keyboard shortcuts.
class AppMenu extends ConsumerWidget {
  const AppMenu({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(prefsProvider);
    ref.watch(workspaceDataProvider);
    ref.watch(toastProvider);
    final groups = buildCommands(context, ref);
    final bindings = <ShortcutActivator, VoidCallback>{
      for (final g in groups)
        for (final c in g.items)
          if (c != null && c.shortcut != null && c.enabled) c.shortcut!: c.run,
      // Ctrl+Backspace / ⌘⌫ also deletes (SPEC §12).
      accel(LogicalKeyboardKey.backspace): () {
        for (final g in groups) {
          for (final c in g.items) {
            if (c?.label == 'Delete Task' && c!.enabled) c.run();
          }
        }
      },
    };
    final body = CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );

    if (_mac) {
      return PlatformMenuBar(
        menus: [
          for (final g in groups)
            PlatformMenu(
              label: g.label,
              menus: [
                for (final section in _sections(g.items))
                  PlatformMenuItemGroup(
                    members: [
                      for (final c in section)
                        PlatformMenuItem(
                          label: c.checked ? '✓ ${c.label}' : c.label,
                          shortcut: c.shortcut,
                          onSelected: c.enabled ? c.run : null,
                        ),
                    ],
                  ),
              ],
            ),
        ],
        child: body,
      );
    }

    final t = Tokens.of(context);
    return Column(
      children: [
        Container(
          height: 28,
          decoration: BoxDecoration(
            color: t.sidebar,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              MenuBar(
                style: const MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                  elevation: WidgetStatePropertyAll(0),
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 4),
                  ),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
                ),
                children: [
                  for (final g in groups)
                    SubmenuButton(
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 12, color: t.secondary),
                        ),
                      ),
                      menuChildren: [
                        for (final c in g.items)
                          if (c == null)
                            const Divider()
                          else
                            MenuItemButton(
                              onPressed: c.enabled ? c.run : null,
                              shortcut: c.shortcut,
                              trailingIcon: c.checked
                                  ? Icon(
                                      Icons.check,
                                      size: 14,
                                      color: t.primary,
                                    )
                                  : null,
                              child: Text(
                                c.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ],
                      child: Text(
                        g.label,
                        style: TextStyle(fontSize: 12, color: t.secondary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  static List<List<AppCommand>> _sections(List<AppCommand?> items) {
    final sections = <List<AppCommand>>[[]];
    for (final c in items) {
      if (c == null) {
        sections.add([]);
      } else {
        sections.last.add(c);
      }
    }
    return sections.where((s) => s.isNotEmpty).toList();
  }
}
