import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/merge.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

/// Two computers editing one project file (docs/SYSTEM_DESIGN.md section 14).
void main() {
  final now = at(100);
  final base = project(
    'p',
    name: 'Web',
    key: 'WEB',
    nextNumber: 4,
    tasks: [
      task('a', number: 1, title: 'A'),
      task('b', number: 2, title: 'B'),
      task('c', number: 3, title: 'C'),
    ],
  );

  Project edit(Project p, String id, Task Function(Task t) change) =>
      p.copyWith(tasks: [for (final t in p.tasks) t.id == id ? change(t) : t]);

  test('edits to different tasks on each computer are both kept', () {
    final mine = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'A mine', updatedAt: at(10)),
    );
    final theirs = edit(
      base,
      'b',
      (t) => t.copyWith(title: 'B theirs', updatedAt: at(11)),
    );
    final r = mergeProject(base: base, mine: mine, theirs: theirs, now: now);
    expect(r.project.taskById('a')!.title, 'A mine');
    expect(r.project.taskById('b')!.title, 'B theirs');
    expect(r.notes, isEmpty);
  });

  test('different fields of one task merge field by field', () {
    final mine = edit(
      base,
      'a',
      (t) => t.copyWith(priority: Priority.high, updatedAt: at(10)),
    );
    final theirs = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'Renamed there', updatedAt: at(12)),
    );
    final a = mergeProject(
      base: base,
      mine: mine,
      theirs: theirs,
      now: now,
    ).project.taskById('a')!;
    expect(a.priority, Priority.high);
    expect(a.title, 'Renamed there');
  });

  test('the same field changed on both computers: the newer edit wins', () {
    final mine = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'Mine', updatedAt: at(20)),
    );
    final theirs = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'Theirs', updatedAt: at(15)),
    );
    expect(
      mergeProject(
        base: base,
        mine: mine,
        theirs: theirs,
        now: now,
      ).project.taskById('a')!.title,
      'Mine',
    );
  });

  test('a clock far ahead does not win every conflict', () {
    final mine = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'Mine', updatedAt: at(100)),
    );
    final theirs = edit(
      base,
      'a',
      (t) =>
          t.copyWith(title: 'Wrong clock', updatedAt: at(100 + 60 * 24 * 30)),
    );
    expect(
      mergeProject(
        base: base,
        mine: mine,
        theirs: theirs,
        now: now,
      ).project.taskById('a')!.title,
      'Mine',
      reason:
          'theirs counts as "now", mine (99) loses only to a real later edit',
    );
  });

  test('deleted there and untouched here: stays deleted', () {
    final theirs = base.copyWith(
      tasks: base.tasks.where((t) => t.id != 'c').toList(),
    );
    final mine = edit(
      base,
      'a',
      (t) => t.copyWith(title: 'A2', updatedAt: at(5)),
    );
    final r = mergeProject(base: base, mine: mine, theirs: theirs, now: now);
    expect(r.project.taskById('c'), isNull);
    expect(r.project.taskById('a')!.title, 'A2');
  });

  test(
    'deleted on one computer but edited on the other: kept, with a note',
    () {
      final theirs = base.copyWith(
        tasks: base.tasks.where((t) => t.id != 'c').toList(),
      );
      final mine = edit(
        base,
        'c',
        (t) => t.copyWith(title: 'C edited', updatedAt: at(5)),
      );
      final r = mergeProject(base: base, mine: mine, theirs: theirs, now: now);
      expect(r.project.taskById('c')!.title, 'C edited');
      expect(r.notes.single, contains('deleted on another computer'));

      final mine2 = base.copyWith(
        tasks: base.tasks.where((t) => t.id != 'b').toList(),
      );
      final theirs2 = edit(
        base,
        'b',
        (t) => t.copyWith(title: 'B there', updatedAt: at(6)),
      );
      final r2 = mergeProject(
        base: base,
        mine: mine2,
        theirs: theirs2,
        now: now,
      );
      expect(r2.project.taskById('b')!.title, 'B there');
      expect(r2.notes.single, contains('after you deleted it here'));
    },
  );

  test('both computers created a task: both kept, numbers made unique', () {
    final mine = base.copyWith(
      tasks: [
        ...base.tasks,
        task('new-here', number: 4, created: at(30)),
      ],
      nextNumber: 5,
    );
    final theirs = base.copyWith(
      tasks: [
        ...base.tasks,
        task('new-there', number: 4, created: at(20)),
      ],
      nextNumber: 5,
    );
    final p = mergeProject(
      base: base,
      mine: mine,
      theirs: theirs,
      now: now,
    ).project;
    expect(
      p.taskById('new-there')!.number,
      4,
      reason: 'older keeps the number',
    );
    expect(p.taskById('new-here')!.number, 5);
    expect(p.nextNumber, 6);
  });

  test('a project renamed on one side keeps task edits from the other', () {
    final mine = base.copyWith(name: 'Website', updatedAt: at(3));
    final theirs = edit(
      base,
      'a',
      (t) => t.copyWith(status: TaskStatus.done, updatedAt: at(4)),
    );
    final p = mergeProject(
      base: base,
      mine: mine,
      theirs: theirs,
      now: now,
    ).project;
    expect(p.name, 'Website');
    expect(p.taskById('a')!.status, TaskStatus.done);
  });
}
