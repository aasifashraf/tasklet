import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/workspace_info.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/prefs.dart';

/// Workspaces are folders; their identity is in the marker file (docs/DECISIONS.md D15).
void main() {
  group('WorkspaceInfo', () {
    test('a marker from before workspaces is named after its folder', () {
      final info = WorkspaceInfo.fromMarker({
        'app': 'tasklet',
        'formatVersion': 1,
      }, 'Work');
      expect(info, const WorkspaceInfo(name: 'Work'));
      expect(info.icon, WorkspaceInfo.defaultIcon);
      expect(WorkspaceInfo.fromMarker(null, 'Work').name, 'Work');
      expect(WorkspaceInfo.fromMarker({'name': '  '}, 'Work').name, 'Work');
    });

    test(
      'reads name, icon (null = plain cube) and color; bad values fall back',
      () {
        final info = WorkspaceInfo.fromMarker({
          'name': ' Acme ',
          'icon': null,
          'color': 'teal',
        }, 'x');
        expect(info.name, 'Acme');
        expect(info.icon, isNull);
        expect(info.color, TaskletColor.teal);
        expect(
          WorkspaceInfo.fromMarker({'name': 3, 'color': 'ultraviolet'}, 'x'),
          const WorkspaceInfo(name: 'x'),
        );
      },
    );

    test('applyTo replaces only changed fields and keeps everything else', () {
      const before = WorkspaceInfo(name: 'Acme', icon: 'rocket');
      final marker = {
        'app': 'tasklet',
        'formatVersion': 1,
        'name': 'Acme',
        'icon': 'rocket',
        'color': 'ultraviolet', // a newer version's color, shown as blue here
        'future': {'x': 1},
      };
      final renamed = before
          .copyWith(name: 'Acme Corp')
          .applyTo(marker, before);
      expect(renamed['name'], 'Acme Corp');
      expect(renamed['color'], 'ultraviolet');
      expect(renamed['future'], {'x': 1});
      final cube = before.copyWith(clearIcon: true).applyTo(marker, before);
      expect(cube.containsKey('icon'), isTrue);
      expect(cube['icon'], isNull);
    });

    test('folderName takes the last path part', () {
      expect(folderName(r'D:\Work\Acme'), 'Acme');
      expect(folderName('/Users/me/Dropbox/OSS/'), 'OSS');
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tasklet_org_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Map<String, Object?> marker() => jsonDecode(
      File(p.join(dir.path, WorkspaceStore.markerFileName)).readAsStringSync(),
    ) as Map<String, Object?>;

    test('a new workspace gets its identity in the marker', () async {
      const acme = WorkspaceInfo(
        name: 'Acme',
        icon: 'briefcase',
        color: TaskletColor.indigo,
      );
      await WorkspaceStore.initialize(dir.path, info: acme);
      expect(marker()['formatVersion'], WorkspaceStore.formatVersion);
      expect((await WorkspaceStore(dir.path).read()).info, acme);

      // An existing marker is never replaced by initialize.
      await WorkspaceStore.initialize(
        dir.path,
        info: const WorkspaceInfo(name: 'Other'),
      );
      expect(marker()['name'], 'Acme');
    });

    test('renaming the open workspace keeps unknown marker fields and shows on the next read', () async {
      await WorkspaceStore.initialize(dir.path);
      final file = File(p.join(dir.path, WorkspaceStore.markerFileName));
      file.writeAsStringSync(
        jsonEncode({...marker(), 'future': true, 'color': 'ultraviolet'}),
      );
      final store = WorkspaceStore(dir.path);
      final before = await store.read();
      expect(before.info.name, p.basename(dir.path));

      final renamed = before.info.copyWith(name: 'Freelance');
      await store.writeWorkspaceInfo(renamed);
      await store.queue.drain();
      expect(marker()['name'], 'Freelance');
      expect(marker()['future'], isTrue);
      expect(marker()['color'], 'ultraviolet');
      expect(store.isOwnWrite(file.path), isTrue);
      final after = await store.read();
      expect(after.info.name, 'Freelance');
      expect(identical(after, before), isFalse);
    });

    test('a workspace saved by a newer version is not written', () async {
      await WorkspaceStore.initialize(dir.path);
      File(
        p.join(dir.path, WorkspaceStore.markerFileName),
      ).writeAsStringSync(jsonEncode({'app': 'tasklet', 'formatVersion': 99}));
      final info = WorkspaceInfo(name: p.basename(dir.path));
      await expectLater(
        WorkspaceStore.writeWorkspaceInfoAt(
          dir.path,
          info.copyWith(name: 'New'),
          before: info,
        ),
        throwsA(isA<UnsafeWriteException>()),
      );
      expect(marker()['formatVersion'], 99);
      expect(marker().containsKey('name'), isFalse);
    });
  });

  group('prefs', () {
    test('the list 1.1.0 kept under "organizations" is still read', () {
      final legacy = Prefs({
        PrefKeys.legacyWorkspaces: [
          {'folder': '/acme', 'name': 'Acme', 'color': 'teal'},
        ],
      }).workspaces;
      expect(legacy.single.info.name, 'Acme');
      expect(legacy.single.info.color, TaskletColor.teal);
      // Once written under the new key, that one wins.
      final both = Prefs({
        PrefKeys.workspaces: [
          {'folder': '/new', 'name': 'New'},
        ],
        PrefKeys.legacyWorkspaces: [
          {'folder': '/acme', 'name': 'Acme'},
        ],
      }).workspaces;
      expect([for (final w in both) w.info.name], ['New']);
    });

    test('a settings file from before workspaces lists its folder', () {
      final workspaces = Prefs({PrefKeys.dataFolder: r'D:\Tasks\Tasklet'})
          .workspaces;
      expect(workspaces, hasLength(1));
      expect(workspaces.single.folder, r'D:\Tasks\Tasklet');
      expect(workspaces.single.info.name, 'Tasklet');
    });

    test(
      'the list round-trips, keeps its order and lists each folder once',
      () {
        final stored = encodeWorkspaces([
          (
            folder: '/b',
            info: const WorkspaceInfo(name: 'B', color: TaskletColor.pink),
          ),
          (folder: '/a', info: const WorkspaceInfo(name: 'A', icon: null)),
        ]);
        final workspaces = Prefs({
          PrefKeys.workspaces: [
            ...jsonDecode(jsonEncode(stored)) as List<Object?>,
            {'folder': '/b', 'name': 'B again'},
            'junk',
            {'name': 'no folder'},
          ],
          PrefKeys.dataFolder: '/a',
        }).workspaces;
        expect([for (final o in workspaces) o.info.name], ['B', 'A']);
        expect(workspaces.first.info.color, TaskletColor.pink);
        expect(workspaces.last.info.icon, isNull);
      },
    );
  });
}
