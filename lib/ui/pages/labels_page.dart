import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/models.dart';
import '../../state/prefs.dart';
import '../../state/toast.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../icon_picker.dart';
import '../theme.dart';
import '../widgets.dart';
import 'restore_dialog.dart';
import 'list_parts.dart';
import 'page_scaffold.dart';

/// Labels list for the workspace or one project (SPEC §4.8).
class LabelsPage extends ConsumerStatefulWidget {
  const LabelsPage({super.key});

  @override
  ConsumerState<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends ConsumerState<LabelsPage> {
  bool _creating = false;
  String? _renaming;

  // Icon and color picked in the create row before the label exists; null color: the next unused one.
  String? _newIcon;
  TaskletColor? _newColor;

  WorkspaceController get _controller => ref.read(workspaceProvider.notifier);

  /// Labels must be unique (case-insensitive) within their scope; returns false and explains if not.
  bool _validate(String name, List<Label> scope, {String? exceptId}) {
    final clash = scope.any(
      (l) => l.id != exceptId && l.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      ref
          .read(toastProvider.notifier)
          .show('A label named "$name" already exists here.');
    }
    return !clash;
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceDataProvider);
    final stored = ref.watch(prefsProvider.select((p) => p.labelsScope));
    if (ws == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final activeProjects = ws.projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // Fall back to Workspace if the remembered project was deleted or archived.
    final scopeProject = activeProjects
        .where((p) => p.id == stored)
        .firstOrNull;
    final labels = [...(scopeProject?.labels ?? ws.labels)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final locked = ws.readOnly || (scopeProject == null && !ws.labelsReadable);

    void setScope(String? id) {
      setState(() => _creating = false);
      ref.read(prefsProvider.notifier).set(PrefKeys.labelsScope, id);
    }

    return PageScaffold(
      title: 'Labels',
      actions: [
        PillMenuButton(
          label: scopeProject?.name ?? 'Workspace',
          leading: scopeProject == null
              ? null
              : ProjectGlyph(scopeProject, size: 12),
          menuChildren: [
            checkItem(
              'Workspace',
              checked: scopeProject == null,
              onPressed: () => setScope(null),
            ),
            if (activeProjects.isNotEmpty) const Divider(),
            for (final p in activeProjects)
              checkItem(
                p.name,
                checked: scopeProject?.id == p.id,
                leading: ProjectGlyph(p, size: 12),
                onPressed: () => setScope(p.id),
              ),
          ],
        ),
        // Project labels live in the project's file, so their history is the project's.
        IconBtn(
          icon: Icons.history,
          tooltip: 'Restore Previous Version…',
          onPressed: locked
              ? null
              : () => scopeProject == null
                    ? showRestoreListDialog(context, ref, labels: true)
                    : showRestoreProjectDialog(context, ref, scopeProject),
        ),
        TextButton.icon(
          onPressed: locked ? null : () => setState(() => _creating = true),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('New Label'),
        ),
      ],
      body: Column(
        children: [
          if (scopeProject == null && !ws.labelsReadable)
            const NoticeBanner(
              icon: Icons.sync_problem_outlined,
              message:
                  "labels.json can't be read right now. It may still be syncing or be damaged. Workspace labels "
                  "can't be changed until it can be read again.",
            ),
          Expanded(
            child: labels.isEmpty && !_creating
                ? EmptyState(
                    icon: Icons.label_outline_rounded,
                    title: 'No labels yet',
                    message: scopeProject == null
                        ? 'Workspace labels can be used on tasks in any project, like Bug, Idea, or Waiting.'
                        : 'Labels created here can only be used on tasks in ${scopeProject.name}.',
                    action: FilledButton.icon(
                      onPressed: locked
                          ? null
                          : () => setState(() => _creating = true),
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('New Label'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      ListHeading(
                        scopeProject == null
                            ? 'Workspace Labels'
                            : '${scopeProject.name} Labels',
                        labels.length,
                      ),
                      if (_creating) _createRow(labels, scopeProject, t),
                      for (final l in labels)
                        _row(context, l, labels, scopeProject, t, locked),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _endCreate() => setState(() {
    _creating = false;
    _newIcon = null;
    _newColor = null;
  });

  /// The picker's icon and color for an existing label; an unchanged color is left alone (see setProjectIcon).
  void _setIcon(Label l, String? icon, TaskletColor color, Project? project) =>
      _controller.updateLabel(
        l.id,
        (x) => x.copyWith(
          icon: icon,
          clearIcon: icon == null,
          color: color == x.color ? null : color,
        ),
        projectId: project?.id,
      );

  Widget _createRow(List<Label> scope, Project? project, Tokens t) {
    final color =
        _newColor ?? TaskletColor.nextUnused(scope.map((l) => l.color));
    return ListRowShell(
      leading: IconPickerButton(
        icon: _newIcon,
        color: color,
        kind: GlyphKind.label,
        onPick: (icon, c) => setState(() {
          _newIcon = icon;
          _newColor = c;
        }),
      ),
      title: InlineEditField(
        initial: '',
        hint: 'Label name',
        maxLength: Label.maxNameLength,
        onCommit: (name) {
          final icon = _newIcon;
          _endCreate();
          if (_validate(name, scope)) {
            _controller.createLabel(
              name,
              color,
              icon: icon,
              projectId: project?.id,
            );
          }
        },
        onCancel: _endCreate,
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Label l,
    List<Label> scope,
    Project? project,
    Tokens t,
    bool locked,
  ) {
    final usage = ref.read(workspaceDataProvider)?.labelUsage[l.id] ?? 0;
    return ListRowShell(
      dimmed: locked,
      leading: IconPickerButton(
        enabled: !locked,
        icon: l.icon,
        color: l.color,
        kind: GlyphKind.label,
        size: 14,
        onPick: (icon, c) => _setIcon(l, icon, c, project),
      ),
      title: _renaming == l.id
          ? InlineEditField(
              initial: l.name,
              maxLength: Label.maxNameLength,
              onCommit: (name) {
                setState(() => _renaming = null);
                if (_validate(name, scope, exceptId: l.id)) {
                  _controller.updateLabel(
                    l.id,
                    (x) => x.copyWith(name: name),
                    projectId: project?.id,
                  );
                }
              },
              onCancel: () => setState(() => _renaming = null),
            )
          : Text(
              l.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.body(context),
            ),
      trailing: [
        Text(
          usage == 1 ? '1 task' : '$usage tasks',
          style: TextStyles.meta(context),
        ),
      ],
      onTap: locked || _renaming == l.id
          ? null
          : () => setState(() => _renaming = l.id),
      menuChildren: locked
          ? null
          : () => [
              menuItem(
                'Rename',
                onPressed: () => setState(() => _renaming = l.id),
              ),
              iconMenuItem(
                context,
                icon: l.icon,
                color: l.color,
                kind: GlyphKind.label,
                onPick: (icon, c) => _setIcon(l, icon, c, project),
              ),
              const Divider(),
              menuItem(
                'Delete Label…',
                danger: true,
                onPressed: () async {
                  final ok = await confirmDestructive(
                    context,
                    title: "Delete '${l.name}'?",
                    message:
                        'It will be removed from $usage ${usage == 1 ? 'task' : 'tasks'}. The tasks themselves are '
                        'not deleted.',
                  );
                  if (ok) {
                    await _controller.deleteLabel(l.id, projectId: project?.id);
                  }
                },
              ),
            ],
    );
  }
}
