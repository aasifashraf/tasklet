import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/ordering.dart';
import 'package:tasklet/core/project_keys.dart';
import 'package:tasklet/core/report.dart';
import 'package:tasklet/core/task_ops.dart';

import '../helpers.dart';

/// Repairs for data that syncing, other tools or long use can produce (audit, Nov 2026).
void main() {
  group('duplicate task numbers', () {
    test('the oldest task keeps the number, newer ones get fresh numbers', () {
      final p = project(
        'p1',
        tasks: [
          task(
            'b',
            number: 13,
            created: at(5),
          ), // created later on another computer
          task('a', number: 13, created: at(1)),
          task('c', number: 14, created: at(2)),
        ],
      );
      final fixed = resolveDuplicateNumbers(p)!;
      final byId = {for (final t in fixed.tasks) t.id: t.number};
      expect(byId, {'a': 13, 'b': 15, 'c': 14});
      expect(fixed.nextNumber, 16);
      expect(resolveDuplicateNumbers(fixed), isNull);
    });

    test(
      'numbers of entries this version cannot show are never handed out',
      () {
        final p = Project(
          id: 'p1',
          name: 'P',
          key: 'PPP',
          createdAt: t0,
          updatedAt: t0,
          tasks: [task('a', number: 3)],
          opaqueTasks: [
            {'id': 'x', 'number': 3},
          ],
        );
        expect(resolveDuplicateNumbers(p)!.tasks.single.number, 4);
      },
    );

    test('unique numbers need no repair', () {
      expect(
        resolveDuplicateNumbers(
          project('p1', tasks: [task('a', number: 1), task('b', number: 2)]),
        ),
        isNull,
      );
    });
  });

  test('a stored key that is not a valid key is regenerated from the name', () {
    final projects = [
      project('p1', name: 'Website', key: 'W-B'),
      project('p2', name: 'Mobile', key: 'MOB2'),
      project('p3', name: 'Docs', key: 'THISKEYISWAYTOOLONG'),
    ];
    expect(resolveProjectKeys(projects), {'p1': 'WEB', 'p3': 'DOC'});
  });

  test('filter values from a newer version survive a round trip', () {
    final filters = BoardFilters.fromJson({
      'status': ['todo', 'blocked'],
      'priorities': [1, 9],
      'due': ['overdue', 'someday'],
    });
    expect(filters.status, {TaskStatus.todo});
    final edited = filters.copyWith(priorities: {Priority.high});
    final json = edited.toJson();
    expect(json['status'], ['todo', 'blocked']);
    expect(json['priorities'], [Priority.high.value, 9]);
    expect(json['due'], contains('someday'));
    expect(edited.cleared().toJson()['status'], isEmpty);
  });

  group('manual order', () {
    test('a drop between distinct neighbours moves only the card', () {
      final r = placeInColumn([0, 1000, 2000], 1);
      expect(r.value, 500);
      expect(r.respaced, isEmpty);
    });

    test(
      'a drop between equal neighbours re-spaces them so the card lands there',
      () {
        final column = <double>[-5, 0, 0, 0, 7];
        final r = placeInColumn(column, 2); // between the 2nd and 3rd zero
        final updated = [...column];
        r.respaced.forEach((i, v) => updated[i] = v);
        final result = [
          ...updated.sublist(0, 2),
          r.value,
          ...updated.sublist(2),
        ];
        for (var i = 1; i < result.length; i++) {
          expect(result[i], greaterThan(result[i - 1]), reason: '$result');
        }
        expect(result.first, -5);
        expect(result.last, 7);
      },
    );

    test('repeated drops at the same spot never run out of room', () {
      var column = <double>[0, 1];
      for (var n = 0; n < 200; n++) {
        final r = placeInColumn(column, 1);
        final updated = [...column];
        r.respaced.forEach((i, v) => updated[i] = v);
        column = [updated[0], r.value, ...updated.sublist(1)];
        for (var i = 1; i < column.length; i++) {
          expect(column[i], greaterThan(column[i - 1]));
        }
      }
    });
  });

  group('reports', () {
    final today = d('2026-10-20');
    Workspace ws(List<Task> tasks) => Workspace(
      folder: '/x',
      projects: [project('p1', name: 'Web', key: 'WEB', tasks: tasks)],
      noProject: Project.noProject(t0),
      noProjectOnDisk: false,
    );

    test('a done task without completedAt counts as completed, never negative days', () {
      final json = buildReportJson(
        ws: ws([
          task(
            'a',
            status: TaskStatus.done,
            created: DateTime.utc(2026, 10, 10),
            updated: DateTime.utc(2026, 10, 12),
          ),
          task(
            'b',
            number: 2,
            status: TaskStatus.done,
            created: DateTime.utc(2026, 10, 15),
            completed: DateTime.utc(2026, 10, 13), // clock skew
          ),
        ]),
        filters: const ReportFilters(),
        period: periodFor(PeriodPreset.thisMonth, today, firstDayOfWeek: 1),
        today: today,
      );
      final totals = json['totals']! as Map;
      expect(totals['completedInPeriod'], 2);
      expect(totals.containsKey('openAtPeriodEnd'), isFalse);
      expect(totals['averageDaysToCompleteInPeriod'], 1.0);
    });

    test('a very wide custom range stays a small timeline', () {
      final json = buildReportJson(
        ws: ws([task('a', created: DateTime.utc(2026, 1, 5))]),
        filters: const ReportFilters(),
        period: ReportPeriod(
          LocalDate(1, 1, 2),
          LocalDate(9999, 12, 31),
          'Custom Range',
        ),
        today: today,
      );
      final timeline = json['timeline'] as Map?;
      final months = (timeline?['months'] as List?) ?? const [];
      expect(months.length, lessThan(3));
    });
  });
}
