import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_format.dart';
import '../../core/filters.dart';
import '../../core/models.dart';
import '../../state/clock.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../theme.dart';
import 'app_menu.dart';

/// One row of the command palette: a command, a place or a task.
class _Entry {
  const _Entry({
    required this.title,
    required this.kind,
    required this.run,
    this.leading,
    this.hint,
  });
  final String title;

  /// What it is ("File", "Project", "WEB-12"): shown on the right and searched too.
  final String kind;
  final VoidCallback run;
  final Widget? leading;
  final String? hint;
}

/// Ctrl+K (⌘K): one box to run any command from the menus, open any project or quick filter, or open any task by
/// ID or title. Arrow keys move, Enter runs, Esc closes.
Future<void> showCommandPalette(
  BuildContext context,
  WidgetRef ref,
  List<CommandGroup> groups,
) => showDialog<void>(
  context: context,
  barrierColor: Tokens.of(context).backdrop,
  builder: (_) => _CommandPalette(groups: groups),
);

/// Ctrl+Shift+F (Edit → Search All Tasks…): the same box, tasks only, from every project (Done tasks and archived
/// projects included), each with its project, status and due date.
Future<void> showTaskSearch(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Tokens.of(context).backdrop,
  builder: (_) => const _CommandPalette(groups: [], tasksOnly: true),
);

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette({required this.groups, this.tasksOnly = false});
  final List<CommandGroup> groups;
  final bool tasksOnly;

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  static const _rowHeight = 34.0;
  static const _maxTasks = 30;
  static const _maxSearchResults = 200;
  final _scroll = ScrollController();
  String _query = '';
  int _selected = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Runs [action] after the palette has closed, so commands that open dialogs or move focus start from the
  /// window they came from.
  VoidCallback _close(VoidCallback action) => () {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  };

  List<_Entry> _entries() {
    final ws = ref.read(workspaceDataProvider);
    final query = SearchQuery(_query);
    final t = Tokens.of(context);
    final router = GoRouter.of(context);
    final entries = <_Entry>[
      if (!widget.tasksOnly)
        for (final g in widget.groups)
          for (final c in g.items)
            if (c != null &&
                c.enabled &&
                c.label != 'Command Palette…' &&
                c.label != 'Search All Tasks…')
              _Entry(
                title: c.label,
                kind: g.label,
                hint: c.shortcut == null ? null : shortcutLabel(c.shortcut!),
                leading: Icon(
                  Icons.keyboard_command_key,
                  size: 14,
                  color: t.tertiary,
                ),
                run: _close(c.run),
              ),
      if (ws != null && !widget.tasksOnly) ...[
        for (final p in ws.projects)
          _Entry(
            title: p.name,
            kind: p.archived ? 'Archived project' : 'Project',
            leading: ProjectGlyph(p, size: 14),
            run: _close(() => router.go('/projects/${p.id}')),
          ),
        for (final v in ws.views)
          _Entry(
            title: v.name,
            kind: 'Quick filter',
            leading: ViewGlyph(v, size: 14),
            run: _close(() => router.go('/views/${v.id}')),
          ),
      ],
    ];
    final matching = [
      for (final e in entries)
        if (query.matchesText('${e.title} ${e.kind}')) e,
    ];
    // Tasks only once something is typed; a workspace can hold 100,000 of them.
    if (ws != null && !query.isEmpty) {
      final limit = widget.tasksOnly ? _maxSearchResults : _maxTasks;
      var found = 0;
      for (final p in ws.allProjects) {
        for (final task in p.tasks) {
          final entry = ProjectTask(p, task);
          if (!query.matches(entry)) continue;
          matching.add(
            _Entry(
              title: task.title,
              kind: entry.displayId,
              hint: widget.tasksOnly ? _taskHint(entry) : null,
              leading: StatusIcon(task.status, size: 14),
              run: _close(
                () => ref
                    .read(openTaskProvider.notifier)
                    .open(TaskRef(p.id, task.id)),
              ),
            ),
          );
          if (++found >= limit) break;
        }
        if (found >= limit) break;
      }
    }
    return matching;
  }

  /// Where a search result lives and how it stands: "Website · In Progress · due Nov 5".
  String _taskHint(ProjectTask e) => [
    e.project.name,
    e.task.status.label,
    if (e.task.dueDate case final due?)
      'due ${relativeDateInText(due, ref.read(todayProvider))}',
  ].join(' · ');

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    final top = _selected * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final entries = _entries();
    if (_selected >= entries.length) _selected = 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, entries.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, entries.length),
      },
      child: Dialog(
        alignment: const Alignment(0, -0.6),
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  autofocus: true,
                  style: TextStyles.bodyLarge(context),
                  decoration: InputDecoration(
                    hintText: widget.tasksOnly
                        ? 'Search all tasks by title, ID, description or checklist'
                        : 'Type a command, project, quick filter or task',
                    prefixIcon: Icon(Icons.search, size: 16, color: t.tertiary),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (q) => setState(() {
                    _query = q;
                    _selected = 0;
                  }),
                  onSubmitted: (_) {
                    if (entries.isNotEmpty) entries[_selected].run();
                  },
                ),
              ),
              Divider(height: 1, color: t.border),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _query.trim().isEmpty
                        ? 'Type to search every task in this workspace, Done ones and archived projects included.'
                        : 'Nothing matches "${_query.trim()}".',
                    style: TextStyles.bodySecondary(context),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _rowHeight * 10),
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemExtent: _rowHeight,
                    itemCount: entries.length,
                    itemBuilder: (context, i) =>
                        _row(context, entries[i], i == _selected, i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Entry e, bool selected, int index) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _selected = index),
      child: GestureDetector(
        onTap: e.run,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? t.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.small),
          ),
          child: Row(
            children: [
              SizedBox(width: 18, child: Center(child: e.leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.body(context),
                ),
              ),
              const SizedBox(width: 12),
              if (e.hint != null) ...[
                Flexible(
                  child: Text(
                    e.hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.meta(context),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Text(e.kind, style: TextStyles.meta(context)),
            ],
          ),
        ),
      ),
    );
  }
}
