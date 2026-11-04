import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

void main() {
  final withSteps = task('t1', title: 'Release').copyWith(
    checklist: [
      ChecklistItem(id: 'a', text: 'Bump the version', done: true),
      ChecklistItem(id: 'b', text: 'Write release notes'),
    ],
  );

  test('round trip; absent when empty; unknown step fields kept', () {
    final json = withSteps.toJson();
    expect(json['checklist'], [
      {'id': 'a', 'text': 'Bump the version', 'done': true},
      {'id': 'b', 'text': 'Write release notes', 'done': false},
    ]);
    expect(Task.fromJson(json).checklist.map((i) => i.text), [
      'Bump the version',
      'Write release notes',
    ]);
    expect(task('t2').toJson().containsKey('checklist'), isFalse);

    final newer = {
      ...json,
      'checklist': [
        {'id': 'a', 'text': 'Step', 'done': false, 'assignee': 'x'},
      ],
    };
    expect(Task.fromJson(newer).toJson()['checklist'], newer['checklist']);
  });

  test('a checklist this version cannot read is kept exactly as it was', () {
    for (final odd in [
      'not a list',
      [
        {'id': 'a'}, // no text
      ],
      [
        {'id': 'a', 'text': 'one'},
        {'id': 'a', 'text': 'same id'},
      ],
      [
        {'id': 'a', 'text': 'x', 'done': 'yes'},
      ],
    ]) {
      final json = {...task('t1').toJson(), 'checklist': odd};
      final read = Task.fromJson(json);
      expect(read.checklist, isEmpty);
      expect(read.toJson()['checklist'], odd);
    }
  });

  test('search finds step text', () {
    final e = ProjectTask(project('p1'), withSteps);
    expect(SearchQuery('release notes').matches(e), isTrue);
    expect(SearchQuery('changelog').matches(e), isFalse);
  });
}
