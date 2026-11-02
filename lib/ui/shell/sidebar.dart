import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../platform/whats_new_notes.dart';
import '../../state/boards.dart';
import '../../state/prefs.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../icon_picker.dart';
import '../organizations.dart';
import '../pages/restore_dialog.dart';
import '../task/new_task_dialog.dart';
import '../theme.dart';
import '../whats_new.dart';
import '../widgets.dart';

/// The persistent left sidebar (SPEC §3.3).
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  String? _renaming; // 'project:<id>' or 'view:<id>'

  WorkspaceController get _controller => ref.read(workspaceProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ws = ref.watch(workspaceDataProvider);
    final prefs = ref.watch(prefsProvider);
    if (ws == null) return const SizedBox.shrink();
    final path = GoRouterState.of(context).uri.path;

    final active = ws.projects.where((p) => !p.archived).toList();
    final favorites = active.where((p) => p.favorite).toList()
      ..sort((a, b) => a.favoriteOrder.compareTo(b.favoriteOrder));
    final plain = active.where((p) => !p.favorite).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final archived = ws.projects.where((p) => p.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final pinned = ws.views.where((v) => v.inSidebar).toList()
      ..sort((a, b) => a.sidebarOrder.compareTo(b.sidebarOrder));

    final unreadNotes = prefs.whatsNewSeen != currentRelease.id;

    return Container(
      color: t.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(child: OrganizationSwitcher()),
                const SizedBox(width: 4),
                IconBtn(
                  icon: Icons.edit_square,
                  tooltip: 'New Task (Ctrl+N)',
                  onPressed: () => openNewTaskForLocation(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              children: [
                _navList(context, prefs, ws, path),
                if (pinned.isNotEmpty)
                  _Section(
                    id: 'views',
                    label: 'Quick Filters',
                    child: _Reorderable<SavedView>(
                      items: pinned,
                      keyOf: (v) => 'view:${v.id}',
                      onMove: (v, before, after) => _controller.moveView(
                        v.id,
                        before: before?.id,
                        after: after?.id,
                      ),
                      itemBuilder: (v) => _viewRow(context, v, pinned, path),
                    ),
                  ),
                if (favorites.isNotEmpty)
                  _Section(
                    id: 'favorites',
                    label: 'Favorites',
                    child: _Reorderable<Project>(
                      items: favorites,
                      keyOf: (p) => 'fav:${p.id}',
                      onMove: (p, before, after) => _controller.moveProject(
                        p.id,
                        before: before?.id,
                        after: after?.id,
                        favorites: true,
                      ),
                      itemBuilder: (p) => _projectRow(
                        context,
                        p,
                        favorites,
                        path,
                        favoritesList: true,
                      ),
                    ),
                  ),
                if (plain.isNotEmpty)
                  _Section(
                    id: 'projects',
                    label: 'Projects',
                    child: _Reorderable<Project>(
                      items: plain,
                      keyOf: (p) => 'project:${p.id}',
                      onMove: (p, before, after) => _controller.moveProject(
                        p.id,
                        before: before?.id,
                        after: after?.id,
                        favorites: false,
                      ),
                      itemBuilder: (p) => _projectRow(
                        context,
                        p,
                        plain,
                        path,
                        favoritesList: false,
                      ),
                    ),
                  ),
                if (archived.isNotEmpty)
                  _Section(
                    id: 'archived',
                    label: 'Archived',
                    child: Column(
                      children: [
                        for (final p in archived)
                          _projectRow(
                            context,
                            p,
                            archived,
                            path,
                            favoritesList: false,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (unreadNotes)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _Row(
                icon: Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: t.secondary,
                ),
                label: "What's New",
                trailing: ColorDot(color: t.accent, size: 6),
                onTap: () => showWhatsNew(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navList(
    BuildContext context,
    Prefs prefs,
    Workspace ws,
    String path,
  ) {
    final navCounts = ref.watch(navCountsProvider);
    final counts = {
      NavItem.today: navCounts.today,
      NavItem.allTasks: navCounts.allOpen,
    };
    final movable = prefs.visibleNav.skip(1).toList();

    Widget row(NavItem item) {
      final selected = item.route == '/'
          ? path == '/'
          : path == item.route || path.startsWith('${item.route}/');
      return _Row(
        key: ValueKey('navrow:${item.name}'),
        icon: Icon(
          item.icon,
          size: 15,
          color: selected
              ? Tokens.of(context).primary
              : Tokens.of(context).secondary,
        ),
        label: item.label,
        selected: selected,
        trailing: counts[item] != null && counts[item]! > 0
            ? CountText(counts[item]!)
            : null,
        onTap: () => context.go(item.route),
      );
    }

    return Column(
      children: [
        row(NavItem.dashboard),
        _Reorderable<NavItem>(
          items: movable,
          keyOf: (n) => 'nav:${n.name}',
          onMove: (item, before, after) {
            final order = [...prefs.navOrder]..remove(item);
            final index = before != null
                ? order.indexOf(before) + 1
                : (after != null ? order.indexOf(after) : 0);
            order.insert(index, item);
            ref.read(prefsProvider.notifier).set(PrefKeys.navOrder, [
              for (final n in order) n.name,
            ]);
          },
          itemBuilder: row,
        ),
      ],
    );
  }

  Widget _projectRow(
    BuildContext context,
    Project p,
    List<Project> section,
    String path, {
    required bool favoritesList,
  }) {
    final key = 'project:${p.id}';
    final selected = path == '/projects/${p.id}';
    final index = section.indexOf(p);
    List<Widget> menu() => [
      menuItem(
        p.favorite ? 'Unpin from Favorites' : 'Pin to Favorites',
        leading: Icon(
          p.favorite ? Icons.push_pin : Icons.push_pin_outlined,
          size: 14,
        ),
        onPressed: () => _controller.setFavorite(p.id, !p.favorite),
      ),
      menuItem('Rename', onPressed: () => setState(() => _renaming = key)),
      iconMenuItem(
        context,
        icon: p.icon,
        color: p.color,
        kind: GlyphKind.project,
        onPick: (icon, color) => _controller.setProjectIcon(p.id, icon, color),
      ),
      menuItem(
        'New Project…',
        onPressed: () {
          context.go('/projects');
          ref.read(newProjectRequestProvider.notifier).fire();
        },
      ),
      const Divider(),
      menuItem(
        'Move Up',
        onPressed: p.archived || index <= 0
            ? null
            : () => _controller.moveProject(
                p.id,
                before: index >= 2 ? section[index - 2].id : null,
                after: section[index - 1].id,
                favorites: favoritesList,
              ),
      ),
      menuItem(
        'Move Down',
        onPressed: p.archived || index >= section.length - 1
            ? null
            : () => _controller.moveProject(
                p.id,
                before: section[index + 1].id,
                after: index + 2 < section.length
                    ? section[index + 2].id
                    : null,
                favorites: favoritesList,
              ),
      ),
      const Divider(),
      menuItem(
        'Restore Previous Version…',
        onPressed: () => showRestoreProjectDialog(context, ref, p),
      ),
      menuItem(
        p.archived ? 'Unarchive' : 'Archive',
        onPressed: () => _controller.setArchived(p.id, !p.archived),
      ),
      menuItem(
        'Delete Project…',
        danger: true,
        onPressed: () => confirmDeleteProject(context, ref, p),
      ),
    ];
    return ContextMenuRegion(
      menuChildren: menu,
      child: _renaming == key
          ? _RenameRow(
              icon: ProjectGlyph(p),
              initial: p.name,
              onDone: (name) {
                setState(() => _renaming = null);
                if (name != null) _controller.renameProject(p.id, name);
              },
            )
          : _Row(
              icon: ProjectGlyph(p),
              label: p.name,
              selected: selected,
              onTap: () => context.go('/projects/${p.id}'),
              menuChildren: menu,
            ),
    );
  }

  Widget _viewRow(
    BuildContext context,
    SavedView v,
    List<SavedView> section,
    String path,
  ) {
    final t = Tokens.of(context);
    final key = 'view:${v.id}';
    final index = section.indexOf(v);
    List<Widget> menu() => [
      menuItem('Rename', onPressed: () => setState(() => _renaming = key)),
      colorSubmenu(
        selected: v.color,
        onPick: (c) =>
            _controller.updateView(v.id, (x) => x.copyWith(color: c)),
      ),
      menuItem(
        'Unpin from Sidebar',
        leading: const Icon(Icons.push_pin, size: 14),
        onPressed: () => _controller.setViewPinned(v.id, false),
      ),
      const Divider(),
      menuItem(
        'Move Up',
        onPressed: index <= 0
            ? null
            : () => _controller.moveView(
                v.id,
                before: index >= 2 ? section[index - 2].id : null,
                after: section[index - 1].id,
              ),
      ),
      menuItem(
        'Move Down',
        onPressed: index >= section.length - 1
            ? null
            : () => _controller.moveView(
                v.id,
                before: section[index + 1].id,
                after: index + 2 < section.length
                    ? section[index + 2].id
                    : null,
              ),
      ),
      const Divider(),
      menuItem(
        'Delete Quick Filter…',
        danger: true,
        onPressed: () => confirmDeleteView(context, ref, v),
      ),
    ];
    return ContextMenuRegion(
      menuChildren: menu,
      child: _renaming == key
          ? _RenameRow(
              icon: LayersIcon(color: t.named(v.color)),
              initial: v.name,
              onDone: (name) {
                setState(() => _renaming = null);
                if (name != null) {
                  _controller.updateView(v.id, (x) => x.copyWith(name: name));
                }
              },
            )
          : _Row(
              icon: LayersIcon(color: t.named(v.color)),
              label: v.name,
              selected: path == '/views/${v.id}',
              onTap: () => context.go('/views/${v.id}'),
              menuChildren: menu,
            ),
    );
  }
}

/// Confirms, then deletes a project (file goes to the Recycle Bin/Trash). Shared by the sidebar and Projects page.
Future<void> confirmDeleteProject(
  BuildContext context,
  WidgetRef ref,
  Project p,
) async {
  final n = p.tasks.length;
  final ok = await confirmDestructive(
    context,
    title: "Delete '${p.name}'?",
    message:
        'The project and its $n ${n == 1 ? 'task' : 'tasks'} will be moved to the '
        '${Theme.of(context).platform == TargetPlatform.macOS ? 'Trash' : 'Recycle Bin'}.',
  );
  if (!ok || !context.mounted) return;
  if (GoRouterState.of(context).uri.path == '/projects/${p.id}') {
    context.go('/projects');
  }
  await ref.read(workspaceProvider.notifier).deleteProject(p.id);
}

Future<void> confirmDeleteView(
  BuildContext context,
  WidgetRef ref,
  SavedView v,
) async {
  final ok = await confirmDestructive(
    context,
    title: "Delete '${v.name}'?",
    message: 'Only the quick filter is removed. No tasks are affected.',
  );
  if (!ok || !context.mounted) return;
  if (GoRouterState.of(context).uri.path == '/views/${v.id}') {
    context.go('/views');
  }
  await ref.read(workspaceProvider.notifier).deleteView(v.id);
}

class _Section extends ConsumerWidget {
  const _Section({required this.id, required this.label, required this.child});
  final String id;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final collapsed = prefs.sidebarSectionCollapsed(id);
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hoverable(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(prefsProvider.notifier).set(
                PrefKeys.collapsedSidebarSections,
                {...prefs.collapsedSidebarSections, id: !collapsed},
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyles.sectionLabel(context)
                          .copyWith(height: 1),
                    ),
                    const SizedBox(width: 5),
                    DisclosureTriangle(
                      collapsed: collapsed,
                      color: hovered ? t.secondary : t.tertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed) child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.trailing,
    this.onTap,
    this.menuChildren,
  });
  final Widget icon;
  final String label;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// When set, a ⋯ button appears on hover with the same menu as right-click.
  final List<Widget> Function()? menuChildren;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Hoverable(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? t.selected
                : (hovered ? t.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(width: 16, child: Center(child: icon)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected ? t.primary : t.secondary,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              ?trailing,
              if (menuChildren != null)
                MenuAnchor(
                  menuChildren: menuChildren!(),
                  builder: (context, controller, _) => Opacity(
                    opacity: hovered || controller.isOpen ? 1 : 0,
                    child: IconBtn(
                      icon: Icons.more_horiz,
                      size: 22,
                      iconSize: 14,
                      tooltip: 'More options',
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameRow extends StatelessWidget {
  const _RenameRow({
    required this.icon,
    required this.initial,
    required this.onDone,
  });
  final Widget icon;
  final String initial;
  final ValueChanged<String?> onDone;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Tokens.of(context).raised,
      border: Border.all(color: Tokens.of(context).accent),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        SizedBox(width: 16, child: Center(child: icon)),
        const SizedBox(width: 9),
        Expanded(
          child: InlineEditField(
            initial: initial,
            onCommit: onDone,
            onCancel: () => onDone(null),
          ),
        ),
      ],
    ),
  );
}

/// A drag-reorderable list whose drags start only after vertical movement, so plain clicks still navigate.
class _Reorderable<T> extends StatelessWidget {
  const _Reorderable({
    required this.items,
    required this.keyOf,
    required this.onMove,
    required this.itemBuilder,
  });
  final List<T> items;
  final String Function(T item) keyOf;

  /// Called with the moved item and its new neighbors (null at the ends).
  final void Function(T item, T? before, T? after) onMove;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    itemCount: items.length,
    proxyDecorator: (child, index, animation) => Material(
      color: Tokens.of(context).raised,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: child,
    ),
    onReorderItem: (oldIndex, newIndex) {
      if (newIndex == oldIndex) return;
      final reordered = [...items];
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, item);
      onMove(
        item,
        newIndex > 0 ? reordered[newIndex - 1] : null,
        newIndex < reordered.length - 1 ? reordered[newIndex + 1] : null,
      );
    },
    itemBuilder: (context, index) => _VerticalDragStart(
      key: ValueKey(keyOf(items[index])),
      index: index,
      child: itemBuilder(items[index]),
    ),
  );
}

class _VerticalDragStart extends ReorderableDragStartListener {
  const _VerticalDragStart({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      VerticalMultiDragGestureRecognizer(debugOwner: this);
}
