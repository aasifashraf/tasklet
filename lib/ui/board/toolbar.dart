import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/filters.dart';
import '../../core/models.dart';
import '../../core/today_rules.dart';
import '../../state/boards.dart';
import '../../state/prefs.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../widgets.dart';

/// The secondary toolbar strip of board/list pages (SPEC §5.3, §6).
class BoardToolbar extends ConsumerStatefulWidget {
  const BoardToolbar({super.key, required this.kind});
  final BoardKind kind;

  @override
  ConsumerState<BoardToolbar> createState() => _BoardToolbarState();
}

class _BoardToolbarState extends ConsumerState<BoardToolbar> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late int _seenSearchRequest = ref.read(searchRequestProvider);

  BoardActions get _actions => BoardActions(ref, widget.kind);

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(sessionSearchProvider)[widget.kind.id] ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (ref.read(sessionSearchProvider)[widget.kind.id] == null) {
      _actions.setSearch('');
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _search.clear();
    _actions.setSearch(null);
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(boardProvider(widget.kind));
    final searchOpen = ref.watch(
      sessionSearchProvider.select((m) => m[widget.kind.id] != null),
    );
    final request = ref.watch(searchRequestProvider);
    if (request != _seenSearchRequest) {
      _seenSearchRequest = request;
      _openSearch();
    }
    if (board == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final isToday = widget.kind is TodayBoard;

    return Row(
      children: [
        if (isToday)
          const _TodayRulesButton()
        else
          _FilterButton(
            kind: widget.kind,
            count: board.filters.activeCategoryCount,
          ),
        const Spacer(),
        if (searchOpen)
          SizedBox(
            width: 240,
            height: 28,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
              },
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                style: TextStyles.body(context),
                onChanged: (v) => _actions.setSearch(v),
                decoration: InputDecoration(
                  hintText: 'Search title, ID, description',
                  prefixIcon: Icon(Icons.search, size: 15, color: t.tertiary),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  suffixIcon: IconBtn(
                    icon: Icons.close,
                    size: 22,
                    iconSize: 13,
                    tooltip: 'Close search',
                    onPressed: _closeSearch,
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 26),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          )
        else
          IconBtn(
            icon: Icons.search,
            tooltip: 'Search (Ctrl+F)',
            onPressed: _openSearch,
          ),
        if (!isToday) ...[
          const SizedBox(width: 4),
          _LayoutToggle(kind: widget.kind, layout: board.display.layout),
        ],
        const SizedBox(width: 4),
        _DisplayButton(kind: widget.kind),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Hoverable(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? t.hover : Colors.transparent,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: t.secondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: t.secondary)),
              if (badge != null && badge! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A checkable menu row that stays open and re-reads its checked state live.
class _LiveCheck extends ConsumerWidget {
  const _LiveCheck({
    required this.label,
    required this.isChecked,
    required this.onToggle,
    this.leading,
    this.enabled = true,
  });
  final String label;
  final bool Function(WidgetRef ref) isChecked;
  final void Function(WidgetRef ref) onToggle;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = isChecked(ref);
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: enabled ? () => onToggle(ref) : null,
      leadingIcon: SizedBox(width: 16, child: leading),
      trailingIcon: SizedBox(
        width: 16,
        child: checked
            ? Icon(Icons.check, size: 14, color: Tokens.of(context).primary)
            : null,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.kind, required this.count});
  final BoardKind kind;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    final board = ref.watch(boardProvider(kind));
    if (ws == null || board == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    BoardFilters current(WidgetRef r) => r.read(boardProvider(kind))!.filters;
    BoardFilters watched(WidgetRef r) => r.watch(boardProvider(kind))!.filters;
    void update(WidgetRef r, BoardFilters f) =>
        BoardActions(r, kind).setFilters(f);
    Set<T> toggle<T>(Set<T> s, T v) =>
        s.contains(v) ? ({...s}..remove(v)) : {...s, v};

    Widget submenu(String label, List<Widget> children) => SubmenuButton(
      menuChildren: children,
      leadingIcon: const SizedBox(width: 16),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );

    final projects = ws.projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final projectLabels = board.availableLabels
        .where((e) => e.$2 != null)
        .toList();
    final workspaceLabels = board.availableLabels
        .where((e) => e.$2 == null)
        .toList();

    return MenuAnchor(
      menuChildren: [
        submenu('Status', [
          for (final s in TaskStatus.values)
            _LiveCheck(
              label: s.label,
              leading: StatusIcon(s),
              isChecked: (r) => watched(r).status.contains(s),
              onToggle: (r) => update(
                r,
                current(r).copyWith(status: toggle(current(r).status, s)),
              ),
            ),
        ]),
        submenu('Priority', [
          for (final p in [
            Priority.none,
            Priority.urgent,
            Priority.high,
            Priority.medium,
            Priority.low,
          ]) ...[
            _LiveCheck(
              label: p.label,
              leading: PriorityIcon(p),
              isChecked: (r) => watched(r).priorities.contains(p),
              onToggle: (r) => update(
                r,
                current(r)
                    .copyWith(priorities: toggle(current(r).priorities, p)),
              ),
            ),
            if (p == Priority.none) const Divider(),
          ],
        ]),
        if (kind.crossProject)
          submenu('Project', [
            _LiveCheck(
              label: 'All Projects',
              isChecked: (r) => watched(r).projects.isEmpty,
              onToggle: (r) =>
                  update(r, current(r).copyWith(projects: const {})),
            ),
            _LiveCheck(
              label: 'No Project',
              leading: CubeIcon(color: t.tertiary, size: 12),
              isChecked: (r) => watched(r).projects.contains(noProjectId),
              onToggle: (r) => update(
                r,
                current(r).copyWith(
                  projects: toggleProjectFilter(
                    current(r).projects,
                    noProjectId,
                  ),
                ),
              ),
            ),
            if (projects.isNotEmpty) const Divider(),
            for (final p in projects)
              _LiveCheck(
                label: p.name,
                leading: CubeIcon(color: t.named(p.color), size: 12),
                isChecked: (r) => watched(r).projects.contains(p.id),
                onToggle: (r) => update(
                  r,
                  current(r).copyWith(
                    projects: toggleProjectFilter(current(r).projects, p.id),
                  ),
                ),
              ),
          ]),
        submenu('Label', [
          _LiveCheck(
            label: 'No Label',
            leading: Icon(Icons.circle_outlined, size: 11, color: t.tertiary),
            isChecked: (r) => watched(r).labels.contains(noLabelFilterId),
            onToggle: (r) => update(
              r,
              current(r)
                  .copyWith(labels: toggle(current(r).labels, noLabelFilterId)),
            ),
          ),
          if (board.availableLabels.isNotEmpty) const Divider(),
          for (final (l, p) in projectLabels)
            _LiveCheck(
              label: kind.crossProject ? '${l.name} (${p!.name})' : l.name,
              leading: ColorDot(color: t.named(l.color)),
              isChecked: (r) => watched(r).labels.contains(l.id),
              onToggle: (r) => update(
                r,
                current(r).copyWith(labels: toggle(current(r).labels, l.id)),
              ),
            ),
          if (projectLabels.isNotEmpty && workspaceLabels.isNotEmpty)
            const Divider(),
          for (final (l, _) in workspaceLabels)
            _LiveCheck(
              label: l.name,
              leading: ColorDot(color: t.named(l.color)),
              isChecked: (r) => watched(r).labels.contains(l.id),
              onToggle: (r) => update(
                r,
                current(r).copyWith(labels: toggle(current(r).labels, l.id)),
              ),
            ),
        ]),
        submenu('Due Date', [
          for (final d in DueFilter.values)
            _LiveCheck(
              label: d.label,
              isChecked: (r) => watched(r).due.contains(d),
              onToggle: (r) => update(
                r,
                current(r).copyWith(due: toggle(current(r).due, d)),
              ),
            ),
        ]),
        const Divider(),
        menuItem(
          'Clear Filters',
          onPressed: board.filtersActive
              ? () => update(ref, board.filters.cleared())
              : null,
        ),
      ],
      builder: (context, controller, _) => _ToolbarButton(
        icon: Icons.filter_list,
        label: 'Filter',
        badge: count,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Today's "Filter" button: the three rules, at least one always on (SPEC §4.2).
class _TodayRulesButton extends ConsumerWidget {
  const _TodayRulesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(prefsProvider.select((p) => p.todayRules));
    return MenuAnchor(
      menuChildren: [
        for (final rule in TodayRule.values)
          _LiveCheck(
            label: rule.label,
            isChecked: (r) => r.watch(prefsProvider).todayRules.contains(rule),
            enabled: !(rules.length == 1 && rules.contains(rule)),
            onToggle: (r) =>
                r.read(prefsProvider.notifier).set(PrefKeys.todayRules, [
                  for (final x in toggleTodayRule(
                    r.read(prefsProvider).todayRules,
                    rule,
                  ))
                    x.name,
                ]),
          ),
      ],
      builder: (context, controller, _) => _ToolbarButton(
        icon: Icons.filter_list,
        label: 'Filter',
        badge: rules.length < TodayRule.values.length ? rules.length : null,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _LayoutToggle extends ConsumerWidget {
  const _LayoutToggle({required this.kind, required this.layout});
  final BoardKind kind;
  final BoardLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(BoardLayout l) {
      final board = ref.read(boardProvider(kind));
      if (board != null) {
        BoardActions(ref, kind).setDisplay(board.display.copyWith(layout: l));
      }
    }

    // One button that flips the layout each click; it shows the current layout.
    final isBoard = layout == BoardLayout.board;
    return IconBtn(
      icon: isBoard ? Icons.view_kanban_outlined : Icons.view_list_rounded,
      tooltip: isBoard
          ? 'Board view. Click for List'
          : 'List view. Click for Board',
      onPressed: () => set(isBoard ? BoardLayout.list : BoardLayout.board),
    );
  }
}

class _DisplayButton extends ConsumerWidget {
  const _DisplayButton({required this.kind});
  final BoardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ViewDisplay current(WidgetRef r) => r.read(boardProvider(kind))!.display;
    ViewDisplay watched(WidgetRef r) => r.watch(boardProvider(kind))!.display;
    void set(WidgetRef r, ViewDisplay d) => BoardActions(r, kind).setDisplay(d);
    final properties = {
      DisplayProperty.id: 'Task ID',
      DisplayProperty.statusIcon: 'Status Icon',
      DisplayProperty.priority: 'Priority',
      DisplayProperty.startDate: 'Start Date',
      DisplayProperty.dueDate: 'Due Date',
      DisplayProperty.labels: 'Labels',
      if (kind.crossProject) DisplayProperty.project: 'Project',
    };

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(label, style: TextStyles.meta(context)),
    );

    return MenuAnchor(
      menuChildren: [
        heading('Order'),
        for (final o in SortOrder.values)
          _LiveCheck(
            label: o.label,
            isChecked: (r) => watched(r).order == o,
            onToggle: (r) => set(r, current(r).withOrder(o)),
          ),
        const Divider(),
        heading('Direction'),
        for (final (d, label) in [
          (SortDirection.asc, 'Ascending'),
          (SortDirection.desc, 'Descending'),
        ])
          Consumer(
            builder: (context, r, _) => _LiveCheck(
              label: label,
              enabled:
                  r.watch(boardProvider(kind))?.display.order !=
                  SortOrder.manual,
              isChecked: (r) =>
                  watched(r).order != SortOrder.manual &&
                  watched(r).direction == d,
              onToggle: (r) => set(r, current(r).copyWith(direction: d)),
            ),
          ),
        const Divider(),
        heading('Sections'),
        _LiveCheck(
          label: 'Hide Empty Sections',
          isChecked: (r) => watched(r).hideEmptySections,
          onToggle: (r) => set(
            r,
            current(r)
                .copyWith(hideEmptySections: !current(r).hideEmptySections),
          ),
        ),
        const Divider(),
        heading('Properties'),
        for (final MapEntry(key: p, value: label) in properties.entries)
          _LiveCheck(
            label: label,
            isChecked: (r) => watched(r).shows(p),
            onToggle: (r) {
              final props = {...current(r).properties};
              if (!props.remove(p)) props.add(p);
              set(r, current(r).copyWith(properties: props));
            },
          ),
        const Divider(),
        Consumer(
          builder: (context, r, _) {
            final display = r.watch(boardProvider(kind))?.display;
            final atDefault =
                display == null || display.sameAs(defaultDisplay(kind));
            return menuItem(
              'Reset to Default',
              onPressed: atDefault
                  ? null
                  : () => BoardActions(r, kind).resetDisplay(),
            );
          },
        ),
      ],
      builder: (context, controller, _) => IconBtn(
        icon: Icons.tune,
        tooltip: 'Display options',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
