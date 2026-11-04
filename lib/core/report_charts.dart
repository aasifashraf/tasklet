// Charts derived from the report JSON (SPEC §4.9 "visuals first"): each chart carries its data (for the in-app
// preview) and its Mermaid source (for the exported text file).

/// One labelled value in a chart.
class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final num value;
}

enum ChartKind { pie, bar }

class ReportChart {
  const ReportChart({
    required this.title,
    required this.kind,
    required this.points,
  });
  final String title;
  final ChartKind kind;
  final List<ChartPoint> points;

  /// Mermaid source for this chart.
  String get mermaid {
    String q(String s) => s.replaceAll('"', "'");
    if (kind == ChartKind.pie) {
      return [
        'pie title ${q(title)}',
        for (final p in points) '    "${q(p.label)}" : ${p.value}',
      ].join('\n');
    }
    final max = points.fold<num>(0, (m, p) => p.value > m ? p.value : m);
    return [
      'xychart-beta',
      '    title "${q(title)}"',
      '    x-axis [${points.map((p) => '"${q(p.label)}"').join(', ')}]',
      '    y-axis "Tasks" 0 --> ${max < 1 ? 1 : max}',
      '    bar [${points.map((p) => p.value).join(', ')}]',
    ].join('\n');
  }
}

Map<String, Object?> _map(Object? v) =>
    v is Map<String, Object?> ? v : const {};
List<Object?> _list(Object? v) => v is List<Object?> ? v : const [];
num _num(Object? v) => v is num ? v : 0;

/// The charts worth drawing for this report: status now, priority, completions over time (if there is a timeline),
/// and tasks per project (if there are several). Empty charts are skipped.
List<ReportChart> chartsForReport(Map<String, Object?> json) {
  final totals = _map(json['totals']);
  final charts = <ReportChart>[];

  List<ChartPoint> points(Map<String, Object?> counts) => [
    for (final e in counts.entries)
      if (_num(e.value) > 0) ChartPoint(e.key, _num(e.value)),
  ];

  final status = points(_map(totals['byStatusNow']));
  if (status.isNotEmpty) {
    charts.add(
      ReportChart(
        title: 'Tasks by status today',
        kind: ChartKind.pie,
        points: status,
      ),
    );
  }

  final priority = points(_map(totals['byPriority']));
  if (priority.length > 1) {
    charts.add(
      ReportChart(
        title: 'Tasks by priority',
        kind: ChartKind.pie,
        points: priority,
      ),
    );
  }

  final timeline = _map(json['timeline']);
  final buckets = _list(timeline['weeks']).isNotEmpty
      ? _list(timeline['weeks'])
      : _list(timeline['months']);
  final completed = [
    for (final b in buckets)
      ChartPoint('${_map(b)['label'] ?? ''}', _num(_map(b)['completed'])),
  ];
  if (completed.any((p) => p.value > 0)) {
    final unit = _list(timeline['weeks']).isNotEmpty ? 'week' : 'month';
    charts.add(
      ReportChart(
        title: 'Completed per $unit',
        kind: ChartKind.bar,
        points: completed,
      ),
    );
  }

  // The backlog trend: open tasks at the end of each week (or month).
  final open = [
    for (final b in buckets)
      ChartPoint('${_map(b)['label'] ?? ''}', _num(_map(b)['openAtEnd'])),
  ];
  if (open.length > 1 && open.any((p) => p.value > 0)) {
    final unit = _list(timeline['weeks']).isNotEmpty ? 'week' : 'month';
    charts.add(
      ReportChart(
        title: 'Open at the end of each $unit',
        kind: ChartKind.bar,
        points: open,
      ),
    );
  }

  final projects = [
    for (final p in _list(json['projects']))
      ChartPoint(
        '${_map(p)['name'] ?? ''}',
        _num(_map(_map(p)['totals'])['tasks']),
      ),
  ];
  if (projects.length > 1) {
    charts.add(
      ReportChart(
        title: 'Tasks by project',
        kind: ChartKind.bar,
        points: projects,
      ),
    );
  }

  return charts;
}

/// The headline numbers above the charts (Reports, D17 insights): (label, value) pairs, empty values left out.
List<(String, String)> reportInsights(Map<String, Object?> json) {
  final totals = _map(json['totals']);
  final timeline = _map(json['timeline']);
  final weeks = _list(timeline['weeks']);
  final completed = _num(totals['completedInPeriod']);
  final average = totals['averageDaysToCompleteInPeriod'];
  return [
    ('Completed', '$completed'),
    // The report leaves zero counts out, so a missing count is 0.
    ('Created', '${_num(totals['createdInPeriod'])}'),
    if (weeks.length > 1)
      ('Per week', (completed / weeks.length).toStringAsFixed(1)),
    if (average is num) ('Days to complete', '$average'),
    ('Open now', '${_num(totals['openNow'])}'),
    ('Overdue now', '${_num(totals['overdueNow'])}'),
  ];
}
