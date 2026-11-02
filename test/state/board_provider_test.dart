import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/sorting.dart';
import 'package:tasklet/state/boards.dart';
import 'package:tasklet/state/clock.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';

class _NoPrefs extends PrefsNotifier {
  @override
  Prefs build() => Prefs(const {});
}

class _Data extends Notifier<Workspace?> {
  _Data(this.initial);
  final Workspace initial;
  @override
  Workspace? build() => initial;
  void set(Workspace ws) => state = ws;
}

/// The board's shortcuts (patching after an edit, filtering the last result while typing) must show exactly what
/// a full recompute shows.
void main() {
  final today = LocalDate(2026, 10, 1);
  const board = AllTasksBoard();
  final titles = [
    'Deploy cache layer',
    'deploy docs',
    'Fix cache bug',
    'Write deploy notes',
    'Cache warmup',
    'Login page',
  ];

  test('typing, deleting and editing match a full recompute', () {
    final web = project(
      'web',
      key: 'WEB',
      tasks: [
        for (final (i, t) in titles.indexed)
          task('t$i', number: i + 1, title: t, sortOrder: i * 10.0),
      ],
    );
    final data = _Data(
      Workspace(
        folder: '/x',
        projects: [web],
        noProject: Project.noProject(t0),
        noProjectOnDisk: false,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWith(_NoPrefs.new),
        todayProvider.overrideWithValue(today),
        workspaceDataProvider.overrideWith((ref) => ref.watch(_dataProvider)),
        _dataProvider.overrideWith(() => data),
      ],
    );
    addTearDown(container.dispose);
    container.listen(boardProvider(board), (_, _) {});

    List<String> shown() => [
      for (final g in container.read(boardProvider(board))!.groups.values)
        for (final e in g) e.task.id,
    ];
    List<String> expected(String search) {
      final q = SearchQuery(search);
      return [
        for (final g in groupAndSort(
          container.read(workspaceDataProvider)!.activeTasks.where(q.matches),
          ViewDisplay(),
        ).values)
          for (final e in g) e.task.id,
      ];
    }

    void search(String text) {
      container.read(sessionSearchProvider.notifier).set(board.id, text);
      expect(shown(), expected(text), reason: '"$text"');
    }

    for (final text in ['d', 'de', 'dep', 'deploy', 'deploy c', 'deploy ca']) {
      search(text);
    }
    search('deploy'); // deleting widens again
    search('web-1');
    search('');

    // An edit while searching patches the board.
    search('cache');
    final ws = container.read(workspaceDataProvider)!;
    final p = ws.projects.single;
    data.set(
      ws.copyWith(
        projects: [
          p.copyWith(
            tasks: [
              for (final t in p.tasks)
                t.id == 't5' ? t.copyWith(title: 'Login cache') : t,
            ],
          ),
        ],
      ),
    );
    expect(shown(), expected('cache'));
    search('cache l');
  });
}

final _dataProvider = NotifierProvider<_Data, Workspace?>(
  () => throw UnimplementedError('overridden in the test'),
);
