import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_tiles.dart';

/// List layout (SPEC §5.2): four collapsible status sections with sticky headers; the next header slides over the
/// previous one. Rows are built lazily.
class TaskListView extends StatelessWidget {
  const TaskListView({
    super.key,
    required this.groups,
    required this.display,
    required this.crossProject,
    required this.collapsed,
    required this.onToggle,
    required this.onAdd,
    this.readOnly = false,
  });

  final Map<TaskStatus, List<ProjectTask>> groups;
  final ViewDisplay display;
  final bool crossProject;
  final Set<TaskStatus> collapsed;
  final ValueChanged<TaskStatus> onToggle;
  final ValueChanged<TaskStatus> onAdd;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      for (final s in TaskStatus.values)
        if (!display.hideEmptySections || (groups[s]?.isNotEmpty ?? false)) s,
    ];
    return Scrollbar(
      child: CustomScrollView(
        slivers: [
          for (final s in statuses)
            SliverMainAxisGroup(
              slivers: [
                PinnedHeaderSliver(
                  child: _SectionHeader(
                    status: s,
                    count: groups[s]?.length ?? 0,
                    collapsed: collapsed.contains(s),
                    onToggle: () => onToggle(s),
                    onAdd: readOnly ? null : () => onAdd(s),
                  ),
                ),
                if (!collapsed.contains(s))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                    sliver: SliverList.builder(
                      itemCount: groups[s]?.length ?? 0,
                      itemBuilder: (context, i) {
                        final e = groups[s]![i];
                        return TaskRow(
                          key: ValueKey(e.task.id),
                          entry: e,
                          display: display,
                          crossProject: crossProject,
                        );
                      },
                    ),
                  ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.status,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onAdd,
  });

  final TaskStatus status;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Hoverable(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          height: 38,
          color: t.background,
          padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Chevron(collapsed: collapsed, size: 16, color: t.secondary),
                const SizedBox(width: 2),
                StatusIcon(status),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: TextStyles.section(context).copyWith(fontSize: 12.5),
                ),
                const SizedBox(width: 6),
                CountText(count),
                const Spacer(),
                if (onAdd != null && (count == 0 || hovered))
                  IconBtn(
                    icon: Icons.add,
                    tooltip: 'New ${status.label} task',
                    onPressed: onAdd,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
