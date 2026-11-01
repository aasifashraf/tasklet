import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/atomic_file.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

/// Edge cases found in the codebase audit: vanished folders, two windows sharing prefs, big folders, odd values.
void main() {
  late Directory root;
  late String folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasklet_robust_');
    folder = p.join(root.path, 'data');
    await Directory(folder).create();
    await WorkspaceStore.initialize(folder);
  });

  tearDown(() => root.delete(recursive: true));

  group('WorkspaceStore', () {
    test(
      'a save after the folder vanished fails and never recreates it',
      () async {
        final store = WorkspaceStore(folder, clock: () => t0);
        await store.read();
        await Directory(folder).delete(recursive: true);
        await expectLater(
          store.writeProject(project('p1', tasks: [task('t1')])),
          throwsA(isA<WorkspaceFolderMissing>()),
        );
        expect(await Directory(folder).exists(), isFalse);
      },
    );

    test('an unchanged folder returns the same workspace; a changed file is re-read', () async {
      final store = WorkspaceStore(folder, clock: () => t0);
      await store.writeProject(project('p1', name: 'One', key: 'ONE'));
      final first = await store.read();
      expect(identical(await store.read(), first), isTrue);

      await store.writeProject(
        project('p1', name: 'Renamed', key: 'ONE', tasks: [task('t1')]),
      );
      final second = await store.read();
      expect(identical(second, first), isFalse);
      expect(second.projects.single.name, 'Renamed');
      expect(identical(await store.read(reparse: true), second), isFalse);
    });

    test(
      'large projects are read and saved off the UI isolate intact',
      () async {
        final store = WorkspaceStore(folder, clock: () => t0);
        final big = project(
          'big',
          key: 'BIG',
          tasks: [
            for (var i = 1; i <= 3000; i++)
              task(
                't$i',
                number: i,
                title: 'Task $i',
                description: 'x' * 100,
                labels: const ['l1'],
              ),
          ],
        );
        await store.writeProject(big); // > 2000 tasks: encoded on an isolate
        expect(
          await File(store.projectPath('big')).length(),
          greaterThan(256 * 1024),
        );

        final ws = await WorkspaceStore(
          folder,
          clock: () => t0,
        ).read(); // parsed on an isolate
        final read = ws.projectById('big')!;
        expect(read.tasks, hasLength(3000));
        expect(read.tasks.last.title, 'Task 3000');
        expect(ws.labelUsage['l1'], 3000);
      },
    );

    test('a non-finite sortOrder reads as 0 and can be saved again', () async {
      await File(p.join(folder, 'projects', 'p1.json')).writeAsString(
        '{"id":"p1","name":"P","key":"PPP","color":"blue","createdAt":"2026-10-01T09:00:00.000Z",'
        '"updatedAt":"2026-10-01T09:00:00.000Z","tasks":[{"id":"t1","number":1,"title":"T","status":"todo",'
        '"priority":0,"sortOrder":1e999,"createdAt":"2026-10-01T09:00:00.000Z"}]}',
      );
      final store = WorkspaceStore(folder, clock: () => t0);
      final ws = await store.read();
      final p1 = ws.projectById('p1')!;
      expect(p1.tasks.single.sortOrder, 0);
      await store.writeProject(p1);
    });
  });

  group('atomic writes', () {
    test('a failed temp write leaves no temp file behind', () async {
      final target = p.join(root.path, 'missing-dir', 'x.json');
      await expectLater(
        writeFileAtomic(target, '{}'),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        root.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    });
  });

  group('PrefsStore shared by two windows', () {
    test(
      'each window saves only its own key, so neither undoes the other',
      () async {
        final path = p.join(root.path, 'settings.json');
        final main = await PrefsStore.open(path);
        final settings = await PrefsStore.open(path);
        await main.set('sidebarWidth', 240.0);
        await settings.set(
          'theme',
          'dark',
        ); // settings never saw sidebarWidth in memory
        await main.set('userName', 'Ada'); // main never saw theme in memory
        final onDisk = jsonDecode(await File(path).readAsString());
        expect(onDisk, {
          'sidebarWidth': 240.0,
          'theme': 'dark',
          'userName': 'Ada',
        });
        await main.dispose();
        await settings.dispose();
      },
    );

    test('a corrupt file is kept as .corrupt before it is replaced', () async {
      final path = p.join(root.path, 'settings.json');
      await File(path).writeAsString('{oops');
      final prefs = await PrefsStore.open(path);
      expect(await File('$path.corrupt').readAsString(), '{oops');
      await prefs.set('theme', 'light');
      expect(jsonDecode(await File(path).readAsString()), {'theme': 'light'});
      await prefs.dispose();
    });
  });

  group('lookups', () {
    test(
      'labelById prefers the workspace label, then the first project with it',
      () {
        final ws1 = Label(id: 'a', name: 'Workspace', color: TaskletColor.red);
        final pr1 = Label(id: 'a', name: 'Project', color: TaskletColor.red);
        final pr2 = Label(id: 'b', name: 'First', color: TaskletColor.red);
        final pr3 = Label(id: 'b', name: 'Second', color: TaskletColor.red);
        final ws = Workspace(
          folder: folder,
          projects: [
            project('p1', labels: [pr1, pr2]),
            project('p2', labels: [pr3]),
          ],
          noProject: Project.noProject(t0),
          noProjectOnDisk: false,
          labels: [ws1],
        );
        expect(ws.labelById('a')!.name, 'Workspace');
        expect(ws.labelById('b')!.name, 'First');
        expect(ws.labelById('zzz'), isNull);
      },
    );

    test('a parsed search matches like the one-off helper', () {
      final e = entry(
        task('t1', number: 12, title: 'Fix Login', description: 'Safari only'),
      );
      for (final q in [
        '',
        'web-12',
        'fix safari',
        'LOGIN',
        'fix chrome',
        '  login   fix ',
      ]) {
        expect(SearchQuery(q).matches(e), matchesSearch(e, q), reason: q);
      }
      expect(SearchQuery('fix safari').matches(e), isTrue);
      expect(SearchQuery('fix chrome').matches(e), isFalse);
    });
  });
}
