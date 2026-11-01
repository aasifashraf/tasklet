import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

void main() {
  late Directory root;
  late String folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasklet_safety_');
    folder = root.path;
    await WorkspaceStore.initialize(folder);
  });

  tearDown(() => root.delete(recursive: true));

  String inFolder(String relative) => p.join(folder, relative);

  Future<void> writeRaw(String relative, Object? json) async {
    final file = File(inFolder(relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(json is String ? json : jsonEncode(json));
  }

  Future<Object?> readRaw(String relative) async =>
      jsonDecode(await File(inFolder(relative)).readAsString());

  WorkspaceStore store() => WorkspaceStore(folder, clock: () => t0);

  group('format version', () {
    test('a newer format opens read-only and refuses every write', () async {
      await writeRaw('tasklet-workspace.json', {
        'app': 'tasklet',
        'formatVersion': 2,
      });
      await writeRaw(
        'projects/p1.json',
        project('p1', name: 'Legacy', key: '').toJson(),
      );
      final s = store();
      final ws = await s.read();
      expect(ws.readOnly, isTrue);
      expect(ws.projects.single.key, 'LEG', reason: 'keys still resolve');
      expect(
        (await readRaw('projects/p1.json'))! as Map,
        containsPair('key', ''),
        reason: 'but nothing is written back',
      );
      await expectLater(
        s.writeProject(ws.projects.single),
        throwsA(isA<UnsafeWriteException>()),
      );
      expect(() => s.writeLabels([]), throwsA(isA<UnsafeWriteException>()));
      expect(() => s.writeViews([]), throwsA(isA<UnsafeWriteException>()));
    });

    test(
      'an unreadable marker (mid-sync) is read-only for that read',
      () async {
        await writeRaw('tasklet-workspace.json', '{"app": ');
        expect((await store().read()).readOnly, isTrue);
      },
    );

    test('a missing marker is writable (fresh or legacy folder)', () async {
      await File(inFolder('tasklet-workspace.json')).delete();
      expect((await store().read()).readOnly, isFalse);
    });
  });

  group('lenient lists', () {
    test(
      'a bad entry in labels.json is hidden, preserved, and the rest load',
      () async {
        final good = Label(id: 'l1', name: 'Bug', color: TaskletColor.red);
        final future = {'id': 'l2', 'color': 'red'}; // no name → hidden
        await writeRaw('labels.json', [good.toJson(), future]);
        final s = store();
        final ws = await s.read();
        expect(ws.labelsReadable, isTrue);
        expect(ws.labels.single.id, 'l1');
        expect(ws.hiddenEntryCount, 1);

        await s.writeLabels([good.copyWith(name: 'Bugs')]);
        final saved = (await readRaw('labels.json'))! as List<Object?>;
        expect((saved.first! as Map)['name'], 'Bugs');
        expect(saved.last, future);
      },
    );

    test('hidden tasks count toward the workspace total', () async {
      final json = project('p1', key: 'WEB').toJson();
      json['tasks'] = [
        {...task('t1').toJson(), 'status': 'canceled'},
      ];
      await writeRaw('projects/p1.json', json);
      expect((await store().read()).hiddenEntryCount, 1);
    });
  });

  group('conflict copies', () {
    test('an orphan copy is shown when the main file is missing; saving recreates the main file only', () async {
      final copy = project('p1', name: 'Website', key: 'WEB');
      await writeRaw(
        "projects/p1 (Ada's conflicted copy 2026-10-01).json",
        copy.toJson(),
      );
      final copyPath = inFolder(
        "projects/p1 (Ada's conflicted copy 2026-10-01).json",
      );
      final before = await File(copyPath).readAsString();

      final s = store();
      final ws = await s.read();
      expect(ws.projects.single.name, 'Website');
      expect(ws.conflicts.single.mainFileMissing, isTrue);

      await s.writeProject(ws.projects.single.copyWith(name: 'Edited'));
      expect(((await readRaw('projects/p1.json'))! as Map)['name'], 'Edited');
      expect(await File(copyPath).readAsString(), before);
      final again = await s.read();
      expect(again.conflicts.single.mainFileMissing, isFalse);
    });

    test('the newest orphan copy wins', () async {
      await writeRaw(
        'projects/p1-LAPTOP.json',
        project('p1', name: 'Old', created: at(0)).toJson(),
      );
      final newer = project(
        'p1',
        name: 'New',
      ).copyWith(updatedAt: at(60)).toJson();
      await writeRaw(
        'projects/p1.sync-conflict-20261001-101010-ABCDEFG.json',
        newer,
      );
      final ws = await store().read();
      expect(ws.projects.single.name, 'New');
      expect(ws.conflicts.length, 2);
    });

    test(
      'an orphan copy is not used when the main file is merely unreadable',
      () async {
        await writeRaw('projects/p1.json', '{"id": "p1"');
        await writeRaw(
          'projects/p1 2.json',
          project('p1', name: 'Copy').toJson(),
        );
        final ws = await store().read();
        expect(ws.projects, isEmpty);
        expect(ws.conflicts.single.mainFileMissing, isFalse);
      },
    );

    test('copies of labels.json and views.json are reported', () async {
      await writeRaw('labels (conflicted copy).json', <Object?>[]);
      await writeRaw('views-DESKTOP-1.json', <Object?>[]);
      await writeRaw('notes.json', <Object?>[]);
      final names = (await store().read()).conflicts.map((c) => c.projectName);
      expect(names, unorderedEquals(['Labels', 'Quick Filters']));
    });
  });

  group('project ids', () {
    test('Windows reserved device names are rejected', () {
      for (final id in ['con', 'NUL', 'Com1', 'lpt9', 'aux']) {
        expect(WorkspaceStore.isSafeProjectId(id), isFalse, reason: id);
      }
      for (final id in [
        'console',
        'nul1x',
        'a3f9c2d0-1b2c-4d5e-8f90-1234567890ab',
      ]) {
        expect(WorkspaceStore.isSafeProjectId(id), isTrue, reason: id);
      }
      expect(WorkspaceStore.isSafeProjectId('../x'), isFalse);
      expect(WorkspaceStore.isSafeProjectId(''), isFalse);
    });
  });

  group('deleteProject', () {
    test('sends the file and its conflict copies to the OS trash', () async {
      await writeRaw('projects/p1.json', project('p1', key: 'WEB').toJson());
      await writeRaw('projects/p1 2.json', project('p1', key: 'WEB').toJson());
      final s = store();
      final ws = await s.read();
      final trashed = <String>[];
      await s.deleteProject(
        ws.projects.single,
        moveToTrash: (path) async {
          trashed.add(p.basename(path));
          await File(path).delete();
          return true;
        },
      );
      expect(trashed, unorderedEquals(['p1.json', 'p1 2.json']));
      expect((await s.read()).projects, isEmpty);
    });

    test(
      'falls back to <folder>/.trash when the volume has no trash',
      () async {
        await writeRaw('projects/p1.json', project('p1', key: 'WEB').toJson());
        final s = store();
        final ws = await s.read();
        await s.deleteProject(
          ws.projects.single,
          moveToTrash: (_) async => false,
        );
        expect(await File(inFolder('projects/p1.json')).exists(), isFalse);
        final kept = await Directory(inFolder('.trash')).list().toList();
        expect(kept.single.path, endsWith('p1.json'));
        expect(
          (await s.read()).projects,
          isEmpty,
          reason: '.trash is never read',
        );
      },
    );

    test('a deleted project is never written again in this session', () async {
      await writeRaw('projects/p1.json', project('p1', key: 'WEB').toJson());
      final s = store();
      final pr = (await s.read()).projects.single;
      await s.deleteProject(pr, moveToTrash: (_) async => false);
      await expectLater(
        s.writeProject(pr),
        throwsA(isA<UnsafeWriteException>()),
      );
      expect(await File(inFolder('projects/p1.json')).exists(), isFalse);
    });

    test('the No Project bucket cannot be deleted', () async {
      final ws = await store().read();
      await expectLater(
        store().deleteProject(ws.noProject, moveToTrash: (_) async => true),
        throwsA(isA<UnsafeWriteException>()),
      );
    });
  });
}
