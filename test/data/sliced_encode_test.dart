import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/atomic_file.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

/// Big project files are encoded a slice of tasks at a time; the bytes must be exactly what encodeJson writes,
/// so files don't change on disk (or churn in the sync service) because of how they were saved.
void main() {
  Project tricky(int n) => Project.fromJson({
    ...project(
      'p1',
      name: 'Ünïcode "quotes" ✓',
      key: 'UNI',
      nextNumber: n + 1,
      labels: [Label(id: 'l1', name: 'bug', color: TaskletColor.red)],
      tasks: [
        for (var i = 0; i < n; i++)
          task(
            't$i',
            number: i + 1,
            title: i.isEven ? 'Title $i 😀' : 'Line\nbreak "and" \\ slash',
            description: 'First line\n\n  indented\ttab',
            labels: i % 3 == 0 ? ['l1'] : const [],
          ),
      ],
    ).toJson(),
    'fromNewerVersion': {
      'nested': [1, 2, 3],
    },
    'tasks': [
      for (var i = 0; i < n; i++)
        {
          ...task('t$i', number: i + 1, title: 'T $i').toJson(),
          'unknownField': i,
        },
      {'id': 'opaque', 'whatever': true}, // an entry this version can't read
    ],
  });

  Future<String> sliced(Project project, {int slice = 3}) async => utf8.decode([
    ...(await encodeJsonInSlices(
      project.copyWith(tasks: const []).toJson(),
      'tasks',
      [...project.tasks, ...project.opaqueTasks],
      (Object? t) => t is Task ? t.toJson() : t,
      slice: slice,
    )).expand((part) => part),
  ]);

  for (final n in [0, 1, 2, 3, 4, 7, 50]) {
    test('$n tasks: same bytes as encodeJson', () async {
      final project = tricky(n);
      expect(await sliced(project), encodeJson(project.toJson()));
      expect(await sliced(project, slice: 250), encodeJson(project.toJson()));
    });
  }

  test(
    'a saved big project reads back the same and matches encodeJson',
    () async {
      final dir = Directory.systemTemp.createTempSync('tasklet_slices_');
      addTearDown(() => dir.deleteSync(recursive: true));
      await WorkspaceStore.initialize(dir.path);
      final store = WorkspaceStore(dir.path);
      await store.read();
      final big = tricky(2100); // above the slicing threshold
      await store.writeProject(big);
      await store.queue.drain();
      final file = File(p.join(dir.path, 'projects', 'p1.json'));
      expect(file.readAsStringSync(), encodeJson(big.toJson()));
      final read = (await store.read()).projects.single;
      expect(read.tasks.length, 2100);
      expect(read.opaqueTasks.length, 1);
    },
  );
}
