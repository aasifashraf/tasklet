import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/dates.dart';
import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../state/clock.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pointers that started on an interactive control inside a card; the card's drag/click handling ignores them so
/// a chip click never starts a drag or opens the task (SPEC §5.1).
abstract final class DragGate {
  static final _claimed = <int>{};
  static void claim(int pointer) => _claimed.add(pointer);
  static bool isClaimed(int pointer) => _claimed.contains(pointer);
  static void release(int pointer) => _claimed.remove(pointer);
}

/// Wrap interactive controls inside draggable cards with this.
class NoDragZone extends StatelessWidget {
  const NoDragZone({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) => DragGate.claim(e.pointer),
    onPointerUp: (e) => Future.microtask(() => DragGate.release(e.pointer)),
    onPointerCancel: (e) => DragGate.release(e.pointer),
    child: child,
  );
}

/// A chip that opens a menu (the picker shell).
class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.chip,
    required this.menuChildren,
    this.enabled = true,
  });
  final Widget Function(VoidCallback? onTap) chip;
  final List<Widget> Function() menuChildren;
  final bool enabled;

  @override
  Widget build(BuildContext context) => NoDragZone(
    child: MenuAnchor(
      menuChildren: menuChildren(),
      builder: (context, controller, _) => chip(
        enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
      ),
    ),
  );
}

class StatusPicker extends StatelessWidget {
  const StatusPicker({
    super.key,
    required this.status,
    required this.onPick,
    this.iconOnly = false,
    this.enabled = true,
  });
  final TaskStatus status;
  final ValueChanged<TaskStatus> onPick;
  final bool iconOnly;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _MenuChip(
    enabled: enabled,
    menuChildren: () => statusMenuItems(status, onPick),
    chip: (onTap) => iconOnly
        ? GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: Tooltip(message: status.label, child: StatusIcon(status)),
            ),
          )
        : PropChip(icon: StatusIcon(status), label: status.label, onTap: onTap),
  );
}

List<Widget> statusMenuItems(
  TaskStatus current,
  ValueChanged<TaskStatus> onPick,
) => [
  for (final s in TaskStatus.values)
    checkItem(
      s.label,
      checked: s == current,
      leading: StatusIcon(s),
      onPressed: () => onPick(s),
    ),
];

class PriorityPicker extends StatelessWidget {
  const PriorityPicker({
    super.key,
    required this.priority,
    required this.onPick,
    this.iconOnly = false,
    this.enabled = true,
  });
  final Priority priority;
  final ValueChanged<Priority> onPick;
  final bool iconOnly;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _MenuChip(
    enabled: enabled,
    menuChildren: () => priorityMenuItems(priority, onPick),
    chip: (onTap) => PropChip(
      icon: PriorityIcon(priority),
      label: iconOnly ? null : priority.label,
      tooltip: iconOnly ? 'Priority: ${priority.label}' : null,
      onTap: onTap,
    ),
  );
}

/// The 5 priorities, with a divider after "None" (SPEC §6, §7.3).
List<Widget> priorityMenuItems(
  Priority current,
  ValueChanged<Priority> onPick,
) => [
  checkItem(
    'No priority',
    checked: current == Priority.none,
    leading: const PriorityIcon(Priority.none),
    onPressed: () => onPick(Priority.none),
  ),
  const Divider(),
  for (final p in [
    Priority.urgent,
    Priority.high,
    Priority.medium,
    Priority.low,
  ])
    checkItem(
      p.label,
      checked: p == current,
      leading: PriorityIcon(p),
      onPressed: () => onPick(p),
    ),
];

/// Quick-pick due/start dates (SPEC §7.3): Today, Tomorrow, Next Week (always next Monday) with hints and checks.
/// [earliest]/[latest] disable choices outside the allowed range (a due date before the start date, or a start
/// date after the due date).
List<Widget> quickDateItems(
  LocalDate today,
  LocalDate? current,
  void Function(LocalDate date, String phrase) onPick, {
  LocalDate? earliest,
  LocalDate? latest,
}) {
  final options = [
    ('Today', today, 'today'),
    ('Tomorrow', tomorrowOf(today), 'tomorrow'),
    ('Next Week', nextMondayAfter(today), 'next week'),
  ];
  return [
    for (final (label, date, phrase) in options)
      Builder(
        builder: (context) => MenuItemButton(
          onPressed:
              (earliest != null && date.isBefore(earliest)) ||
                  (latest != null && date.isAfter(latest))
              ? null
              : () => onPick(date, phrase),
          leadingIcon: SizedBox(
            width: 16,
            child: current == date
                ? Icon(Icons.check, size: 14, color: Tokens.of(context).primary)
                : null,
          ),
          trailingIcon: Text(
            weekdayHint(date),
            style: TextStyles.meta(context),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
  ];
}

/// Opens the calendar limited to [earliest]..[latest] (either may be null). Every calendar in the app goes through
/// this so a range's start can never be picked after its end (or the end before the start).
Future<LocalDate?> pickCalendarDate(
  BuildContext context, {
  required LocalDate initial,
  LocalDate? earliest,
  LocalDate? latest,
}) async {
  var first = earliest ?? LocalDate(2000, 1, 1);
  var last = latest ?? LocalDate(2100, 12, 31);
  if (first.isAfter(last)) (first, last) = (last, first);
  final start = initial.isBefore(first)
      ? first
      : (initial.isAfter(last) ? last : initial);
  final picked = await showDatePicker(
    context: context,
    initialDate: start.toLocalDateTime(),
    firstDate: first.toLocalDateTime(),
    lastDate: last.toLocalDateTime(),
  );
  return picked == null ? null : LocalDate.fromDateTime(picked);
}

/// A start- or due-date chip with quick picks, a calendar, and remove.
class DatePickerChip extends ConsumerWidget {
  const DatePickerChip({
    super.key,
    required this.date,
    required this.onPick,
    required this.placeholder,
    this.earliest,
    this.latest,
    this.enabled = true,
  });
  final LocalDate? date;

  /// Called with the new date (null = removed) and a phrase for toasts ("next week").
  final void Function(LocalDate? date, String? phrase) onPick;
  final String placeholder;

  /// Allowed range: a due date can't be before the start date and a start date can't be after the due date.
  final LocalDate? earliest;
  final LocalDate? latest;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final t = Tokens.of(context);
    final overdue =
        date != null && date!.isBefore(today) && placeholder == 'Due date';
    return _MenuChip(
      enabled: enabled,
      menuChildren: () => [
        ...quickDateItems(
          today,
          date,
          (d, phrase) => onPick(d, phrase),
          earliest: earliest,
          latest: latest,
        ),
        const Divider(),
        menuItem(
          'Pick a Date…',
          leading: const Icon(Icons.calendar_month_outlined, size: 14),
          onPressed: () async {
            final picked = await pickCalendarDate(
              context,
              initial: date ?? today,
              earliest: earliest,
              latest: latest,
            );
            if (picked != null) onPick(picked, null);
          },
        ),
        menuItem(
          placeholder == 'Due date' ? 'Remove Due Date' : 'Remove Start Date',
          onPressed: date == null ? null : () => onPick(null, null),
        ),
      ],
      chip: (onTap) => PropChip(
        icon: Icon(
          Icons.calendar_today_outlined,
          size: 12,
          color: overdue ? t.danger : t.secondary,
        ),
        label: date == null ? placeholder : relativeDate(date!, today),
        onTap: onTap,
      ),
    );
  }
}

/// Up to 3 overlapping label dots.
class LabelDots extends StatelessWidget {
  const LabelDots(this.labels, {super.key});
  final List<Label> labels;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final shown = labels.take(3).toList();
    return SizedBox(
      width: 8.0 + (shown.length - 1) * 5,
      height: 8,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 5.0,
              child: ColorDot(
                color: t.named(shown[i].color),
                size: 8,
                border: t.raised,
              ),
            ),
        ],
      ),
    );
  }
}

/// The labels chip: one label → dot + name; several → overlapping dots + "N labels" (SPEC §8.5).
Widget labelsChipContent(
  BuildContext context,
  List<Label> labels, {
  VoidCallback? onTap,
  bool placeholder = true,
}) {
  final t = Tokens.of(context);
  if (labels.isEmpty) {
    return PropChip(
      icon: Icon(Icons.circle_outlined, size: 11, color: t.tertiary),
      label: placeholder ? 'Labels' : null,
      onTap: onTap,
    );
  }
  if (labels.length == 1) {
    return PropChip(
      icon: LabelGlyph(labels.single),
      label: labels.single.name,
      onTap: onTap,
    );
  }
  return PropChip(
    icon: LabelDots(labels),
    label: '${labels.length} labels',
    onTap: onTap,
  );
}

class LabelsPicker extends StatelessWidget {
  const LabelsPicker({
    super.key,
    required this.selected,
    required this.available,
    required this.onToggle,
    this.enabled = true,
  });
  final List<String> selected;

  /// Labels usable here, with the owning project (null = workspace label).
  final List<(Label, Project?)> available;
  final ValueChanged<Label> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final labels = [
      for (final (l, _) in available)
        if (selected.contains(l.id)) l,
    ];
    return _MenuChip(
      enabled: enabled && available.isNotEmpty,
      menuChildren: () => labelMenuItems(available, selected, onToggle, t),
      chip: (onTap) => labelsChipContent(context, labels, onTap: onTap),
    );
  }
}

/// Checkable label items (project labels first, then workspace; SPEC §6). Stays open while toggling.
List<Widget> labelMenuItems(
  List<(Label, Project?)> available,
  List<String> selected,
  ValueChanged<Label> onToggle,
  Tokens t,
) {
  final projectLabels = available.where((e) => e.$2 != null).toList();
  final workspaceLabels = available.where((e) => e.$2 == null).toList();
  Widget item(Label l) => _ToggleItem(
    label: l.name,
    leading: LabelGlyph(l),
    initiallyChecked: selected.contains(l.id),
    onToggle: () => onToggle(l),
  );
  return [
    for (final (l, _) in projectLabels) item(l),
    if (projectLabels.isNotEmpty && workspaceLabels.isNotEmpty) const Divider(),
    for (final (l, _) in workspaceLabels) item(l),
  ];
}

/// A menu row that toggles a check mark without closing the menu.
class _ToggleItem extends StatefulWidget {
  const _ToggleItem({
    required this.label,
    required this.leading,
    required this.initiallyChecked,
    required this.onToggle,
  });
  final String label;
  final Widget leading;
  final bool initiallyChecked;
  final VoidCallback onToggle;

  @override
  State<_ToggleItem> createState() => _ToggleItemState();
}

class _ToggleItemState extends State<_ToggleItem> {
  late bool _checked = widget.initiallyChecked;

  @override
  Widget build(BuildContext context) => MenuItemButton(
    closeOnActivate: false,
    onPressed: () {
      setState(() => _checked = !_checked);
      widget.onToggle();
    },
    leadingIcon: SizedBox(width: 16, child: widget.leading),
    trailingIcon: SizedBox(
      width: 16,
      child: _checked
          ? Icon(Icons.check, size: 14, color: Tokens.of(context).primary)
          : null,
    ),
    child: Text(widget.label, style: const TextStyle(fontSize: 12)),
  );
}

/// Project chip: cube + name, "No Project" for the bucket.
class ProjectPicker extends StatelessWidget {
  const ProjectPicker({
    super.key,
    required this.project,
    required this.options,
    required this.onPick,
    this.enabled = true,
  });
  final Project project;
  final List<Project> options;
  final ValueChanged<Project> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return _MenuChip(
      enabled: enabled,
      menuChildren: () => projectMenuItems(options, project.id, onPick, t),
      chip: (onTap) => PropChip(
        icon: ProjectGlyph(
          project,
          size: 12,
          color: project.isNoProject ? t.tertiary : null,
        ),
        label: project.name,
        onTap: onTap,
      ),
    );
  }
}

List<Widget> projectMenuItems(
  List<Project> options,
  String currentId,
  ValueChanged<Project> onPick,
  Tokens t,
) => [
  for (final (i, p) in options.indexed) ...[
    checkItem(
      p.name,
      checked: p.id == currentId,
      leading: ProjectGlyph(
        p,
        size: 12,
        color: p.isNoProject ? t.tertiary : null,
      ),
      onPressed: () => onPick(p),
    ),
    if (i == 0 && p.isNoProject && options.length > 1) const Divider(),
  ],
];

/// Projects a task can be filed into: "No Project" first, then active projects, plus [alsoInclude] (an archived
/// project the task already belongs to or whose board opened the dialog; SPEC §7.1, §7.3).
List<Project> projectOptions(Workspace ws, {String? alsoInclude}) {
  final active =
      ws.projects.where((p) => !p.archived || p.id == alsoInclude).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return [ws.noProject, ...active];
}
