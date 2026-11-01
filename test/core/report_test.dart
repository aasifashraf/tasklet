import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/report.dart';
import 'package:tasklet/core/report_prompt.dart';

import '../helpers.dart';

void main() {
  final today = d('2026-10-15');
  DateTime day(String s) =>
      LocalDate.parse(s).toLocalDateTime().add(const Duration(hours: 12));

  group('periods', () {
    test('weeks honor the first day of week; months and last 30 days', () {
      final mon = periodFor(
        PeriodPreset.thisWeek,
        today,
        firstDayOfWeek: DateTime.monday,
      );
      expect((mon.from, mon.to), (d('2026-10-12'), d('2026-10-18')));
      final sun = periodFor(
        PeriodPreset.lastWeek,
        today,
        firstDayOfWeek: DateTime.sunday,
      );
      expect((sun.from, sun.to), (d('2026-10-04'), d('2026-10-10')));
      final lastMonth = periodFor(
        PeriodPreset.lastMonth,
        today,
        firstDayOfWeek: 1,
      );
      expect(
        (lastMonth.from, lastMonth.to),
        (d('2026-09-01'), d('2026-09-30')),
      );
      final last30 = periodFor(
        PeriodPreset.last30Days,
        today,
        firstDayOfWeek: 1,
      );
      expect(last30.days, 30);
    });

    test('custom range swaps reversed dates', () {
      final p = periodFor(
        PeriodPreset.custom,
        today,
        firstDayOfWeek: 1,
        customFrom: d('2026-10-20'),
        customTo: d('2026-10-01'),
      );
      expect((p.from, p.to), (d('2026-10-01'), d('2026-10-20')));
    });
  });

  group('in range', () {
    final period = ReportPeriod(d('2026-10-05'), d('2026-10-11'), 'Week');

    test('open during the period', () {
      expect(inRange(task('a', created: day('2026-09-01')), period), isTrue);
      expect(inRange(task('b', created: day('2026-10-20')), period), isFalse);
    });

    test('completed before the period is out, completed within is in', () {
      expect(
        inRange(
          task(
            'a',
            created: day('2026-09-01'),
            status: TaskStatus.done,
            completed: day('2026-09-10'),
          ),
          period,
        ),
        isFalse,
      );
      expect(
        inRange(
          task(
            'b',
            created: day('2026-09-01'),
            status: TaskStatus.done,
            completed: day('2026-10-06'),
          ),
          period,
        ),
        isTrue,
      );
    });

    test(
      'start or due date inside the period counts even if created later',
      () {
        expect(
          inRange(
            task('a', created: day('2026-10-20'), due: d('2026-10-07')),
            period,
          ),
          isTrue,
        );
        expect(
          inRange(
            task('b', created: day('2026-10-20'), start: d('2026-10-07')),
            period,
          ),
          isTrue,
        );
      },
    );
  });

  group('json', () {
    Workspace ws() {
      final bug = Label(id: 'l-bug', name: 'Bug', color: TaskletColor.red);
      final web = project(
        'p-web',
        name: 'Website',
        key: 'WEB',
        labels: [bug],
        tasks: [
          task(
            't1',
            number: 1,
            title: 'Done in period',
            status: TaskStatus.done,
            priority: Priority.high,
            created: day('2026-10-01'),
            completed: day('2026-10-06'),
            labels: ['l-bug'],
          ),
          task(
            't2',
            number: 2,
            title: 'Still open',
            created: day('2026-10-02'),
            due: d('2026-10-10'),
          ),
        ],
      );
      final web2 = project(
        'p-web2',
        name: 'Website',
        key: 'WEB1',
        tasks: [task('t3', title: 'Twin', created: day('2026-10-06'))],
      );
      return Workspace(
        folder: '/x',
        projects: [web, web2],
        noProject: Project.noProject(t0),
        noProjectOnDisk: false,
      );
    }

    final period = ReportPeriod(
      d('2026-10-05'),
      d('2026-10-11'),
      'Custom Range',
    );

    test('no uuids, names not ids, YYYY-MM-DD dates, empty fields omitted', () {
      final json = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(),
        period: period,
        today: today,
      );
      final text = json.toString();
      expect(text.contains('p-web'), isFalse);
      expect(text.contains('l-bug'), isFalse);
      expect(text.contains('t1'), isFalse);
      final report = json['report']! as Map;
      expect(report.containsKey('filters'), isFalse);
      expect(report.containsKey('includesArchivedProjects'), isFalse);
      final projects = json['projects']! as List;
      expect(
        [for (final p in projects) (p as Map)['name']],
        ['Website (WEB)', 'Website (WEB1)'],
      );
      final done = ((projects.first as Map)['tasks'] as List).first as Map;
      expect(done['labels'], ['Bug']);
      expect(done['priority'], 'High');
      expect(done['completed'], '2026-10-06');
      expect(done['atPeriodEnd'], 'done');
      expect(done['daysToComplete'], 5);
      expect(done.containsKey('description'), isFalse);
      expect(done.containsKey('overdueNowByDays'), isFalse);
      final open = ((projects.first as Map)['tasks'] as List).last as Map;
      expect(open['overdueNowByDays'], 5);
      expect(open.containsKey('priority'), isFalse);
    });

    test('totals are pre-computed', () {
      final json = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(),
        period: period,
        today: today,
      );
      final totals = json['totals']! as Map;
      expect(totals['tasks'], 3);
      expect(totals['completedInPeriod'], 1);
      expect(totals['openAtPeriodEnd'], 2);
      expect(totals['overdueNow'], 1);
      expect(totals['byLabel'], {'Bug': 1});
      expect(totals['averageDaysToCompleteInPeriod'], 5.0);
    });

    test('filters are listed once and narrow the tasks', () {
      final json = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(statuses: {TaskStatus.done}),
        period: period,
        today: today,
      );
      expect((json['report']! as Map)['filters'], {
        'status': ['Done'],
      });
      expect((json['totals']! as Map)['tasks'], 1);
    });

    test('timeline buckets by span length', () {
      final shortJson = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(),
        period: period,
        today: today,
      );
      expect(shortJson.containsKey('timeline'), isFalse);
      final month = ReportPeriod(
        d('2026-10-01'),
        d('2026-10-31'),
        'This Month',
      );
      final monthJson = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(),
        period: month,
        today: today,
      );
      final timeline = monthJson['timeline']! as Map;
      expect(timeline.containsKey('weeks'), isTrue);
      expect(timeline.containsKey('months'), isFalse);
    });

    test('all time reports the actual earliest-to-today span', () {
      final json = buildReportJson(
        ws: ws(),
        filters: const ReportFilters(),
        period: periodFor(PeriodPreset.allTime, today, firstDayOfWeek: 1),
        today: today,
      );
      final p = (json['report']! as Map)['period']! as Map;
      expect(p['from'], '2026-10-01');
      expect(p['to'], '2026-10-15');
    });
  });

  group('prompt text', () {
    final json = {
      'report': {
        'today': '2026-10-15',
        'period': {
          'from': '2026-10-05',
          'to': '2026-10-11',
          'name': 'Last Week',
        },
      },
      'totals': {'tasks': 3},
      'projects': [
        {'name': 'A'},
        {'name': 'B'},
      ],
    };

    test('report prompt has sections in order and the fenced JSON', () {
      final text = buildReportText(ReportKind.report, json);
      expect(text, startsWith('Below is task data'));
      expect(text, contains('Oct 5, 2026 to Oct 11, 2026'));
      expect(
        text.indexOf('How to read the data'),
        lessThan(text.indexOf('Writing rules')),
      );
      expect(
        text.indexOf('Writing rules'),
        lessThan(text.indexOf('Visuals first')),
      );
      expect(text, contains('By project'));
      expect(text, isNot(contains('By label')));
      expect(text, contains('"None."'));
      expect(text.trimRight(), endsWith('```'));
      expect(text, contains('```json'));
    });

    test('summary prompt asks for under 200 words without headings', () {
      final text = buildReportText(ReportKind.summary, json);
      expect(text, contains('under 200 words'));
      expect(text, isNot(contains('timeline')));
    });

    test('json only is just the JSON', () {
      expect(
        buildReportText(ReportKind.json, json).trimLeft(),
        startsWith('{'),
      );
    });
  });
}
