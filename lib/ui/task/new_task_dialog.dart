import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/local_date.dart';
import '../../core/quick_add.dart';
import '../../core/date_format.dart';
import '../../core/models.dart';
import '../../state/boards.dart';
import '../../state/clock.dart';
import '../../state/toast.dart';
import '../../state/ui_state.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pickers.dart';

/// Initial values for the New Task dialog.
@immutable
class NewTaskDefaults {
  const NewTaskDefaults({
    this.projectId,
    this.status = TaskStatus.todo,
    this.priority = Priority.none,
    this.dueDate,
    this.labelIds = const [],
    this.archivedProjectId,
  });

  /// null = No Project.
  final String? projectId;
  final TaskStatus status;
  final Priority priority;
  final LocalDate? dueDate;
  final List<String> labelIds;

  /// An archived project to offer anyway because its board opened the dialog (SPEC §7.1).
  final String? archivedProjectId;

  NewTaskDefaults copyWith({TaskStatus? status}) => NewTaskDefaults(
    projectId: projectId,
    status: status ?? this.status,
    priority: priority,
    dueDate: dueDate,
    labelIds: labelIds,
    archivedProjectId: archivedProjectId,
  );
}

/// Defaults per board (SPEC §4.2–4.7). Saved views derive them from their filters only when unambiguous.
NewTaskDefaults defaultsForBoard(
  BoardKind kind,
  Workspace ws,
  LocalDate today,
) {
  switch (kind) {
    case AllTasksBoard():
      return const NewTaskDefaults();
    case TodayBoard():
      return NewTaskDefaults(dueDate: today);
    case ProjectBoard(:final projectId):
      final p = ws.projectById(projectId);
      return NewTaskDefaults(
        projectId: projectId,
        archivedProjectId: p != null && p.archived ? projectId : null,
      );
    case ViewBoard(:final viewId):
      final view = ws.views.where((v) => v.id == viewId).firstOrNull;
      if (view == null) return const NewTaskDefaults();
      final f = view.filters;
      final project = f.projects.length == 1 && f.projects.single != noProjectId
          ? f.projects.single
          : null;
      return NewTaskDefaults(
        projectId: project,
        status: f.status.length == 1 ? f.status.single : TaskStatus.todo,
        priority: f.priorities.length == 1
            ? f.priorities.single
            : Priority.none,
        labelIds: [
          for (final id in f.labels)
            if (id != noLabelFilterId) id,
        ],
        dueDate:
            f.due.contains(DueFilter.today) || f.due.contains(DueFilter.week)
            ? today
            : null,
      );
  }
}

/// The board for the current route, used by the sidebar button and Ctrl+N.
BoardKind boardForLocation(String path) {
  final segments = Uri.parse(path).pathSegments;
  return switch (segments) {
    ['projects', final id] => ProjectBoard(id),
    ['views', final id] => ViewBoard(id),
    ['today'] => const TodayBoard(),
    _ => const AllTasksBoard(),
  };
}

/// "New Task" from the sidebar / Ctrl+N: project of the current page, or none (SPEC §3.3).
Future<void> openNewTaskForLocation(BuildContext context, WidgetRef ref) async {
  final ws = ref.read(workspaceDataProvider);
  if (ws == null || ws.readOnly) return;
  final kind = boardForLocation(GoRouterState.of(context).uri.path);
  await showNewTaskDialog(
    context,
    ref,
    defaultsForBoard(kind, ws, ref.read(todayProvider)),
  );
}

Future<void> showNewTaskDialog(
  BuildContext context,
  WidgetRef ref,
  NewTaskDefaults defaults,
) async {
  if (ref.read(newTaskOpenProvider)) {
    return; // Ctrl+N while open is a no-op (SPEC §12)
  }
  ref.read(newTaskOpenProvider.notifier).set(true);
  try {
    await showDialog<void>(
      context: context,
      barrierColor: Tokens.of(context).backdrop,
      builder: (_) => _NewTaskDialog(defaults: defaults),
    );
  } finally {
    ref.read(newTaskOpenProvider.notifier).set(false);
  }
}

class _NewTaskDialog extends ConsumerStatefulWidget {
  const _NewTaskDialog({required this.defaults});
  final NewTaskDefaults defaults;

  @override
  ConsumerState<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends ConsumerState<_NewTaskDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _titleFocus = FocusNode();
  late String _projectId = widget.defaults.projectId ?? noProjectId;
  late TaskStatus _status = widget.defaults.status;
  late Priority _priority = widget.defaults.priority;
  LocalDate? _start;
  late LocalDate? _due = widget.defaults.dueDate;
  late List<String> _labels = [...widget.defaults.labelIds];
  bool _createMore = false;
  Repeat? _repeat;
  bool _closing = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    final ws = ref.read(workspaceDataProvider);
    if (ws != null && ws.projectById(_projectId) == null) {
      _projectId = noProjectId;
    }
    _labels = _validLabels(_labels);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  List<(Label, Project?)> _available() {
    final ws = ref.read(workspaceDataProvider);
    final project = ws?.projectById(_projectId);
    if (ws == null || project == null) return const [];
    return [
      for (final l in project.labels) (l, project),
      for (final l in ws.labels) (l, null),
    ];
  }

  List<String> _validLabels(List<String> ids) {
    final valid = {for (final (l, _) in _available()) l.id};
    return [
      for (final id in ids)
        if (valid.contains(id)) id,
    ];
  }

  bool get _dirty =>
      _title.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;

  /// What the title says beyond the title itself (quick add, D17): any project's labels can be named, since
  /// `+project` may change the project; labels the final project can't use are dropped.
  QuickAdd _quickAdd() {
    final ws = ref.read(workspaceDataProvider);
    if (ws == null) return QuickAdd(title: _title.text.trim());
    final options = projectOptions(
      ws,
      alsoInclude: widget.defaults.archivedProjectId,
    );
    return parseQuickAdd(
      _title.text,
      today: ref.read(todayProvider),
      labels: [for (final p in options) ...p.labels, ...ws.labels],
      projects: [
        for (final p in options)
          if (!p.isNoProject) p,
      ],
    );
  }

  /// Applies what [_quickAdd] found to the chips (the typed fields win over the chips' values).
  void _applyQuickAdd(QuickAdd q) {
    if (q.project case final project?) _projectId = project.id;
    if (q.priority case final priority?) _priority = priority;
    if (q.due case final due?) {
      _due = due;
      if (_start != null && _start!.isAfter(due)) _start = null;
    }
    _labels = _validLabels([
      ..._labels,
      for (final l in q.labels)
        if (!_labels.contains(l.id)) l.id,
    ]);
  }

  Future<void> _submit() async {
    final quick = _quickAdd();
    final title = quick.title;
    // Enter and Ctrl+Enter both submit; a slow (synced) save must not create the task twice.
    if (title.isEmpty || _submitting) return;
    _applyQuickAdd(quick);
    // The chosen project may have been deleted (here or by sync) while the dialog was open.
    final projectGone =
        ref.read(workspaceDataProvider)?.projectById(_projectId) == null;
    setState(() => _submitting = true);
    try {
      await ref
          .read(workspaceProvider.notifier)
          .createTask(
            projectId: projectGone ? noProjectId : _projectId,
            title: title,
            description: _description.text,
            status: _status,
            priority: _priority,
            startDate: _start,
            dueDate: _due,
            labelIds: projectGone ? const [] : _labels,
            repeat: _repeat,
          );
    } catch (e) {
      ref.read(toastProvider.notifier).show("Couldn't create the task: $e");
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    if (_createMore) {
      // Keep status/priority/project; restore due date and labels to how the dialog opened (SPEC §7.1).
      setState(() {
        _title.clear();
        _description.clear();
        _due = widget.defaults.dueDate;
        _labels = _validLabels(widget.defaults.labelIds);
      });
      _titleFocus.requestFocus();
    } else {
      _closing = true;
      Navigator.pop(context);
    }
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    if (_dirty) {
      final discard = await confirmDestructive(
        context,
        title: 'Discard this task?',
        message: "What you've typed will be lost.",
        confirmLabel: 'Discard',
        cancelLabel: 'Keep Editing',
      );
      if (!discard || !mounted) return;
    }
    _closing = true;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ws = ref.watch(workspaceDataProvider);
    if (ws == null) return const SizedBox.shrink();
    final project = ws.projectById(_projectId) ?? ws.noProject;
    final options = projectOptions(
      ws,
      alsoInclude: widget.defaults.archivedProjectId,
    );

    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          alignment: const Alignment(0, -0.35),
          child: SizedBox(
            width: 700,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!project.isNoProject) ...[
                        ProjectGlyph(project, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          project.key,
                          style: TextStyles.body(context)
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right, size: 14, color: t.tertiary),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'New Task',
                        style: TextStyles.body(context)
                            .copyWith(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      IconBtn(
                        icon: Icons.close,
                        tooltip: 'Close',
                        onPressed: _requestClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    autofocus: true,
                    style: TextStyles.title(context),
                    decoration: const InputDecoration(
                      hintText: 'Task title',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  // Quick add: what the title will set, before Enter.
                  Builder(
                    builder: (context) {
                      final q = _quickAdd();
                      if (q.isEmpty) return const SizedBox.shrink();
                      final today = ref.read(todayProvider);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          [
                            if (q.due case final due?)
                              'Due ${relativeDateInText(due, today)}',
                            if (q.priority case final p?) p.label,
                            for (final l in q.labels) '#${l.name}',
                            if (q.project case final p?) 'in ${p.name}',
                          ].join(' · '),
                          style: TextStyles.meta(context)
                              .copyWith(color: t.accent),
                        ),
                      );
                    },
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 70,
                      maxHeight: 240,
                    ),
                    child: TextField(
                      controller: _description,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyles.bodyLarge(context),
                      decoration: const InputDecoration(
                        hintText: 'Add a description…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPicker(
                        status: _status,
                        onPick: (s) => setState(() => _status = s),
                      ),
                      PriorityPicker(
                        priority: _priority,
                        onPick: (p) => setState(() => _priority = p),
                      ),
                      DatePickerChip(
                        date: _start,
                        placeholder: 'Start date',
                        latest: _due,
                        onPick: (d, _) => setState(() => _start = d),
                      ),
                      DatePickerChip(
                        date: _due,
                        placeholder: 'Due date',
                        earliest: _start,
                        onPick: (d, _) => setState(() => _due = d),
                      ),
                      LabelsPicker(
                        selected: _labels,
                        available: _available(),
                        onToggle: (l) => setState(() {
                          _labels = _labels.contains(l.id)
                              ? [
                                  for (final id in _labels)
                                    if (id != l.id) id,
                                ]
                              : [..._labels, l.id];
                        }),
                      ),
                      RepeatPicker(
                        repeat: _repeat,
                        onPick: (r) => setState(() => _repeat = r),
                      ),
                      ProjectPicker(
                        project: project,
                        options: options,
                        onPick: (p) => setState(() {
                          _projectId = p.id;
                          _labels = _validLabels(
                            _labels,
                          ); // drop labels the new project can't use
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: t.border),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        height: 20,
                        child: FittedBox(
                          child: Switch(
                            value: _createMore,
                            onChanged: (v) => setState(() => _createMore = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create more',
                        style: TextStyles.bodySecondary(context),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'Ctrl+Enter',
                        child: FilledButton(
                          onPressed: _title.text.trim().isEmpty
                              ? null
                              : _submit,
                          child: const Text('Create Task'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
