import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/board_patch.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/sorting.dart';

import '../helpers.dart';

/// Patching a board after an edit must give exactly what a full group-and-sort gives.
void main() {
  final today = LocalDate(2026, 10, 1);

  Workspace workspace(List<Project> projects) => Workspace(
    folder: '/x',
    projects: projects,
    noProject: Project.noProject(t0),
    noProjectOnDisk: false,
  );

  Map<TaskStatus, List<String>> ids(Map<TaskStatus, List<ProjectTask>> g) => {
    for (final e in g.entries) e.key: [for (final t in e.value) t.task.id],
  };

  for (final order in SortOrder.values) {
    test('random edits patched == full recompute (${order.name})', () {
      final rnd = Random(order.index + 7);
      final display = ViewDisplay(order: order);
      Task randomTask(String id, int n) => task(
        id,
        number: n,
        title: 'task ${rnd.nextInt(5)}',
        status: TaskStatus.values[rnd.nextInt(4)],
        priority: Priority.values[rnd.nextInt(5)],
        sortOrder: rnd.nextInt(5) * 1000.0, // many ties on purpose
        due: rnd.nextBool() ? today.addDays(rnd.nextInt(10) - 5) : null,
        created: at(rnd.nextInt(50)),
        updated: at(50 + rnd.nextInt(50)),
        completed: at(rnd.nextInt(100)),
      );
      var ws = workspace([
        for (var p = 0; p < 4; p++)
          project(
            'p$p',
            key: 'P${'ABCD'[p]}',
            tasks: [for (var i = 0; i < 30; i++) randomTask('p$p-$i', i + 1)],
          ),
      ]);
      var nextId = 0;

      for (final (filters, search) in [
        (BoardFilters.empty, ''),
        (BoardFilters(priorities: {Priority.high, Priority.urgent}), 'task'),
      ]) {
        final query = SearchQuery(search);
        bool include(ProjectTask e) =>
            matchesFilters(e, filters, today) && query.matches(e);
        Map<TaskStatus, List<ProjectTask>> full(Workspace w) =>
            groupAndSort(w.activeTasks.where(include), display);
        var groups = full(ws);

        for (var round = 0; round < 150; round++) {
          final p = ws.projects[rnd.nextInt(ws.projects.length)];
          final tasks = [...p.tasks];
          switch (rnd.nextInt(4)) {
            case 0 when tasks.isNotEmpty:
              tasks.removeAt(rnd.nextInt(tasks.length)); // delete
            case 1:
              tasks.add(randomTask('new-${nextId++}', 100 + nextId)); // create
            default:
              if (tasks.isEmpty) continue;
              final i = rnd.nextInt(tasks.length); // edit (keeps the id)
              tasks[i] = randomTask(tasks[i].id, tasks[i].number);
          }
          final next = workspace([
            for (final q in ws.projects)
              q.id == p.id ? q.copyWith(tasks: tasks) : q,
          ]);
          final diff = diffTasks(ws, next)!;
          groups = patchGroups(
            groups,
            display,
            removed: diff.removed.values,
            added: diff.added.where(include),
          );
          expect(ids(groups), ids(full(next)), reason: 'round $round');
          ws = next;
        }
      }
    });
  }

  test('a project-level change needs a full recompute', () {
    final before = workspace([
      project('p', name: 'A', tasks: [task('t')]),
    ]);
    final renamed = workspace([before.projects.single.copyWith(name: 'B')]);
    expect(diffTasks(before, renamed), isNull);
    final added = workspace([...before.projects, project('q')]);
    expect(diffTasks(before, added), isNull);
  });

  test('too many changed tasks needs a full recompute', () {
    final before = workspace([
      project('p', tasks: [for (var i = 0; i < 300; i++) task('t$i')]),
    ]);
    final after = workspace([before.projects.single.copyWith(tasks: const [])]);
    expect(diffTasks(before, after), isNull);
  });
}
