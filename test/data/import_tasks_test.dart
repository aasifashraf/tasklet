import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/csv.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';

/// Import Tasks from CSV on a real folder (D17).
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('tasklet_import_');
    await WorkspaceStore.initialize(dir.path);
    final store = WorkspaceStore(dir.path);
    await store.read();
    await store.writeLabels([
      Label(id: 'bug', name: 'bug', color: TaskletColor.red),
    ]);
    await store.writeProject(project('web', name: 'Website', key: 'WEB'));
    await store.queue.drain();
    final prefs = await PrefsStore.open(p.join(dir.path, 'prefs.json'));
    await prefs.set(PrefKeys.dataFolder, dir.path);
    container = ProviderContainer(
      overrides: [prefsStoreProvider.overrideWithValue(prefs)],
    );
    container.read(workspaceProvider);
    for (var i = 0; i < 100; i++) {
      if (container.read(workspaceDataProvider) != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  test(
    'rows go to their project, labels match or are created, order kept',
    () async {
      final tasks = importTasks(
        'Title,Project,Labels,Status\n'
        'First,website,bug,Done\n'
        'Second,Website,"bug, docs",\n'
        'Loose,Somewhere else,,\n',
      )!;
      final count = await container
          .read(workspaceProvider.notifier)
          .importTasks(tasks);
      await container.read(workspaceProvider.notifier).flushSaves();
      expect(count, 3);

      final ws = container.read(workspaceDataProvider)!;
      final web = ws.projectById('web')!;
      final docs = ws.labels.firstWhere((l) => l.name == 'docs');
      final byTitle = {for (final t in web.tasks) t.title: t};
      expect(byTitle.keys.toSet(), {'First', 'Second'});
      expect(byTitle['First']!.status, TaskStatus.done);
      expect(byTitle['First']!.completedAt, isNotNull);
      expect(byTitle['Second']!.labelIds, ['bug', docs.id]);
      expect(ws.noProject.tasks.single.title, 'Loose');
      // In Todo, the file's first row stays above the later ones.
      final todo = [
        for (final t in web.tasks)
          if (t.status == TaskStatus.todo) t,
      ];
      expect(todo.single.title, 'Second');

      final onDisk = WorkspaceStore(dir.path);
      final reread = await onDisk.read();
      expect(reread.projectById('web')!.tasks.length, 2);
      expect(reread.labels.map((l) => l.name), containsAll(['bug', 'docs']));
    },
  );
}
