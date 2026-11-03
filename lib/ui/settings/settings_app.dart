import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/reminder.dart';
import '../../platform/native.dart';
import '../../platform/windows.dart';
import '../../state/prefs.dart';
import '../workspaces.dart';
import '../startup.dart';
import '../theme.dart';
import '../widgets.dart';

/// The separate Settings window (SPEC §11). Runs in its own engine and talks to the main window through device
/// prefs (watched by both) and [mainWindowChannel].
class SettingsApp extends ConsumerWidget {
  const SettingsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(prefsProvider.select((p) => p.theme));
    return MaterialApp(
      title: 'Tasklet Settings',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeModeOf(theme),
      home: const _SettingsPage(),
    );
  }
}

enum _Tab {
  general('General', Icons.tune),
  sidebar('Sidebar', Icons.view_sidebar_outlined),
  notifications('Notifications', Icons.notifications_none),
  workspaces('Workspaces', Icons.workspaces_outlined);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  _Tab _tab = _Tab.general;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      body: Column(
        children: [
          // Grows with large OS text (the page below scrolls); tabs widen to fit their label, and the row only
          // shrinks when it would be wider than the fixed window.
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in _Tab.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Pressable(
                        onTap: () => setState(() => _tab = tab),
                        selected: tab == _tab,
                        borderRadius: Radii.medium,
                        builder: (context, hovered) => Container(
                          constraints: const BoxConstraints(
                            minWidth: 92,
                            minHeight: 48,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tab == _tab
                                ? t.selected
                                : (hovered ? t.hover : Colors.transparent),
                            borderRadius: BorderRadius.circular(Radii.medium),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tab.icon,
                                size: 18,
                                color: tab == _tab ? t.accent : t.secondary,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tab.label,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyles.meta(context).copyWith(
                                  color: tab == _tab ? t.primary : t.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Each tab scrolls on its own so nothing overflows past the fixed window (SPEC §11).
          Expanded(
            child: switch (_tab) {
              _Tab.general => const _GeneralTab(),
              _Tab.sidebar => const _SidebarTab(),
              _Tab.notifications => const _NotificationsTab(),
              _Tab.workspaces => const _WorkspacesTab(),
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.description});
  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyles.body(context).copyWith(fontWeight: FontWeight.w500),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!, style: TextStyles.meta(context)),
        ],
      ],
    );
    // Large OS text doesn't fit a 150 px label column in the fixed 520 px window: put the label above instead.
    final stacked = MediaQuery.textScalerOf(context).scale(12) > 18;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 6), child],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: heading,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: child),
              ],
            ),
    );
  }
}

ListView _tabBody(List<Widget> children) => ListView(
  padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
  children: children,
);

class _GeneralTab extends ConsumerStatefulWidget {
  const _GeneralTab();

  @override
  ConsumerState<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends ConsumerState<_GeneralTab> {
  late final _name = TextEditingController(
    text: ref.read(prefsProvider).userName,
  );
  // Read up front: dispose() saves the name, and `ref` can't be used there.
  late final PrefsNotifier _prefs;
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsProvider.notifier);
    // Saved on blur (SPEC §11.1).
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) {
        ref
            .read(prefsProvider.notifier)
            .set(PrefKeys.userName, _name.text.trim());
      }
    });
  }

  @override
  void dispose() {
    _prefs.set(PrefKeys.userName, _name.text.trim());
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(prefsProvider.select((p) => p.theme));
    return _tabBody([
      _Row(
        label: 'Theme',
        child: RadioGroup<ThemeChoice>(
          groupValue: theme,
          onChanged: (v) =>
              ref.read(prefsProvider.notifier).set(PrefKeys.theme, v?.name),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (choice, label) in [
                (ThemeChoice.auto, 'Auto (match system)'),
                (ThemeChoice.light, 'Light'),
                (ThemeChoice.dark, 'Dark'),
              ])
                RadioListTile<ThemeChoice>(
                  value: choice,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  title: Text(label, style: TextStyles.body(context)),
                ),
            ],
          ),
        ),
      ),
      _Row(
        label: 'Your Name',
        description: 'Used in the Dashboard greeting.',
        child: TextField(
          controller: _name,
          focusNode: _nameFocus,
          style: TextStyles.body(context),
          decoration: const InputDecoration(hintText: 'Optional'),
          onSubmitted: (_) => _nameFocus.unfocus(),
        ),
      ),
      _Row(
        label: "What's New",
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () =>
                sendToMainWindow<void>(MainCommands.showReleaseNotes),
            child: const Text('Show Release Notes'),
          ),
        ),
      ),
    ]);
  }
}

/// Reorder and hide the primary nav items; Dashboard is pinned (SPEC §3.5). Changes apply live.
class _SidebarTab extends ConsumerWidget {
  const _SidebarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final prefs = ref.watch(prefsProvider);
    final order = prefs.navOrder;
    final hidden = prefs.navHidden;

    Widget row(NavItem item, {Widget? trailing, Key? key, Widget? handle}) =>
        Container(
          key: key,
          height: 40,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(Radii.medium),
          ),
          child: Row(
            children: [
              SizedBox(width: 20, child: handle),
              const SizedBox(width: 6),
              Icon(item.icon, size: 15, color: t.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.label, style: TextStyles.body(context)),
              ),
              ?trailing,
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      children: [
        Text(
          'Drag to reorder. Turn items off to hide them from the sidebar.',
          style: TextStyles.bodySecondary(context),
        ),
        const SizedBox(height: 12),
        row(
          NavItem.dashboard,
          trailing: Text('Always shown', style: TextStyles.meta(context)),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: order.length,
          onReorderItem: (from, to) {
            final next = [...order];
            next.insert(to, next.removeAt(from));
            ref.read(prefsProvider.notifier).set(PrefKeys.navOrder, [
              for (final n in next) n.name,
            ]);
          },
          itemBuilder: (context, i) {
            final item = order[i];
            return row(
              item,
              key: ValueKey(item),
              handle: ReorderableDragStartListener(
                index: i,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: t.tertiary,
                  ),
                ),
              ),
              trailing: SizedBox(
                height: 24,
                child: FittedBox(
                  child: Switch(
                    value: !hidden.contains(item),
                    onChanged: (on) {
                      final next = {...hidden};
                      on ? next.remove(item) : next.add(item);
                      ref.read(prefsProvider.notifier).set(PrefKeys.navHidden, [
                        for (final n in next) n.name,
                      ]);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NotificationsTab extends ConsumerStatefulWidget {
  const _NotificationsTab();

  @override
  ConsumerState<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<_NotificationsTab> {
  bool? _allowed;
  bool _sent = false;

  /// Turning reminders on, or moving the time, to an already-passed time waits until tomorrow (SPEC §11.3).
  Future<void> _save(ReminderSettings next) async {
    final notifier = ref.read(prefsProvider.notifier);
    final prefs = ref.read(prefsProvider);
    final timeOrEnableChanged =
        next.enabled &&
        (!prefs.reminders.enabled ||
            next.hour != prefs.reminders.hour ||
            next.minute != prefs.reminders.minute);
    if (timeOrEnableChanged) {
      await notifier.set(
        PrefKeys.lastReminderDay,
        markSentIfTimePassed(
          now: DateTime.now(),
          hour: next.hour,
          minute: next.minute,
          current: prefs.lastReminderDay,
        ),
      );
    }
    await notifier.set(PrefKeys.reminders, next.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = ref.watch(prefsProvider.select((p) => p.reminders));
    Widget toggle(bool value, ValueChanged<bool>? onChanged) => SizedBox(
      height: 24,
      child: FittedBox(
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
    return _tabBody([
      if (_allowed == false)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: t.warning.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(Radii.medium),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 16,
                color: t.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notifications are off. Tasklet can\'t show reminders until you allow notifications.',
                  style: TextStyles.body(context),
                ),
              ),
              TextButton(
                onPressed: openNotificationSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      _Row(
        label: 'Daily Reminder',
        description: 'One summary a day of what\'s due.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: toggle(s.enabled, (v) => _save(s.copyWith(enabled: v))),
        ),
      ),
      _Row(
        label: 'Remind Me At',
        child: Align(
          alignment: Alignment.centerLeft,
          child: _TimeSelect(
            hour: s.hour,
            minute: s.minute,
            enabled: s.enabled,
            onChanged: (h, m) => _save(s.copyWith(hour: h, minute: m)),
          ),
        ),
      ),
      _Row(
        label: 'Include Overdue Tasks',
        child: Align(
          alignment: Alignment.centerLeft,
          child: toggle(
            s.includeOverdue,
            s.enabled ? (v) => _save(s.copyWith(includeOverdue: v)) : null,
          ),
        ),
      ),
      _Row(
        label: 'Remind the Day Before',
        description: 'Also mention tasks due tomorrow.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: toggle(
            s.dayBefore,
            s.enabled ? (v) => _save(s.copyWith(dayBefore: v)) : null,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () async {
            final allowed = await sendToMainWindow<bool>(
              MainCommands.sendTestNotification,
            );
            if (mounted) {
              setState(() {
                _allowed = allowed;
                _sent = true;
              });
            }
          },
          child: const Text('Send Test Notification'),
        ),
      ),
      // Windows can't report Do Not Disturb or per-app banner settings, so say where to look.
      if (_sent && _allowed != false)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Sent. Not seeing it? Check Do Not Disturb and your notification settings.',
                  style: TextStyles.bodySecondary(context),
                ),
              ),
              TextButton(
                onPressed: openNotificationSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
    ]);
  }
}

/// Workspaces on this computer (docs/DECISIONS.md D15). Changes go to the main window, which owns the open
/// folder; the list here follows the shared prefs file.
class _WorkspacesTab extends ConsumerWidget {
  const _WorkspacesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final workspaces = prefs.workspaces;
    final open = prefs.dataFolder;
    return _tabBody([
      Text(
        'Each workspace is its own folder of plain JSON files, with its own projects, labels and quick filters. '
        'Add one with New Workspace… or Open Existing Folder… in the Workspace menu or at the top of the '
        'sidebar.',
        style: TextStyles.bodySecondary(context),
      ),
      const SizedBox(height: 12),
      for (final (i, o) in workspaces.indexed)
        _WorkspaceRow(
          entry: o,
          isOpen: open != null && sameFolder(o.folder, open),
          first: i == 0,
          last: i == workspaces.length - 1,
        ),
    ]);
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.entry,
    required this.isOpen,
    required this.first,
    required this.last,
  });
  final WorkspaceEntry entry;
  final bool isOpen;
  final bool first;
  final bool last;

  Future<void> _move(int delta) => sendToMainWindow<void>(
    MainCommands.moveWorkspace,
    {'folder': entry.folder, 'delta': delta},
  );

  Future<void> _edit(BuildContext context) async {
    final info = await showEditWorkspaceDialog(context, entry.info);
    if (info != null && info != entry.info) {
      await sendToMainWindow<void>(MainCommands.updateWorkspaceInfo, {
        'folder': entry.folder,
        ...info.toJson(),
      });
    }
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: "Remove '${entry.info.name}'?",
      message:
          'It disappears from the list on this computer. Its folder and files are not deleted; you can add it '
          'again with Open Existing Folder….',
      confirmLabel: 'Remove',
    );
    if (ok) {
      await sendToMainWindow<void>(MainCommands.removeWorkspace, entry.folder);
    }
  }

  Future<void> _changeFolder() async {
    final picked = await pickExistingFolder();
    if (picked != null) {
      await sendToMainWindow<void>(MainCommands.chooseFolder, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cloud = cloudProviderFor(entry.folder);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: WorkspaceGlyph(entry.info, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.info.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.body(context)
                            .copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (isOpen) ...[
                      const SizedBox(width: 8),
                      Text('Open', style: TextStyles.meta(context)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(entry.folder, style: TextStyles.meta(context)),
                if (cloud != null)
                  Text('Synced with $cloud', style: TextStyles.meta(context)),
              ],
            ),
          ),
          if (!isOpen)
            TextButton(
              onPressed: () => sendToMainWindow<void>(
                MainCommands.switchWorkspace,
                entry.folder,
              ),
              child: const Text('Open'),
            ),
          MenuAnchor(
            menuChildren: [
              menuItem('Edit…', onPressed: () => _edit(context)),
              menuItem(
                'Show in Folder',
                onPressed: () => openInFileManager(entry.folder),
              ),
              if (isOpen) menuItem('Change Folder…', onPressed: _changeFolder),
              const Divider(),
              menuItem('Move Up', onPressed: first ? null : () => _move(-1)),
              menuItem('Move Down', onPressed: last ? null : () => _move(1)),
              if (!isOpen) ...[
                const Divider(),
                menuItem(
                  'Remove from This Computer…',
                  danger: true,
                  onPressed: () => _remove(context),
                ),
              ],
            ],
            builder: (context, controller, _) => IconBtn(
              icon: Icons.more_horiz,
              tooltip: 'More',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact hour : minute picker that fits the small Settings window (the Material clock dial doesn't).
class _TimeSelect extends StatelessWidget {
  const _TimeSelect({
    required this.hour,
    required this.minute,
    required this.enabled,
    required this.onChanged,
  });
  final int hour;
  final int minute;
  final bool enabled;
  final void Function(int hour, int minute) onChanged;

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final minutes = {for (var m = 0; m < 60; m += 5) m, minute}.toList()
      ..sort();
    Widget select(
      String value,
      List<(String, VoidCallback)> items,
      String tooltip,
    ) => MenuAnchor(
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(120, 280)),
      ),
      menuChildren: [
        for (final (label, onPick) in items)
          MenuItemButton(
            onPressed: onPick,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: label == value ? FontWeight.w600 : null,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(56, 30)),
          child: Text('$value  ▾'),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        select(_two(hour), [
          for (var h = 0; h < 24; h++) (_two(h), () => onChanged(h, minute)),
        ], 'Hour'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            ':',
            style: TextStyles.body(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        select(_two(minute), [
          for (final m in minutes) (_two(m), () => onChanged(hour, m)),
        ], 'Minute'),
      ],
    );
  }
}
