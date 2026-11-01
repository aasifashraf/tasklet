import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/local_date.dart';
import '../../core/models.dart';
import '../../core/report.dart';
import '../../core/report_prompt.dart';
import '../../platform/native.dart';
import '../../state/clock.dart';
import '../../state/toast.dart';
import '../../state/workspace.dart';
import '../glyphs.dart';
import '../task/pickers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_parts.dart';
import 'page_scaffold.dart';

/// Reports (SPEC §4.9): build a filter, then copy an AI-ready prompt or JSON. Never calls an AI service.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  PeriodPreset _preset = PeriodPreset.thisWeek;
  LocalDate? _customFrom;
  LocalDate? _customTo;
  ReportFilters _filters = const ReportFilters();
  final int _firstDayOfWeek = osFirstDayOfWeek() ?? DateTime.monday;

  void _setFilters(ReportFilters f, Workspace ws) {
    // Drop selected labels that are no longer in scope for the chosen projects (SPEC §4.9).
    final scoped = {for (final (l, _) in _labelScope(ws, f)) l.id};
    setState(
      () => _filters = ReportFilters(
        projectIds: f.projectIds,
        includeArchived: f.includeArchived,
        labelIds: f.labelIds.where(scoped.contains).toSet(),
        statuses: f.statuses,
        priorities: f.priorities,
      ),
    );
  }

  /// Workspace labels always; project labels only for projects included by the Projects filter.
  List<(Label, Project?)> _labelScope(Workspace ws, ReportFilters f) {
    final included = reportProjects(ws, f).where((p) => !p.isNoProject).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    int byName((Label, Project?) a, (Label, Project?) b) =>
        a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
    return [
      ...[for (final l in ws.labels) (l, null)]..sort(byName),
      for (final p in included)
        ...[for (final l in p.labels) (l, p)]..sort(byName),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceDataProvider);
    final today = ref.watch(todayProvider);
    if (ws == null) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final period = periodFor(
      _preset,
      today,
      firstDayOfWeek: _firstDayOfWeek,
      customFrom: _customFrom,
      customTo: _customTo,
    );
    final count = reportTasks(ws, _filters, period).length;
    final labelScope = _labelScope(ws, _filters);

    return PageScaffold(
      title: 'Reports',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pick what to include, then copy a ready-made prompt into any AI assistant to get a summary or a '
                    'progress report. Tasklet never sends your data anywhere.',
                    style: TextStyles.bodySecondary(context),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        _row(context, 'Date range', [
                          PillMenuButton(
                            label: _preset.label,
                            menuChildren: [
                              for (final p in PeriodPreset.values)
                                checkItem(
                                  p.label,
                                  checked: p == _preset,
                                  onPressed: () => setState(() => _preset = p),
                                ),
                            ],
                          ),
                          if (_preset == PeriodPreset.custom) ...[
                            _dateChip(
                              context,
                              _customFrom ?? today,
                              today,
                              (d) => setState(() => _customFrom = d),
                              latest: _customTo ?? today,
                            ),
                            Text('→', style: TextStyles.meta(context)),
                            _dateChip(
                              context,
                              _customTo ?? today,
                              today,
                              (d) => setState(() => _customTo = d),
                              earliest: _customFrom ?? today,
                            ),
                          ] else if (_preset != PeriodPreset.allTime)
                            Text(
                              '${shortDate(period.from, today)} – ${shortDate(period.to, today)}',
                              style: TextStyles.meta(context),
                            ),
                        ]),
                        _divider(t),
                        _row(context, 'Projects', [
                          _projectsMenu(ws, t),
                          const Spacer(),
                          _archivedToggle(ws),
                        ]),
                        _divider(t),
                        _row(context, 'Labels', [
                          _labelsMenu(ws, labelScope, t),
                        ]),
                        _divider(t),
                        _row(context, 'Status', [_statusMenu(ws)]),
                        _divider(t),
                        _row(context, 'Priority', [_priorityMenu(ws)]),
                        _divider(t),
                        _row(context, 'Tasks', [
                          Expanded(
                            child: Text(
                              count == 0
                                  ? 'No tasks match. Try a wider date range or fewer filters.'
                                  : '$count ${count == 1 ? 'task' : 'tasks'} will be included',
                              style: TextStyles.body(
                                context,
                              ).copyWith(color: count == 0 ? t.tertiary : null),
                            ),
                          ),
                          _copyButton(ws, period, today, count),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Tokens t) =>
      Divider(color: t.border, height: 1, indent: 16, endIndent: 16);

  Widget _row(BuildContext context, String label, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(label, style: TextStyles.sectionLabel(context)),
            ),
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              c,
            ],
          ],
        ),
      );

  Widget _dateChip(
    BuildContext context,
    LocalDate date,
    LocalDate today,
    ValueChanged<LocalDate> onPick, {
    LocalDate? earliest,
    LocalDate? latest,
  }) => PropChip(
    icon: Icon(
      Icons.calendar_today_outlined,
      size: 12,
      color: Tokens.of(context).secondary,
    ),
    label: shortDate(date, today),
    onTap: () async {
      final picked = await pickCalendarDate(
        context,
        initial: date,
        earliest: earliest,
        latest: latest,
      );
      if (picked != null) onPick(picked);
    },
  );

  Widget _archivedToggle(Workspace ws) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Include archived', style: TextStyles.bodySecondary(context)),
      const SizedBox(width: 6),
      SizedBox(
        height: 22,
        child: FittedBox(
          child: Switch(
            value: _filters.includeArchived,
            onChanged: (on) {
              // Turning it off also drops archived projects from the selection.
              final archived = {
                for (final p in ws.projects.where((p) => p.archived)) p.id,
              };
              _setFilters(
                ReportFilters(
                  projectIds: on
                      ? _filters.projectIds
                      : _filters.projectIds.difference(archived),
                  includeArchived: on,
                  labelIds: _filters.labelIds,
                  statuses: _filters.statuses,
                  priorities: _filters.priorities,
                ),
                ws,
              );
            },
          ),
        ),
      ),
    ],
  );

  ReportFilters _with({
    Set<String>? projectIds,
    Set<String>? labelIds,
    Set<TaskStatus>? statuses,
    Set<Priority>? priorities,
  }) => ReportFilters(
    projectIds: projectIds ?? _filters.projectIds,
    includeArchived: _filters.includeArchived,
    labelIds: labelIds ?? _filters.labelIds,
    statuses: statuses ?? _filters.statuses,
    priorities: priorities ?? _filters.priorities,
  );

  Set<T> _toggle<T>(Set<T> s, T v) =>
      s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  String _summary<T>(Set<T> selected, String all, String Function(T) name) =>
      switch (selected.length) {
        0 => all,
        1 => name(selected.single),
        final n => '$n selected',
      };

  Widget _projectsMenu(Workspace ws, Tokens t) {
    final active = ws.projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final archived = ws.projects.where((p) => p.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    Widget item(String id, String name, Widget leading) => checkItem(
      name,
      checked: _filters.projectIds.contains(id),
      leading: leading,
      onPressed: () =>
          _setFilters(_with(projectIds: _toggle(_filters.projectIds, id)), ws),
    );
    return PillMenuButton(
      label: _summary(
        _filters.projectIds,
        'All Projects',
        (id) => ws.projectById(id)?.name ?? 'Project',
      ),
      menuChildren: [
        checkItem(
          'All Projects',
          checked: _filters.projectIds.isEmpty,
          onPressed: () => _setFilters(_with(projectIds: {}), ws),
        ),
        item(noProjectId, 'No Project', CubeIcon(color: t.tertiary, size: 12)),
        if (active.isNotEmpty) const Divider(),
        for (final p in active)
          item(p.id, p.name, CubeIcon(color: t.named(p.color), size: 12)),
        if (_filters.includeArchived && archived.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text('Archived', style: TextStyles.meta(context)),
          ),
          for (final p in archived)
            item(p.id, p.name, CubeIcon(color: t.named(p.color), size: 12)),
        ],
      ],
    );
  }

  Widget _labelsMenu(Workspace ws, List<(Label, Project?)> scope, Tokens t) {
    final groups = <String, List<Label>>{};
    for (final (l, p) in scope) {
      (groups[p?.name ?? 'Workspace'] ??= []).add(l);
    }
    final names = {for (final (l, _) in scope) l.id: l.name};
    return PillMenuButton(
      label: _summary(
        _filters.labelIds,
        'All Labels',
        (id) => names[id] ?? 'Label',
      ),
      enabled: scope.isNotEmpty,
      menuChildren: [
        for (final MapEntry(key: group, value: labels) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(group, style: TextStyles.meta(context)),
          ),
          for (final l in labels)
            checkItem(
              l.name,
              checked: _filters.labelIds.contains(l.id),
              leading: ColorDot(color: t.named(l.color)),
              onPressed: () => _setFilters(
                _with(labelIds: _toggle(_filters.labelIds, l.id)),
                ws,
              ),
            ),
        ],
      ],
    );
  }

  Widget _statusMenu(Workspace ws) => PillMenuButton(
    label: _summary(_filters.statuses, 'All Statuses', (s) => s.label),
    menuChildren: [
      for (final s in TaskStatus.values)
        checkItem(
          s.label,
          checked: _filters.statuses.contains(s),
          leading: StatusIcon(s),
          onPressed: () =>
              _setFilters(_with(statuses: _toggle(_filters.statuses, s)), ws),
        ),
    ],
  );

  Widget _priorityMenu(Workspace ws) => PillMenuButton(
    label: _summary(_filters.priorities, 'All Priorities', (p) => p.label),
    menuChildren: [
      for (final p in [
        Priority.none,
        Priority.urgent,
        Priority.high,
        Priority.medium,
        Priority.low,
      ])
        checkItem(
          p.label,
          checked: _filters.priorities.contains(p),
          leading: PriorityIcon(p),
          onPressed: () => _setFilters(
            _with(priorities: _toggle(_filters.priorities, p)),
            ws,
          ),
        ),
    ],
  );

  Widget _copyButton(
    Workspace ws,
    ReportPeriod period,
    LocalDate today,
    int count,
  ) {
    Future<void> copy(ReportKind kind) async {
      final json = buildReportJson(
        ws: ws,
        filters: _filters,
        period: period,
        today: today,
      );
      await Clipboard.setData(ClipboardData(text: buildReportText(kind, json)));
      ref
          .read(toastProvider.notifier)
          .show(
            'Copied ${kind.label} — covers $count ${count == 1 ? 'task' : 'tasks'}',
          );
    }

    return MenuAnchor(
      menuChildren: [
        for (final k in ReportKind.values)
          menuItem(k.label, onPressed: count == 0 ? null : () => copy(k)),
      ],
      builder: (context, controller, _) => FilledButton.icon(
        onPressed: count == 0
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.copy, size: 14),
        label: const Text('Copy  ▾'),
      ),
    );
  }
}
