import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/sorting.dart';

import '../helpers.dart';

List<String> sortIds(List<Task> tasks, SortOrder order, SortDirection dir, {TaskStatus? status}) {
  final compare = comparatorFor(order, dir, status: status);
  return ([...tasks]..sort(compare)).map((t) => t.id).toList();
}

void main() {
  group('manual', () {
    test('sortOrder ascending, ties newest-created first', () {
      final tasks = [task('a', sortOrder: 10), task('b', sortOrder: -5), task('c', sortOrder: 10, created: at(5))];
      expect(sortIds(tasks, SortOrder.manual, SortDirection.asc), ['b', 'c', 'a']);
    });

    test('Done column shows most recently completed first', () {
      final tasks = [
        task('old', status: TaskStatus.done, completed: at(1), sortOrder: -100),
        task('new', status: TaskStatus.done, completed: at(9)),
        task('noCompleted', status: TaskStatus.done, updated: at(5)),
      ];
      expect(sortIds(tasks, SortOrder.manual, SortDirection.asc, status: TaskStatus.done), [
        'new',
        'noCompleted',
        'old',
      ]);
    });

    test('Done uses the user-picked order when not manual', () {
      final tasks = [
        task('low', status: TaskStatus.done, priority: Priority.low, completed: at(9)),
        task('urgent', status: TaskStatus.done, priority: Priority.urgent, completed: at(1)),
      ];
      expect(sortIds(tasks, SortOrder.priority, SortDirection.asc, status: TaskStatus.done), ['urgent', 'low']);
    });
  });

  group('priority', () {
    final tasks = [
      task('none', priority: Priority.none),
      task('low', priority: Priority.low),
      task('urgent', priority: Priority.urgent),
      task('high', priority: Priority.high),
      task('medium', priority: Priority.medium),
    ];

    test('ascending: urgent first, none last', () {
      expect(sortIds(tasks, SortOrder.priority, SortDirection.asc), ['urgent', 'high', 'medium', 'low', 'none']);
    });

    test('descending: low first, none still last', () {
      expect(sortIds(tasks, SortOrder.priority, SortDirection.desc), ['low', 'medium', 'high', 'urgent', 'none']);
    });

    test('ties break by sortOrder', () {
      final tied = [task('b', priority: Priority.high, sortOrder: 2), task('a', priority: Priority.high, sortOrder: 1)];
      expect(sortIds(tied, SortOrder.priority, SortDirection.asc), ['a', 'b']);
    });
  });

  group('due date', () {
    final tasks = [
      task('undated'),
      task('late', due: d('2026-10-20')),
      task('startOnly', start: d('2026-10-10')),
      task('soon', due: d('2026-10-05')),
    ];

    test('ascending uses start date as fallback, undated last', () {
      expect(sortIds(tasks, SortOrder.dueDate, SortDirection.asc), ['soon', 'startOnly', 'late', 'undated']);
    });

    test('descending keeps undated at the bottom', () {
      expect(sortIds(tasks, SortOrder.dueDate, SortDirection.desc), ['late', 'startOnly', 'soon', 'undated']);
    });

    test('same date breaks by priority rank then sortOrder', () {
      final same = [
        task('none', due: d('2026-10-05')),
        task('urgent', due: d('2026-10-05'), priority: Priority.urgent),
        task('high2', due: d('2026-10-05'), priority: Priority.high, sortOrder: 2),
        task('high1', due: d('2026-10-05'), priority: Priority.high, sortOrder: 1),
      ];
      expect(sortIds(same, SortOrder.dueDate, SortDirection.asc), ['urgent', 'high1', 'high2', 'none']);
    });
  });

  test('updated and newest apply direction directly', () {
    final tasks = [task('a', created: at(1), updated: at(9)), task('b', created: at(5), updated: at(6))];
    expect(sortIds(tasks, SortOrder.updated, SortDirection.desc), ['a', 'b']);
    expect(sortIds(tasks, SortOrder.newest, SortDirection.desc), ['b', 'a']);
    expect(sortIds(tasks, SortOrder.newest, SortDirection.asc), ['a', 'b']);
  });

  test('every comparator is deterministic for otherwise identical tasks', () {
    final tasks = [task('c'), task('a'), task('b')];
    for (final order in SortOrder.values) {
      for (final dir in SortDirection.values) {
        expect(sortIds(tasks, order, dir), sortIds(tasks.reversed.toList(), order, dir), reason: '$order $dir');
        final compare = comparatorFor(order, dir);
        expect(compare(tasks[0], tasks[1]), isNot(0));
      }
    }
  });

  test('groupAndSort groups by status in workflow order', () {
    final groups = groupAndSort([
      entry(task('d', status: TaskStatus.done, completed: at(1))),
      entry(task('b', status: TaskStatus.backlog)),
      entry(task('i', status: TaskStatus.inProgress)),
    ], ViewDisplay());
    expect(groups.keys, TaskStatus.values);
    expect(groups[TaskStatus.todo], isEmpty);
    expect(groups[TaskStatus.done]!.single.task.id, 'd');
  });

  test('manual reordering only in non-Done columns under Manual order', () {
    expect(isManuallyOrdered(SortOrder.manual, TaskStatus.todo), isTrue);
    expect(isManuallyOrdered(SortOrder.manual, TaskStatus.done), isFalse);
    expect(isManuallyOrdered(SortOrder.priority, TaskStatus.todo), isFalse);
  });
}
