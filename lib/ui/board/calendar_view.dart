import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../platform/native.dart';
import '../../state/clock.dart';
import '../../state/task_actions.dart';
import '../../state/ui_state.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_tiles.dart';
import '../task/task_menu.dart';

final _monthTitle = DateFormat('MMMM y');
final _weekday = DateFormat('EEE');

/// The calendar layout (D17): the board's tasks (same filters and search) on their due dates, a month or a week at
/// a time. Drag a task to another day to change its due date (with Undo); click opens it, Ctrl/⌘/Shift + click
/// selects it for bulk edit.
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key, required this.groups, required this.readOnly});
  final Map<TaskStatus, List<ProjectTask>> groups;
  final bool readOnly;

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late LocalDate _anchor = ref.read(todayProvider);
  bool _week = false;
  final int _firstDay = osFirstDayOfWeek() ?? DateTime.monday;

  List<LocalDate> _days() {
    if (_week) {
      final start = startOfWeek(_anchor, _firstDay);
      return [for (var i = 0; i < 7; i++) start.addDays(i)];
    }
    final first = startOfWeek(startOfMonth(_anchor), _firstDay);
    final last = endOfMonth(_anchor);
    final days = <LocalDate>[];
    for (
      var d = first;
      !d.isAfter(last) || days.length % 7 != 0;
      d = d.addDays(1)
    ) {
      days.add(d);
    }
    return days;
  }

  void _move(int step) => setState(() {
    if (_week) {
      _anchor = _anchor.addDays(7 * step);
    } else {
      final index = _anchor.year * 12 + _anchor.month - 1 + step;
      _anchor = LocalDate(index ~/ 12, index % 12 + 1, 1);
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final today = ref.watch(todayProvider);
    final byDay = <LocalDate, List<ProjectTask>>{};
    var undated = 0;
    for (final list in widget.groups.values) {
      for (final e in list) {
        final due = e.task.dueDate;
        if (due == null) {
          undated++;
        } else {
          (byDay[due] ??= []).add(e);
        }
      }
    }
    final days = _days();
    final rows = days.length ~/ 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                _week
                    ? 'Week of ${DateFormat('MMM d').format(days.first.toLocalDateTime())}'
                    : _monthTitle.format(_anchor.toLocalDateTime()),
                style: TextStyles.pageTitle(context),
              ),
              const SizedBox(width: 12),
              IconBtn(
                icon: Icons.chevron_left,
                tooltip: _week ? 'Previous week' : 'Previous month',
                onPressed: () => _move(-1),
              ),
              IconBtn(
                icon: Icons.chevron_right,
                tooltip: _week ? 'Next week' : 'Next month',
                onPressed: () => _move(1),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => setState(() => _anchor = today),
                child: const Text('Today'),
              ),
              const Spacer(),
              if (undated > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    undated == 1
                        ? '1 task has no due date'
                        : '$undated tasks have no due date',
                    style: TextStyles.meta(context),
                  ),
                ),
              _Segment(
                labels: const ['Month', 'Week'],
                selected: _week ? 1 : 0,
                onChanged: (i) => setState(() => _week = i == 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in days.take(7))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 4),
                    child: Text(
                      _weekday.format(d.toLocalDateTime()),
                      style: TextStyles.meta(context),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                for (var r = 0; r < rows; r++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final day in days.skip(r * 7).take(7))
                          Expanded(
                            child: _DayCell(
                              day: day,
                              tasks: byDay[day] ?? const [],
                              today: today,
                              dimmed: !_week && day.month != _anchor.month,
                              readOnly: widget.readOnly,
                              border: t.border,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.tasks,
    required this.today,
    required this.dimmed,
    required this.readOnly,
    required this.border,
  });
  final LocalDate day;
  final List<ProjectTask> tasks;
  final LocalDate today;
  final bool dimmed;
  final bool readOnly;
  final Color border;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final isToday = day == today;
    return DragTarget<ProjectTask>(
      onWillAcceptWithDetails: (d) => !readOnly && d.data.task.dueDate != day,
      onAcceptWithDetails: (d) =>
          ref.read(taskActionsProvider).setDue(d.data, day),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? t.hover : t.surface,
          border: Border.all(color: isToday ? t.accent : border),
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: TextStyles.meta(context).copyWith(
                color: isToday
                    ? t.accent
                    : dimmed
                    ? t.tertiary.withValues(alpha: 0.6)
                    : t.secondary,
                fontWeight: isToday ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                primary: false,
                children: [
                  for (final e in tasks)
                    _CalendarTask(entry: e, readOnly: readOnly, today: today),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarTask extends ConsumerWidget {
  const _CalendarTask({
    required this.entry,
    required this.readOnly,
    required this.today,
  });
  final ProjectTask entry;
  final bool readOnly;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Tokens.of(context);
    final task = entry.task;
    final ref0 = TaskRef(entry.project.id, task.id);
    final selected = ref.watch(
      taskSelectionProvider.select((s) => s.contains(ref0)),
    );
    final color = dueColor(task, today, t);
    final chip = Container(
      height: 22,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: selected ? t.openHighlight : t.raised,
        border: Border.all(color: selected ? t.accent : t.border),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        children: [
          StatusIcon(task.status, size: 11),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.meta(context).copyWith(
                color: task.isDone ? t.tertiary : (color ?? t.primary),
                decoration: task.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
    final clickable = ContextMenuRegion(
      menuChildren: () => taskMenuChildren(context, ref, entry),
      child: Tooltip(
        message: '${entry.displayId} ${task.title}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => openOrSelect(ref, ref0),
            child: chip,
          ),
        ),
      ),
    );
    if (readOnly) return clickable;
    return Draggable<ProjectTask>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 160, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: clickable,
    );
  }
}

/// A two-option segmented toggle in the toolbar's shape.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, label) in labels.indexed)
          Pressable(
            onTap: () => onChanged(i),
            selected: i == selected,
            builder: (context, hovered) => Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == selected
                    ? t.selected
                    : (hovered ? t.hover : Colors.transparent),
                borderRadius: BorderRadius.circular(Radii.small),
              ),
              child: Text(
                label,
                style: TextStyles.chip(context)
                    .copyWith(color: i == selected ? t.primary : t.secondary),
              ),
            ),
          ),
      ],
    );
  }
}
