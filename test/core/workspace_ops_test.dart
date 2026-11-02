import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/task_ops.dart';
import 'package:tasklet/core/workspace_ops.dart';

import '../helpers.dart';

void main() {
  test('a new project goes last with the next free key', () {
    final existing = [
      project('a', key: 'WEB'),
      Project(
        id: 'b',
        name: 'B',
        key: 'BBB',
        sortOrder: 4000,
        createdAt: t0,
        updatedAt: t0,
      ),
    ];
    final p = newProject(
      id: 'n',
      name: ' Website ',
      color: TaskletColor.green,
      existing: existing,
      now: t0,
    );
    expect(p.name, 'Website');
    expect(p.key, 'WEB1');
    expect(p.sortOrder, 5000);
  });

  test('orderAfterAll puts an item after every pinned one', () {
    expect(orderAfterAll([]), 0);
    expect(orderAfterAll([-3000, 2000, 500]), 3000);
  });

  test('stripLabel removes the label from the project and its tasks, or reports no change', () {
    final l = Label(id: 'l1', name: 'bug', color: TaskletColor.red);
    final p = project(
      'p',
      labels: [l],
      tasks: [
        task('a', labels: ['l1', 'l2']),
        task('b', labels: ['l2']),
      ],
    );
    final stripped = stripLabel(p, 'l1', at(5))!;
    expect(stripped.labels, isEmpty);
    expect(stripped.taskById('a')!.labelIds, ['l2']);
    expect(stripped.taskById('a')!.updatedAt, at(5));
    expect(stripped.taskById('b')!.updatedAt, t0, reason: 'untouched task');
    expect(stripLabel(project('q', tasks: [task('c')]), 'l1', at(5)), isNull);
  });

  test('a restored backup keeps the key, never lowers nextNumber, leaves moved tasks out', () {
    final current = project('p', key: 'NEW', nextNumber: 30);
    final backup = project(
      'p',
      key: 'OLD',
      nextNumber: 10,
      tasks: [task('stays', number: 1), task('moved', number: 2)],
    );
    final r = restoredFromBackup(
      current: current,
      backup: backup,
      elsewhere: {'moved'},
      now: at(9),
    );
    expect(r.leftOut, 1);
    expect(r.project.key, 'NEW');
    expect(r.project.nextNumber, 30);
    expect([for (final t in r.project.tasks) t.id], ['stays']);
  });

  group('task edits', () {
    test(
      'editTask maintains completedAt and refuses a start after the due date',
      () {
        final t = task('a', start: d('2026-10-05'), due: d('2026-10-10'));
        final done = editTask(
          t,
          (x) => x.copyWith(status: TaskStatus.done),
          at(3),
        )!;
        expect(done.completedAt, at(3));
        expect(done.updatedAt, at(3));
        final reopened = editTask(
          done,
          (x) => x.copyWith(status: TaskStatus.todo),
          at(4),
        )!;
        expect(reopened.completedAt, isNull);
        expect(
          editTask(t, (x) => x.copyWith(startDate: d('2026-10-20')), at(5)),
          isNull,
        );
      },
    );

    test('undo of a move restores the old number when it is still free', () {
      final snapshot = task('t', number: 7);
      final original = project('o', nextNumber: 8);
      final current = project('c', tasks: [snapshot.copyWith(number: 1)]);
      final (back, out) = restoreMovedTask(original, current, snapshot, at(1));
      expect(back.taskById('t')!.number, 7);
      expect(out.taskById('t'), isNull);

      final taken = project('o', tasks: [task('x', number: 7)], nextNumber: 8);
      final (back2, _) = restoreMovedTask(taken, current, snapshot, at(1));
      expect(back2.taskById('t')!.number, 8);
      expect(back2.nextNumber, 9);
    });
  });
}
