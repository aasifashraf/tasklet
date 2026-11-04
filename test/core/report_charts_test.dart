import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/report_charts.dart';
import 'package:tasklet/core/report_prompt.dart';

void main() {
  final json = <String, Object?>{
    'report': {
      'today': '2026-10-15',
      'period': {
        'from': '2026-10-01',
        'to': '2026-10-31',
        'name': 'This Month',
      },
    },
    'totals': {
      'tasks': 6,
      'byStatusNow': {'Todo': 2, 'In Progress': 1, 'Done': 3},
      'byPriority': {'High': 2, 'No Priority': 4},
    },
    'timeline': {
      'weeks': [
        {'label': 'Week of Oct 1', 'completed': 1},
        {'label': 'Week of Oct 8', 'completed': 2},
      ],
    },
    'projects': [
      {
        'name': 'Web "Redesign"',
        'totals': {'tasks': 4},
      },
      {
        'name': 'Home',
        'totals': {'tasks': 2},
      },
    ],
  };

  test('builds status, priority, timeline and project charts', () {
    final charts = chartsForReport(json);
    expect(charts.map((c) => c.title), [
      'Tasks by status today',
      'Tasks by priority',
      'Completed per week',
      'Tasks by project',
    ]);
  });

  test('pie and bar charts produce valid-looking Mermaid', () {
    final charts = chartsForReport(json);
    expect(
      charts.first.mermaid,
      startsWith('pie title Tasks by status today\n'),
    );
    expect(charts.first.mermaid, contains('"Done" : 3'));
    final weekly = charts[2].mermaid;
    expect(weekly, startsWith('xychart-beta'));
    expect(weekly, contains('x-axis ["Week of Oct 1", "Week of Oct 8"]'));
    expect(weekly, contains('bar [1, 2]'));
    expect(
      charts.last.mermaid,
      contains("\"Web 'Redesign'\""),
      reason: 'quotes are escaped',
    );
  });

  test('empty data produces no charts', () {
    expect(chartsForReport({'totals': <String, Object?>{}}), isEmpty);
  });

  test('charts are included in prompts only when requested', () {
    final charts = chartsForReport(json);
    final withCharts = buildReportText(ReportKind.report, json, charts: charts);
    expect('```mermaid'.allMatches(withCharts).length, 4);
    expect(
      withCharts.indexOf('```mermaid'),
      lessThan(withCharts.indexOf('```json')),
    );
    expect(
      buildReportText(ReportKind.report, json),
      isNot(contains('```mermaid')),
    );
    expect(
      buildReportText(ReportKind.json, json, charts: charts),
      isNot(contains('mermaid')),
    );
  });

  test('export file name shows the report period', () {
    expect(
      reportFileName(ReportKind.report, json),
      'Tasklet Report Prompt 2026-10-01 to 2026-10-31.txt',
    );
    expect(
      reportFileName(ReportKind.summary, json),
      'Tasklet Summary Prompt 2026-10-01 to 2026-10-31.txt',
    );
    expect(
      reportFileName(ReportKind.json, json),
      'Tasklet Report Data 2026-10-01 to 2026-10-31.json',
    );
    final oneDay = {
      'report': {
        'period': {'from': '2026-11-01', 'to': '2026-11-01'},
      },
    };
    expect(
      reportFileName(ReportKind.report, oneDay),
      'Tasklet Report Prompt 2026-11-01.txt',
    );
  });

  test('insights and the open trend', () {
    final json = <String, Object?>{
      'totals': {
        'completedInPeriod': 12,
        'createdInPeriod': 9,
        'openNow': 30,
        'overdueNow': 2,
        'averageDaysToCompleteInPeriod': 3.5,
      },
      'timeline': {
        'weeks': [
          {'label': 'W1', 'completed': 5, 'openAtEnd': 20},
          {'label': 'W2', 'completed': 4, 'openAtEnd': 24},
          {'label': 'W3', 'completed': 3, 'openAtEnd': 30},
        ],
      },
    };
    expect(reportInsights(json), [
      ('Completed', '12'),
      ('Created', '9'),
      ('Per week', '4.0'),
      ('Days to complete', '3.5'),
      ('Open now', '30'),
      ('Overdue now', '2'),
    ]);
    final open = chartsForReport(json)
        .firstWhere((c) => c.title == 'Open at the end of each week');
    expect(open.points.map((p) => p.value), [20, 24, 30]);
  });
}
