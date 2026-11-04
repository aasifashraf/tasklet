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
    test('matchesText: every word, any order, ignoring case', () {
      final q = SearchQuery('proj web');
      expect(q.matchesText('Website Project'), isTrue);
      expect(q.matchesText('Website'), isFalse);
      expect(SearchQuery('').matchesText('anything'), isTrue);
    });

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

    test('any part of the id matches, the same as searching the id text', () {
      // web's key is WEB: "WEB-12".
      for (final (query, expected) in [
        ('we', true),
        ('Web', true),
        ('b-1', true),
        ('-12', true),
        ('12', true),
        ('1', true),
        ('13', false),
        ('web-13', false),
        ('eb12', false),
        ('-', true),
      ]) {
        expect(
          matchesSearch(e, query),
          'web-12 fix login button\nsafari only'.contains(query.toLowerCase()),
          reason: query,
        );
        expect(matchesSearch(e, query), expected, reason: query);
      }
    });

    test('a narrower query matches only tasks the previous one matched', () {
      bool narrows(String next, String previous) =>
          SearchQuery(next).narrows(SearchQuery(previous));
      expect(narrows('dep', ''), isTrue);
      expect(narrows('deploy', 'dep'), isTrue);
      expect(narrows('deploy cache', 'deploy'), isTrue);
      expect(narrows('cache deploy', 'deploy ca'), isTrue);
      expect(narrows('web-12', 'b-1'), isTrue);
      expect(narrows('dep', 'deploy'), isFalse);
      expect(narrows('', 'dep'), isFalse);
      expect(narrows('deploy', 'deploy cache'), isFalse);

      // Whatever narrows, the matches really are a subset.
      final tasks = [
        for (final (i, t) in [
          'Fix login',
          'Deploy cache',
          'cache deploy fix',
          'web',
        ].indexed)
          entry(task('t$i', number: i + 1, title: t), web),
      ];
      for (final (next, previous) in [
        ('deploy cache', 'dep'),
        ('fix', ''),
        ('web-2', 'web'),
      ]) {
        final n = SearchQuery(next), p = SearchQuery(previous);
        expect(n.narrows(p), isTrue);
        expect(tasks.where(n.matches).every(p.matches), isTrue, reason: next);
      }
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
