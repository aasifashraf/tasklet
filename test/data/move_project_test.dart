import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/workspace_info.dart';
import 'package:tasklet/core/workspace_ops.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';

/// Moving a project to another workspace (docs/DECISIONS.md D15).
void main() {
  group('projectForTransfer', () {
    final bug = Label(id: 'bug', name: 'bug', color: TaskletColor.red);
    final docs = Label(id: 'docs', name: 'docs', color: TaskletColor.blue);
    final own = Label(id: 'own', name: 'own', color: TaskletColor.green);
    final moving = project(
      'p',
      name: 'Billing API',
      key: 'BIL',
      labels: [own],
      tasks: [
        task('t1', number: 7, labels: ['bug', 'own']),
        task('t2', number: 9),
      ],
    );

    test(
      'brings the workspace labels its tasks use and keeps task numbers',
      () {
        final moved = projectForTransfer(
          moving,
          workspaceLabels: [bug, docs],
          targetProjects: const [],
          now: t0,
        );
        expect([for (final l in moved.labels) l.id], ['own', 'bug']);
        expect([for (final t in moved.tasks) t.number], [7, 9]);
        expect(moved.key, 'BIL');
        expect(moved.nextNumber, moving.nextNumber);
      },
    );

    test('a key already used there is replaced; it goes last in the list', () {
      final there = [
        project('a', key: 'BIL').copyWith(sortOrder: 5000),
        project('b', key: 'OPS').copyWith(sortOrder: 9000),
      ];
      final moved = projectForTransfer(
        moving,
        workspaceLabels: const [],
        targetProjects: there,
        now: t0,
      );
      expect(moved.key, isNot('BIL'));
      expect(moved.key, isNot('OPS'));
      expect(moved.sortOrder, greaterThan(9000));
    });
  });

  group('moving between folders', () {
    late Directory root;
    late String work, oss;
    late ProviderContainer container;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('tasklet_move_');
      work = p.join(root.path, 'Work');
      oss = p.join(root.path, 'OSS');
      for (final (folder, name) in [(work, 'Acme'), (oss, 'Open Source')]) {
        Directory(folder).createSync();
        await WorkspaceStore.initialize(
          folder,
          info: WorkspaceInfo(name: name),
        );
      }
      final store = WorkspaceStore(work);
      await store.read();
      await store.writeLabels([
        Label(id: 'bug', name: 'bug', color: TaskletColor.red),
      ]);
      await store.writeProject(
        project(
          'billing',
          name: 'Billing API',
          key: 'BIL',
          tasks: [
            task('t1', number: 3, labels: ['bug']),
          ],
        ),
      );
      await store.queue.drain();
      final prefs = await PrefsStore.open(p.join(root.path, 'prefs.json'));
      await prefs.set(PrefKeys.dataFolder, work);
      container = ProviderContainer(
        overrides: [
          prefsStoreProvider.overrideWithValue(prefs),
          trashProvider.overrideWithValue((_) async => false),
        ],
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
      root.deleteSync(recursive: true);
    });

    test('writes it there, then removes it here', () async {
      final controller = container.read(workspaceProvider.notifier);
      final error = await controller.moveProjectToWorkspace('billing', oss);
      expect(error, isNull);

      expect(container.read(workspaceDataProvider)!.projects, isEmpty);
      expect(
        File(p.join(work, 'projects', 'billing.json')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(work, '.trash'))
            .listSync()
            .map((f) => p.basename(f.path)),
        [endsWith('billing.json')],
        reason: 'kept recoverable',
      );

      final there = await WorkspaceStore(oss).read();
      final moved = there.projects.single;
      expect(moved.name, 'Billing API');
      expect(moved.tasks.single.number, 3);
      expect(moved.labels.single.name, 'bug');
      expect(
        there.labels,
        isEmpty,
        reason: "the other folder's labels.json is untouched",
      );
    });

    test(
      'a folder saved by a newer version refuses it; nothing changes here',
      () async {
        File(p.join(oss, WorkspaceStore.markerFileName)).writeAsStringSync(
          jsonEncode({'app': 'tasklet', 'formatVersion': 99}),
        );
        final controller = container.read(workspaceProvider.notifier);
        final error = await controller.moveProjectToWorkspace('billing', oss);
        expect(error, contains('newer version'));
        expect(container.read(workspaceDataProvider)!.projects, hasLength(1));
        expect(
          File(p.join(work, 'projects', 'billing.json')).existsSync(),
          isTrue,
        );
        expect(Directory(p.join(oss, 'projects')).listSync(), isEmpty);
      },
    );

    test('a missing folder is reported', () async {
      final controller = container.read(workspaceProvider.notifier);
      final error = await controller.moveProjectToWorkspace(
        'billing',
        p.join(root.path, 'gone'),
      );
      expect(error, "Can't find that workspace's folder.");
      expect(container.read(workspaceDataProvider)!.projects, hasLength(1));
    });
  });
}
