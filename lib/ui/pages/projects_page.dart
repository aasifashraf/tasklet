import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/colors.dart';
import '../../core/models.dart';
import '../../core/project_keys.dart';
import '../../state/prefs.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../icon_picker.dart';
import '../organizations.dart';
import '../shell/sidebar.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_parts.dart';
import 'page_scaffold.dart';
import 'restore_dialog.dart';

/// Projects list (SPEC §4.5).
class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  bool _creating = false;
  String? _renaming;
  TaskletColor _newColor = TaskletColor.blue;
  String? _newIcon;
  String _draftName = '';
  int _seenRequest = 0;

  WorkspaceController get _controller => ref.read(workspaceProvider.notifier);

  void _startCreate() => setState(() {
    _creating = true;
    _draftName = '';
    _newIcon = null;
    _newColor =
        TaskletColor.rotation[Random().nextInt(TaskletColor.rotation.length)];
  });

  @override
  void initState() {
    super.initState();
    _seenRequest = ref.read(newProjectRequestProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceDataProvider);
    final showArchived = ref.watch(
      prefsProvider.select((p) => p.projectsShowArchived),
    );
    final request = ref.watch(newProjectRequestProvider);
    if (request != _seenRequest) {
      _seenRequest = request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (showArchived) {
          ref
              .read(prefsProvider.notifier)
              .set(PrefKeys.projectsShowArchived, false);
        }
        _startCreate();
      });
    }
    if (ws == null) return const SizedBox.shrink();
    final projects =
        ws.projects.where((p) => p.archived == showArchived).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final t = Tokens.of(context);

    return PageScaffold(
      title: 'Projects',
      actions: [
        PillToggle<bool>(
          options: const {false: 'Active', true: 'Archived'},
          selected: showArchived,
          onChanged: (v) {
            setState(() => _creating = false);
            ref
                .read(prefsProvider.notifier)
                .set(PrefKeys.projectsShowArchived, v);
          },
        ),
        if (!showArchived)
          TextButton.icon(
            onPressed: ws.readOnly ? null : _startCreate,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('New Project'),
          ),
      ],
      body: projects.isEmpty && !_creating
          ? EmptyState(
              icon: Icons.view_in_ar_outlined,
              title: showArchived ? 'No archived projects' : 'No projects yet',
              message: showArchived
                  ? 'Archive a project from its ⋯ menu to tidy it away. Archived projects keep their tasks.'
                  : 'Projects group related tasks and give them short IDs like WEB-12. '
                        'Create one to get started.',
              action: showArchived
                  ? null
                  : FilledButton.icon(
                      onPressed: ws.readOnly ? null : _startCreate,
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('New Project'),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                ListHeading(
                  showArchived ? 'Archived Projects' : 'Active Projects',
                  projects.length,
                ),
                if (_creating) _createRow(context, ws, t),
                for (final p in projects) _row(context, p, t),
              ],
            ),
    );
  }

  Widget _createRow(BuildContext context, Workspace ws, Tokens t) =>
      ListRowShell(
        leading: IconPickerButton(
          icon: _newIcon,
          color: _newColor,
          kind: GlyphKind.project,
          onPick: (icon, color) => setState(() {
            _newIcon = icon;
            _newColor = color;
          }),
        ),
        title: InlineEditField(
          initial: '',
          hint: 'Project name',
          onChanged: (v) => setState(() => _draftName = v),
          onCommit: (name) async {
            setState(() => _creating = false);
            await _controller.createProject(name, _newColor, icon: _newIcon);
          },
          onCancel: () => setState(() => _creating = false),
        ),
        trailing: [
          if (_draftName.trim().isNotEmpty)
            Text(
              'Task IDs: ${keyForNewProject(_draftName, ws.projects)}-1',
              style: TextStyles.meta(context),
            ),
        ],
      );

  Widget _row(BuildContext context, Project p, Tokens t) {
    final done = p.tasks.where((x) => x.isDone).length;
    final readOnly = ref.read(workspaceDataProvider)?.readOnly ?? true;
    return ListRowShell(
      leading: IconPickerButton(
        enabled: !readOnly,
        icon: p.icon,
        color: p.color,
        kind: GlyphKind.project,
        onPick: (icon, color) => _controller.setProjectIcon(p.id, icon, color),
      ),
      title: _renaming == p.id
          ? InlineEditField(
              initial: p.name,
              onCommit: (name) {
                setState(() => _renaming = null);
                _controller.renameProject(p.id, name);
              },
              onCancel: () => setState(() => _renaming = null),
            )
          : Row(
              children: [
                Flexible(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body(context),
                  ),
                ),
                const SizedBox(width: 8),
                Text(p.key, style: TextStyles.meta(context)),
                if (p.favorite) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.star_rounded, size: 13, color: t.tertiary),
                ],
              ],
            ),
      trailing: [ProgressCell(done: done, total: p.tasks.length)],
      onTap: _renaming == p.id ? null : () => context.go('/projects/${p.id}'),
      onDoubleTap: readOnly ? null : () => setState(() => _renaming = p.id),
      menuChildren: readOnly
          ? null
          : () => [
              menuItem(
                p.favorite ? 'Unpin from Favorites' : 'Pin to Favorites',
                leading: Icon(
                  p.favorite ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 14,
                ),
                onPressed: () => _controller.setFavorite(p.id, !p.favorite),
              ),
              menuItem(
                'Rename',
                onPressed: () => setState(() => _renaming = p.id),
              ),
              iconMenuItem(
                context,
                icon: p.icon,
                color: p.color,
                kind: GlyphKind.project,
                onPick: (icon, color) =>
                    _controller.setProjectIcon(p.id, icon, color),
              ),
              ?moveToOrganizationMenu(context, ref, p),
              menuItem(
                p.archived ? 'Unarchive' : 'Archive',
                onPressed: () => _controller.setArchived(p.id, !p.archived),
              ),
              menuItem(
                'Restore Previous Version…',
                onPressed: () => showRestoreProjectDialog(context, ref, p),
              ),
              const Divider(),
              menuItem(
                'Delete Project…',
                danger: true,
                onPressed: () => confirmDeleteProject(context, ref, p),
              ),
            ],
    );
  }
}
