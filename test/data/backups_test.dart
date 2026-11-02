import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/data/backups.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

void main() {
  late Directory root;
  late String folder;
  late String backupRoot;
  var now = t0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasklet_backups_');
    folder = p.join(root.path, 'data');
    backupRoot = p.join(root.path, 'backups');
    await Directory(folder).create();
    await WorkspaceStore.initialize(folder);
    now = t0;
  });

  tearDown(() => root.delete(recursive: true));

  WorkspaceStore store({int keep = 20}) => WorkspaceStore(
    folder,
    clock: () => now,
    backups: Backups(backupRoot, folder, keep: keep, clock: () => now),
  );

  test(
    'the version being replaced is kept, at most once per 10 minutes',
    () async {
      final s = store();
      await s.writeProject(
        project('p1', name: 'v1', key: 'WEB'),
      ); // nothing to back up yet
      expect(await s.projectBackups('p1'), isEmpty);

      now = now.add(const Duration(minutes: 1));
      await s.writeProject(project('p1', name: 'v2', key: 'WEB'));
      now = now.add(const Duration(minutes: 1));
      await s.writeProject(project('p1', name: 'v3', key: 'WEB')); // too soon
      final backups = await s.projectBackups('p1');
      expect(backups, hasLength(1));
      expect((await s.readBackup(backups.single))!.name, 'v1');

      now = now.add(const Duration(minutes: 10));
      await s.writeProject(project('p1', name: 'v4', key: 'WEB'));
      final names = [
        for (final b in await s.projectBackups('p1'))
          (await s.readBackup(b))!.name,
      ];
      expect(names, ['v3', 'v1'], reason: 'newest first');
    },
  );

  test(
    'a forced backup ignores the interval and old ones are pruned',
    () async {
      final s = store(keep: 3);
      await s.writeProject(project('p1', name: 'v0', key: 'WEB'));
      for (var i = 1; i <= 5; i++) {
        now = now.add(const Duration(seconds: 1));
        await s.writeProject(
          project('p1', name: 'v$i', key: 'WEB'),
          backupFirst: true,
        );
      }
      final names = [
        for (final b in await s.projectBackups('p1'))
          (await s.readBackup(b))!.name,
      ];
      expect(names, ['v4', 'v3', 'v2']);
    },
  );

  test(
    'backups live outside the data folder, one folder per workspace',
    () async {
      final s = store();
      await s.writeProject(project('p1', key: 'WEB'));
      now = now.add(const Duration(hours: 1));
      await s.writeProject(project('p1', key: 'WEB'));
      final backup = (await s.projectBackups('p1')).single;
      expect(p.isWithin(backupRoot, backup.path), isTrue);
      expect(p.isWithin(folder, backup.path), isFalse);
      final other = Backups(backupRoot, p.join(root.path, 'other'));
      expect(other.dir, isNot(Backups(backupRoot, folder).dir));
    },
  );
}
