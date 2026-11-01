import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/models.dart';
import '../../state/task_actions.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pickers.dart';

/// The task detail sheet sliding in from the right over a dimmed backdrop (SPEC §7.2).
class DetailPanelOverlay extends ConsumerWidget {
  const DetailPanelOverlay({super.key, required this.taskRef});
  final TaskRef taskRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceDataProvider);
    final project = ws?.projectById(taskRef.projectId);
    final task = project?.taskById(taskRef.taskId);
    if (ws == null || project == null || task == null) {
      // Deleted here or by sync while open → close (SPEC §7.2).
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(openTaskProvider.notifier).close(),
      );
      return const SizedBox.shrink();
    }
    final t = Tokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(openTaskProvider.notifier).close(),
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => ref.read(openTaskProvider.notifier).close(),
                child: ColoredBox(color: t.backdrop),
              ),
            ),
            Positioned(
              top: 8,
              bottom: 8,
              right: 8,
              width: 580,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduceMotion ? 0 : 1, end: 0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Transform.translate(
                  offset: Offset(v * 600, 0),
                  child: child,
                ),
                child: Material(
                  color: t.raised,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: t.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _PanelBody(
                    key: ValueKey(task.id),
                    entry: ProjectTask(project, task),
                    readOnly: ws.readOnly,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelBody extends ConsumerStatefulWidget {
  const _PanelBody({super.key, required this.entry, required this.readOnly});
  final ProjectTask entry;
  final bool readOnly;

  @override
  ConsumerState<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends ConsumerState<_PanelBody> {
  late final _title = TextEditingController(text: widget.entry.task.title);
  late final _description = TextEditingController(
    text: widget.entry.task.description,
  );
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  /// The panel takes focus when it opens so Escape and Delete reach it (focus returns to the card on close).
  final _panelFocus = FocusScopeNode(debugLabel: 'Task panel');
  Timer? _debounce;
  late WorkspaceController _controller;
  late TaskActions _actions;

  ProjectTask get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(workspaceProvider.notifier);
    _actions = ref.read(taskActionsProvider);
    _title.addListener(_scheduleSave);
    _description.addListener(_scheduleSave);
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _flush(revertEmptyTitle: true);
    });
    _descriptionFocus.addListener(() {
      if (!_descriptionFocus.hasFocus) _flush();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(_PanelBody old) {
    super.didUpdateWidget(old);
    // Reflect external changes (sync, menu edits) in fields the user isn't editing.
    if (!_titleFocus.hasFocus &&
        _title.text != entry.task.title &&
        _debounce == null) {
      _title.text = entry.task.title;
    }
    if (!_descriptionFocus.hasFocus &&
        _description.text != entry.task.description &&
        _debounce == null) {
      _description.text = entry.task.description;
    }
  }

  @override
  void dispose() {
    _flush(revertEmptyTitle: true); // save immediately on close (SPEC §7.2)
    _title.dispose();
    _description.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _flush);
  }

  /// Saves title/description if changed. An empty title is never saved; it reverts when the field is left.
  void _flush({bool revertEmptyTitle = false}) {
    _debounce?.cancel();
    _debounce = null;
    if (widget.readOnly) return;
    final title = _title.text.trim();
    final description = _description.text;
    final current = _controller.workspace
        ?.projectById(entry.project.id)
        ?.taskById(entry.task.id);
    if (current == null) return;
    if (title.isEmpty && revertEmptyTitle && mounted) {
      _title.text = current.title;
    }
    final newTitle = title.isEmpty ? current.title : title;
    if (newTitle == current.title && description == current.description) return;
    _controller.updateTask(
      entry.project.id,
      entry.task.id,
      (t) => t.copyWith(title: newTitle, description: description),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ws = ref.watch(workspaceDataProvider)!;
    final task = entry.task;
    final available = [
      for (final l in entry.project.labels) (l, entry.project),
      for (final l in ws.labels) (l, null),
    ];
    final enabled = !widget.readOnly;
    final fieldDecoration = const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    );

    return FocusScope(
      node: _panelFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Text(
                  entry.displayId,
                  style: TextStyles.body(
                    context,
                  ).copyWith(color: t.secondary, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                IconBtn(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete task',
                  onPressed: enabled ? () => _actions.delete(entry) : null,
                ),
                IconBtn(
                  icon: Icons.close,
                  tooltip: 'Close (Esc)',
                  onPressed: () => ref.read(openTaskProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPicker(
                  status: task.status,
                  enabled: enabled,
                  onPick: (s) => _actions.setStatus(entry, s, toast: false),
                ),
                PriorityPicker(
                  priority: task.priority,
                  enabled: enabled,
                  onPick: (p) => _actions.setPriority(entry, p, toast: false),
                ),
                DatePickerChip(
                  date: task.startDate,
                  placeholder: 'Start date',
                  latest: task.dueDate,
                  enabled: enabled,
                  onPick: (d, _) => _actions.setStart(entry, d, toast: false),
                ),
                DatePickerChip(
                  date: task.dueDate,
                  placeholder: 'Due date',
                  earliest: task.startDate,
                  enabled: enabled,
                  onPick: (d, _) => _actions.setDue(entry, d, toast: false),
                ),
                LabelsPicker(
                  selected: task.labelIds,
                  available: available,
                  enabled: enabled,
                  onToggle: (l) => _actions.toggleLabel(entry, l, toast: false),
                ),
                ProjectPicker(
                  project: entry.project,
                  options: projectOptions(ws, alsoInclude: entry.project.id),
                  enabled: enabled,
                  onPick: (p) => _actions.moveToProject(entry, p),
                ),
              ],
            ),
          ),
          Divider(color: t.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallbackShortcuts(
                    // Enter moves to the description; a title is conceptually one line.
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _descriptionFocus.requestFocus(),
                    },
                    child: TextField(
                      controller: _title,
                      focusNode: _titleFocus,
                      enabled: enabled,
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: t.primary,
                        height: 1.35,
                      ),
                      decoration: fieldDecoration.copyWith(
                        hintText: 'Task title',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    focusNode: _descriptionFocus,
                    enabled: enabled,
                    maxLines: null,
                    minLines: 4,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      fontSize: 13,
                      color: t.primary,
                      height: 1.5,
                    ),
                    decoration: fieldDecoration.copyWith(
                      hintText: 'Add a description…',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: Text(
              [
                'Created ${longDate(task.createdAt)}',
                if (task.isDone && task.completedAt != null)
                  'Completed ${longDate(task.completedAt!)}',
              ].join(' · '),
              style: TextStyles.meta(context),
            ),
          ),
        ],
      ),
    );
  }
}
