import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/merge.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/recurrence.dart';
import 'package:tasklet/core/task_ops.dart' as ops;

import '../helpers.dart';

void main() {
  final today = d('2026-11-03'); // a Tuesday
  final now = DateTime.utc(2026, 11, 3, 12);

  group('next occurrence', () {
    String next(Repeat r, String anchor) =>
        nextOccurrence(r, d(anchor), today).toString();

    test('days, weeks, weekdays', () {
      expect(next(Repeat(unit: RepeatUnit.day), '2026-11-03'), '2026-11-04');
      expect(
        next(Repeat(unit: RepeatUnit.week, every: 2), '2026-11-03'),
        '2026-11-17',
      );
      // Friday -> Monday.
      expect(
        next(Repeat(unit: RepeatUnit.weekday), '2026-11-06'),
        '2026-11-09',
      );
    });

    test('months keep their day; short months use their last day', () {
      final monthly = Repeat(unit: RepeatUnit.month, day: 31);
      expect(next(monthly, '2026-11-30'), '2026-12-31');
      expect(next(monthly, '2026-12-31'), '2027-01-31');
      expect(
        nextOccurrence(monthly, d('2027-01-31'), d('2027-01-31')).toString(),
        '2027-02-28',
      );
      expect(
        nextOccurrence(monthly, d('2027-02-28'), d('2027-02-28')).toString(),
        '2027-03-31',
      );
      expect(next(Repeat(unit: RepeatUnit.year), '2026-11-03'), '2027-11-03');
    });

    test('from the due date: never lands on or before today', () {
      // Weekly, due three weeks ago: skips to the next one after today.
      expect(next(Repeat(unit: RepeatUnit.week), '2026-10-13'), '2026-11-10');
    });

    test('from completion: one step from the completion day', () {
      final r = Repeat(
        unit: RepeatUnit.day,
        every: 3,
        from: RepeatFrom.completion,
      );
      expect(next(r, '2026-11-03'), '2026-11-06');
    });
  });

  group('completing a repeating task', () {
    final rule = Repeat(unit: RepeatUnit.week);
    final base = project(
      'p1',
      key: 'WEB',
      nextNumber: 8,
      tasks: [
        task(
          't1',
          number: 7,
          title: 'Pay the invoice',
          due: d('2026-11-03'),
          start: d('2026-11-01'),
        ).copyWith(
          repeat: rule,
          checklist: [ChecklistItem(id: 'a', text: 'Check', done: true)],
        ),
      ],
    );

    (Project, Task)? complete(Project p) {
      final before = p.tasks.single;
      final after = ops.editTask(
        before,
        (t) => t.copyWith(status: TaskStatus.done),
        now,
      )!;
      return completeRepeating(
        ops.putTask(p, after, now),
        before,
        after,
        today: today,
        now: now,
      );
    }

    test('the done task stays; the next one takes the rule', () {
      final (project, next) = complete(base)!;
      final done = project.taskById('t1')!;
      expect(done.isDone, isTrue);
      expect(done.repeat, isNull);
      expect(next.id, 't1~20261110');
      expect(next.number, 8);
      expect(project.nextNumber, 9);
      expect(next.status, TaskStatus.todo);
      expect(next.dueDate.toString(), '2026-11-10');
      expect(next.startDate.toString(), '2026-11-08'); // same distance
      expect(next.repeat!.sameAs(rule), isTrue);
      expect(next.checklist.single.done, isFalse);
    });

    test('not repeating, already done, or not done: nothing', () {
      final plain = project('p2', tasks: [task('x', due: today)]);
      expect(complete(plain), isNull);
      final t = base.tasks.single;
      expect(completeRepeating(base, t, t, today: today, now: now), isNull);
    });

    test('two computers completing it make one next task after the merge', () {
      final (mine, _) = complete(base)!;
      final (theirs, _) = complete(base)!;
      final merged = mergeProject(
        base: base,
        mine: mine,
        theirs: theirs,
        now: now,
      ).project;
      expect(merged.tasks.map((t) => t.id).toSet(), {'t1', 't1~20261110'});
    });
  });

  test('repeat round trip; an unreadable rule is kept verbatim', () {
    final t = task('t1').copyWith(
      repeat: Repeat(unit: RepeatUnit.month, from: RepeatFrom.completion),
    );
    expect(t.toJson()['repeat'], {
      'every': 1,
      'unit': 'month',
      'from': 'completion',
    });
    expect(Task.fromJson(t.toJson()).repeat!.unit, RepeatUnit.month);
    expect(task('t2').toJson().containsKey('repeat'), isFalse);
    final odd = {'unit': 'fortnight'};
    final read = Task.fromJson({...task('t3').toJson(), 'repeat': odd});
    expect(read.repeat, isNull);
    expect(read.toJson()['repeat'], odd);
  });
}
