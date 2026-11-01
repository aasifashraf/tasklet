import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

void main() {
  final today = d('2026-10-15');
  final web = project('web', key: 'WEB');
  final app = project('app', key: 'APP');
  final none = Project.noProject(t0);

  bool matches(ProjectTask e, BoardFilters f) => matchesFilters(e, f, today);

  test('empty filters match everything', () {
    expect(matches(entry(task('t')), BoardFilters.empty), isTrue);
  });

  test('OR within a category, AND across categories', () {
    final urgentTodo = entry(task('a', priority: Priority.urgent));
    final highDone = entry(
      task('b', priority: Priority.high, status: TaskStatus.done),
    );
    final f = BoardFilters(
      status: {TaskStatus.todo},
      priorities: {Priority.urgent, Priority.high},
    );
    expect(matches(urgentTodo, f), isTrue);
    expect(matches(highDone, f), isFalse);
  });

  test('project filter by id, including No Project', () {
    final inWeb = entry(task('a'), web);
    final inNone = entry(task('b'), none);
    expect(matches(inWeb, BoardFilters(projects: {'web'})), isTrue);
    expect(matches(inNone, BoardFilters(projects: {'web'})), isFalse);
    expect(matches(inNone, BoardFilters(projects: {noProjectId})), isTrue);
  });

  test('label filter with No Label', () {
    final bug = entry(task('a', labels: ['bug']));
    final bare = entry(task('b'));
    expect(matches(bug, BoardFilters(labels: {'bug'})), isTrue);
    expect(matches(bare, BoardFilters(labels: {'bug'})), isFalse);
    expect(matches(bare, BoardFilters(labels: {noLabelFilterId})), isTrue);
    expect(
      matches(bug, BoardFilters(labels: {noLabelFilterId, 'bug'})),
      isTrue,
    );
  });

  group('due filter', () {
    bool due(Task t, DueFilter f) => matchesDue(t, {f}, today);

    test('overdue means past due and not done', () {
      expect(due(task('a', due: d('2026-10-14')), DueFilter.overdue), isTrue);
      expect(
        due(
          task('b', due: d('2026-10-14'), status: TaskStatus.done),
          DueFilter.overdue,
        ),
        isFalse,
      );
      expect(due(task('c', due: today), DueFilter.overdue), isFalse);
    });

    test('next 7 days is today through today+6 inclusive', () {
      expect(due(task('a', due: today), DueFilter.week), isTrue);
      expect(due(task('b', due: d('2026-10-21')), DueFilter.week), isTrue);
      expect(due(task('c', due: d('2026-10-22')), DueFilter.week), isFalse);
      expect(due(task('d', due: d('2026-10-14')), DueFilter.week), isFalse);
    });

    test('today and none', () {
      expect(due(task('a', due: today), DueFilter.today), isTrue);
      expect(due(task('b'), DueFilter.none), isTrue);
      expect(due(task('c', due: today), DueFilter.none), isFalse);
    });
  });

  group('search', () {
    final e = entry(
      task(
        'a',
        number: 12,
        title: 'Fix login button',
        description: 'Safari only',
      ),
      web,
    );

    test('every word must appear in id, title, or description', () {
      expect(matchesSearch(e, ''), isTrue);
      expect(matchesSearch(e, 'login'), isTrue);
      expect(matchesSearch(e, 'SAFARI fix'), isTrue);
      expect(matchesSearch(e, 'web-12'), isTrue);
      expect(matchesSearch(e, 'login chrome'), isFalse);
    });
  });

  group('toggleProjectFilter', () {
    test('No Project and real projects are mutually exclusive', () {
      expect(toggleProjectFilter({}, 'web'), {'web'});
      expect(toggleProjectFilter({'web'}, 'app'), {'web', 'app'});
      expect(toggleProjectFilter({'web', 'app'}, noProjectId), {noProjectId});
      expect(toggleProjectFilter({noProjectId}, 'web'), {'web'});
      expect(toggleProjectFilter({noProjectId}, noProjectId), <String>{});
      expect(toggleProjectFilter({'web'}, 'web'), <String>{});
    });
  });

  test('stale filter values are pruned', () {
    final f = BoardFilters(
      projects: {'web', 'gone'},
      labels: {'bug', 'deleted', noLabelFilterId},
    );
    final pruned = pruneStaleFilters(
      f,
      {'web', app.id, noProjectId},
      {'bug', noLabelFilterId},
    );
    expect(pruned.projects, {'web'});
    expect(pruned.labels, {'bug', noLabelFilterId});
    expect(
      identical(
        pruneStaleFilters(pruned, {'web'}, {'bug', noLabelFilterId}),
        pruned,
      ),
      isTrue,
    );
  });
}
