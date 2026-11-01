import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/colors.dart';
import '../../core/models.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../shell/sidebar.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_parts.dart';
import 'page_scaffold.dart';

/// Saved views list (SPEC §4.6).
class ViewsPage extends ConsumerStatefulWidget {
  const ViewsPage({super.key});

  @override
  ConsumerState<ViewsPage> createState() => _ViewsPageState();
}

class _ViewsPageState extends ConsumerState<ViewsPage> {
  bool _creating = false;
  String? _renaming;
  TaskletColor _newColor = TaskletColor.purple;

  WorkspaceController get _controller => ref.read(workspaceProvider.notifier);

  void _startCreate() => setState(() {
    _creating = true;
    _newColor =
        TaskletColor.rotation[Random().nextInt(TaskletColor.rotation.length)];
  });

  static String filterSummary(BoardFilters f) =>
      switch (f.activeCategoryCount) {
        0 => 'No filters',
        1 => '1 filter',
        final n => '$n filters',
      };

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceDataProvider);
    if (ws == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final editable = ws.viewsReadable && !ws.readOnly;
    final views = [...ws.views]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return PageScaffold(
      title: 'Saved Views',
      actions: [
        TextButton.icon(
          onPressed: editable ? _startCreate : null,
          icon: const Icon(Icons.add, size: 15),
          label: const Text('New View'),
        ),
      ],
      body: Column(
        children: [
          if (!ws.viewsReadable)
            const NoticeBanner(
              icon: Icons.sync_problem_outlined,
              message:
                  "views.json can't be read right now. It may still be syncing or be damaged. Views can't be "
                  'created or changed until it can be read again.',
            ),
          Expanded(
            child: views.isEmpty && !_creating
                ? EmptyState(
                    icon: Icons.layers_outlined,
                    title: 'No saved views yet',
                    message:
                        'A view is a saved set of filters across all your projects, like "Urgent this week". '
                        'Create one, then set its filters.',
                    action: FilledButton.icon(
                      onPressed: editable ? _startCreate : null,
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('New View'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      ListHeading('Saved Views', views.length),
                      if (_creating)
                        ListRowShell(
                          leading: TapMenu(
                            menuChildren: [
                              ColorGrid(
                                selected: _newColor,
                                onPick: (c) => setState(() => _newColor = c),
                              ),
                            ],
                            child: LayersIcon(
                              color: t.named(_newColor),
                              size: 15,
                            ),
                          ),
                          title: InlineEditField(
                            initial: '',
                            hint: 'View name',
                            onCommit: (name) async {
                              setState(() => _creating = false);
                              final view = await _controller.createView(
                                name,
                                _newColor,
                              );
                              // An unfiltered view isn't useful yet; go set its filters (SPEC §4.6).
                              if (context.mounted) {
                                context.go('/views/${view.id}');
                              }
                            },
                            onCancel: () => setState(() => _creating = false),
                          ),
                        ),
                      for (final v in views) _row(context, v, t, editable),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SavedView v, Tokens t, bool editable) =>
      ListRowShell(
        leading: TapMenu(
          enabled: editable,
          menuChildren: [
            ColorGrid(
              selected: v.color,
              onPick: (c) =>
                  _controller.updateView(v.id, (x) => x.copyWith(color: c)),
            ),
          ],
          child: LayersIcon(color: t.named(v.color), size: 15),
        ),
        title: _renaming == v.id
            ? InlineEditField(
                initial: v.name,
                onCommit: (name) {
                  setState(() => _renaming = null);
                  _controller.updateView(v.id, (x) => x.copyWith(name: name));
                },
                onCancel: () => setState(() => _renaming = null),
              )
            : Row(
                children: [
                  Flexible(
                    child: Text(
                      v.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.body(context),
                    ),
                  ),
                  if (v.inSidebar) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'In sidebar',
                      child: Icon(
                        Icons.push_pin_outlined,
                        size: 12,
                        color: t.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
        trailing: [
          Text(filterSummary(v.filters), style: TextStyles.meta(context)),
        ],
        onTap: _renaming == v.id ? null : () => context.go('/views/${v.id}'),
        onDoubleTap: editable ? () => setState(() => _renaming = v.id) : null,
        menuChildren: editable
            ? () => [
                menuItem(
                  v.inSidebar ? 'Unpin from Sidebar' : 'Pin to Sidebar',
                  leading: Icon(
                    v.inSidebar ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 14,
                  ),
                  onPressed: () =>
                      _controller.setViewPinned(v.id, !v.inSidebar),
                ),
                menuItem(
                  'Rename',
                  onPressed: () => setState(() => _renaming = v.id),
                ),
                colorSubmenu(
                  selected: v.color,
                  onPick: (c) =>
                      _controller.updateView(v.id, (x) => x.copyWith(color: c)),
                ),
                const Divider(),
                menuItem(
                  'Delete View…',
                  danger: true,
                  onPressed: () => confirmDeleteView(context, ref, v),
                ),
              ]
            : null,
      );
}
