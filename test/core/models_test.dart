import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

void main() {
  group('Task JSON', () {
    test('round-trips every field', () {
      final original = task(
        't1',
        number: 7,
        title: 'Ship it',
        description: 'line 1\nline 2',
        status: TaskStatus.done,
        priority: Priority.high,
        start: d('2026-10-02'),
        due: d('2026-10-09'),
        labels: ['l1', 'l2'],
        sortOrder: -1500.5,
        created: at(0),
        updated: at(10),
        completed: at(10),
      );
      final copy = Task.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>);
      expect(copy.toJson(), original.toJson());
      expect(copy.status, TaskStatus.done);
      expect(copy.dueDate, d('2026-10-09'));
    });

    test('writes status as snake_case and dates as YYYY-MM-DD', () {
      final json = task('t1', status: TaskStatus.inProgress, due: d('2026-01-05')).toJson();
      expect(json['status'], 'in_progress');
      expect(json['dueDate'], '2026-01-05');
      expect(json['startDate'], isNull);
    });

    test('preserves unknown fields from newer versions', () {
      final json = task('t1').toJson()
        ..['estimate'] = 3
        ..['future'] = {'nested': true};
      final out = Task.fromJson(json).toJson();
      expect(out['estimate'], 3);
      expect(out['future'], {'nested': true});
    });

    test('missing required fields or bad values throw FormatException', () {
      final good = task('t1').toJson();
      expect(() => Task.fromJson({...good}..remove('id')), throwsFormatException);
      expect(() => Task.fromJson({...good, 'status': 'archived'}), throwsFormatException);
      expect(() => Task.fromJson({...good, 'priority': 9}), throwsFormatException);
      expect(() => Task.fromJson({...good, 'dueDate': '2026-13-01'}), throwsFormatException);
      expect(() => Task.fromJson({...good, 'createdAt': 'yesterday'}), throwsFormatException);
    });

    test('copyWith can clear nullable fields', () {
      final t = task('t1', due: d('2026-10-09'), completed: at(1));
      final cleared = t.copyWith(dueDate: null, completedAt: null);
      expect(cleared.dueDate, isNull);
      expect(cleared.completedAt, isNull);
      expect(t.copyWith(title: 'x').dueDate, d('2026-10-09'));
    });
  });

  group('Project JSON', () {
    test('round-trips with tasks, labels and unknown fields', () {
      final p = project(
        'p1',
        name: 'Website',
        key: 'WEB',
        tasks: [task('t1', number: 1), task('t2', number: 2)],
        labels: [Label(id: 'l1', name: 'Bug', color: TaskletColor.red)],
      );
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>;
      json['team'] = 'none';
      final copy = Project.fromJson(json);
      expect(copy.tasks.length, 2);
      expect(copy.labels.single.name, 'Bug');
      expect(copy.toJson()['team'], 'none');
    });

    test('nextNumber never falls behind existing task numbers', () {
      final p = project('p1', tasks: [task('t1', number: 9)], nextNumber: 3);
      expect(p.nextNumber, 10);
    });

    test('legacy file without key reads with an empty key', () {
      final json = project('p1').toJson()..remove('key');
      expect(Project.fromJson(json).key, '');
    });

    test('display id is KEY-number', () {
      final p = project('p1', key: 'WEB');
      expect(p.displayIdOf(task('t1', number: 12)), 'WEB-12');
    });
  });

  group('BoardFilters', () {
    test('round-trips and counts active categories', () {
      final f = BoardFilters(
        status: {TaskStatus.todo},
        priorities: {Priority.urgent, Priority.none},
        labels: {noLabelFilterId},
        due: {DueFilter.week},
      );
      final copy = BoardFilters.fromJson(jsonDecode(jsonEncode(f.toJson())));
      expect(copy.status, {TaskStatus.todo});
      expect(copy.priorities, {Priority.urgent, Priority.none});
      expect(copy.due, {DueFilter.week});
      expect(copy.activeCategoryCount, 4);
      expect(BoardFilters.empty.isEmpty, isTrue);
    });

    test('drops unknown values instead of failing', () {
      final f = BoardFilters.fromJson({
        'status': ['todo', 'blocked'],
        'due': ['someday'],
        'extraCategory': [1],
      });
      expect(f.status, {TaskStatus.todo});
      expect(f.due, isEmpty);
      expect(f.toJson()['extraCategory'], [1]);
    });
  });

  group('ViewDisplay', () {
    test('withOrder applies the default direction', () {
      final v = ViewDisplay();
      expect(v.withOrder(SortOrder.updated).direction, SortDirection.desc);
      expect(v.withOrder(SortOrder.newest).direction, SortDirection.desc);
      expect(v.withOrder(SortOrder.priority).direction, SortDirection.asc);
      expect(v.withOrder(SortOrder.dueDate).direction, SortDirection.asc);
    });

    test('Today defaults: list layout without priority and start date', () {
      final t = ViewDisplay.todayDefaults;
      expect(t.layout, BoardLayout.list);
      expect(t.shows(DisplayProperty.priority), isFalse);
      expect(t.shows(DisplayProperty.startDate), isFalse);
      expect(t.shows(DisplayProperty.dueDate), isTrue);
    });

    test('round-trips', () {
      final v = ViewDisplay(order: SortOrder.dueDate, layout: BoardLayout.list, properties: {DisplayProperty.id});
      final copy = ViewDisplay.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
      expect(copy.sameAs(v), isTrue);
      expect(copy.sameAs(ViewDisplay()), isFalse);
    });
  });

  test('SavedView round-trips with null display', () {
    final v = SavedView(
      id: 'v1',
      name: 'Urgent',
      filters: BoardFilters(priorities: {Priority.urgent}),
      createdAt: t0,
      updatedAt: t0,
    );
    final copy = SavedView.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
    expect(copy.display, isNull);
    expect(copy.filters.priorities, {Priority.urgent});
  });

  test('label color rotation picks the least used color, never neutral', () {
    expect(TaskletColor.nextUnused([]), TaskletColor.blue);
    expect(TaskletColor.nextUnused([TaskletColor.blue, TaskletColor.purple]), TaskletColor.green);
    expect(TaskletColor.nextUnused(TaskletColor.rotation), TaskletColor.blue);
  });
}
