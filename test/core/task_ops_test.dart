import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/dates.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/ordering.dart';
import 'package:tasklet/core/task_ops.dart';

import '../helpers.dart';

void main() {
  group('ordering', () {
    test('midpoint between neighbors, ±1000 at the ends', () {
      expect(sortOrderBetween(null, null), 0);
      expect(sortOrderBetween(null, 50), -950);
      expect(sortOrderBetween(50, null), 1050);
      expect(sortOrderBetween(0, 1000), 500);
      expect(sortOrderBetween(1, 2), 1.5);
    });

    test('top of column is below the minimum', () {
      expect(sortOrderAtTop([]), 0);
      expect(sortOrderAtTop([5, -20, 100]), -1020);
    });
  });

  group('dates', () {
    test('next Monday is always after today and never a weekend', () {
      expect(
        nextMondayAfter(d('2026-10-12')),
        d('2026-10-19'),
      ); // Monday → next Monday
      expect(nextMondayAfter(d('2026-10-17')), d('2026-10-19')); // Saturday
      expect(nextMondayAfter(d('2026-10-18')), d('2026-10-19')); // Sunday
      expect(nextMondayAfter(d('2026-10-16')), d('2026-10-19')); // Friday
    });

    test('start of week honors the first day of week', () {
      final thu = d('2026-10-15');
      expect(startOfWeek(thu, DateTime.monday), d('2026-10-12'));
      expect(startOfWeek(thu, DateTime.sunday), d('2026-10-11'));
      expect(startOfWeek(d('2026-10-11'), DateTime.sunday), d('2026-10-11'));
    });

    test('month bounds and leap years', () {
      expect(endOfMonth(d('2028-02-10')), d('2028-02-29'));
      expect(endOfMonth(d('2026-12-03')), d('2026-12-31'));
      expect(startOfMonth(d('2026-12-03')), d('2026-12-01'));
    });

    test('LocalDate parsing and arithmetic', () {
      expect(d('2026-12-31').addDays(1), d('2027-01-01'));
      expect(d('2026-10-01').daysUntil(d('2026-10-15')), 14);
      expect(() => LocalDate.parse('2026-2-1'), throwsFormatException);
      expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
    });
  });

  group('task ops', () {
    test(
      'create assigns sequential numbers and lands at the top of its status',
      () {
        var p = project('p', tasks: [task('a', number: 1, sortOrder: 0)]);
        final (p2, t2) = createTask(p, id: 'b', title: 'B', now: at(1));
        expect(t2.number, 2);
        expect(t2.sortOrder, -1000);
        expect(p2.nextNumber, 3);
        p = p2;
        final (p3, t3) = createTask(
          p,
          id: 'c',
          title: 'C',
          status: TaskStatus.done,
          now: at(2),
        );
        expect(t3.completedAt, at(2));
        expect(t3.sortOrder, 0); // first in Done
        expect(p3.updatedAt, at(2));
      },
    );

    test('numbers are never reused after delete', () {
      final (p1, t1) = createTask(
        project('p'),
        id: 'a',
        title: 'A',
        now: at(0),
      );
      final p2 = removeTask(p1, t1.id, at(1));
      final (_, t2) = createTask(p2, id: 'b', title: 'B', now: at(2));
      expect(t2.number, 2);
    });

    test('status change maintains completedAt', () {
      final t = task('a');
      final done = withStatus(t, TaskStatus.done, at(5));
      expect(done.completedAt, at(5));
      expect(done.updatedAt, at(5));
      expect(withStatus(done, TaskStatus.done, at(9)).completedAt, at(5));
      expect(withStatus(done, TaskStatus.todo, at(6)).completedAt, isNull);
    });

    test(
      'putTask replaces or inserts (undo of delete restores exact fields)',
      () {
        final original = task('a', number: 4, title: 'Keep me');
        var p = project('p', tasks: [original]);
        p = removeTask(p, 'a', at(1));
        p = putTask(p, original, at(2));
        expect(p.taskById('a')!.toJson(), original.toJson());
        p = putTask(p, original.copyWith(title: 'Edited'), at(3));
        expect(p.tasks.length, 1);
        expect(p.taskById('a')!.title, 'Edited');
      },
    );

    test('duplicate copies fields but not history', () {
      final source = task(
        'a',
        number: 1,
        status: TaskStatus.done,
        priority: Priority.high,
        due: d('2026-10-09'),
        labels: ['bug'],
        completed: at(-100),
      );
      final (p, copy) = duplicateTask(
        project('p', tasks: [source]),
        source,
        newId: 'b',
        now: at(1),
      );
      expect(copy.number, 2);
      expect(copy.priority, Priority.high);
      expect(copy.labelIds, ['bug']);
      expect(copy.completedAt, at(1));
      expect(copy.createdAt, at(1));
      expect(p.tasks.length, 2);
    });

    test('move issues a new number, drops invalid labels, and can restore the original number', () {
      final t = task(
        'a',
        number: 3,
        labels: ['projectLabel', 'workspaceLabel'],
      );
      final from = project('from', tasks: [t]);
      final to = project('to', tasks: [task('x', number: 1)]);
      final (from2, to2, moved) = moveTask(
        from,
        to,
        t,
        allowedLabelIds: {'workspaceLabel'},
        now: at(1),
      );
      expect(from2.tasks, isEmpty);
      expect(moved.number, 2);
      expect(moved.labelIds, ['workspaceLabel']);
      expect(to2.nextNumber, 3);

      // Undo: move back restoring number 3, which is still free in the original project.
      final (_, back, restored) = moveTask(
        to2,
        from2,
        moved,
        allowedLabelIds: {},
        restoreNumber: 3,
        now: at(2),
      );
      expect(restored.number, 3);
      expect(back.nextNumber, 4);
    });

    test('restore number falls back to a new number when taken', () {
      final t = task('a', number: 1);
      final to = project('to', tasks: [task('x', number: 1)]);
      final (_, _, moved) = moveTask(
        project('from', tasks: [t]),
        to,
        t,
        allowedLabelIds: {},
        restoreNumber: 1,
        now: at(1),
      );
      expect(moved.number, 2);
    });
  });

  test('a start date may not fall after the due date', () {
    expect(datesInOrder(null, null), isTrue);
    expect(datesInOrder(d('2026-10-02'), null), isTrue);
    expect(datesInOrder(null, d('2026-10-02')), isTrue);
    expect(datesInOrder(d('2026-10-02'), d('2026-10-02')), isTrue);
    expect(datesInOrder(d('2026-10-01'), d('2026-10-02')), isTrue);
    expect(datesInOrder(d('2026-10-03'), d('2026-10-02')), isFalse);
  });
}
