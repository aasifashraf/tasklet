import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/organization.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/prefs.dart';

/// Organizations are folders; their identity is in the marker file (docs/DECISIONS.md D15).
void main() {
  group('OrgInfo', () {
    test('a marker from before organizations is named after its folder', () {
      final info = OrgInfo.fromMarker({
        'app': 'tasklet',
        'formatVersion': 1,
      }, 'Work');
      expect(info, const OrgInfo(name: 'Work'));
      expect(info.icon, OrgInfo.defaultIcon);
      expect(OrgInfo.fromMarker(null, 'Work').name, 'Work');
      expect(OrgInfo.fromMarker({'name': '  '}, 'Work').name, 'Work');
    });

    test(
      'reads name, icon (null = plain cube) and color; bad values fall back',
      () {
        final info = OrgInfo.fromMarker({
          'name': ' Acme ',
          'icon': null,
          'color': 'teal',
        }, 'x');
        expect(info.name, 'Acme');
        expect(info.icon, isNull);
        expect(info.color, TaskletColor.teal);
        expect(
          OrgInfo.fromMarker({'name': 3, 'color': 'ultraviolet'}, 'x'),
          const OrgInfo(name: 'x'),
        );
      },
    );

    test('applyTo replaces only changed fields and keeps everything else', () {
      const before = OrgInfo(name: 'Acme', icon: 'rocket');
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

    test('a new organization gets its identity in the marker', () async {
      const acme = OrgInfo(
        name: 'Acme',
        icon: 'briefcase',
        color: TaskletColor.indigo,
      );
      await WorkspaceStore.initialize(dir.path, organization: acme);
      expect(marker()['formatVersion'], WorkspaceStore.formatVersion);
      expect((await WorkspaceStore(dir.path).read()).organization, acme);

      // An existing marker is never replaced by initialize.
      await WorkspaceStore.initialize(
        dir.path,
        organization: const OrgInfo(name: 'Other'),
      );
      expect(marker()['name'], 'Acme');
    });

    test('renaming the open organization keeps unknown marker fields and shows on the next read', () async {
      await WorkspaceStore.initialize(dir.path);
      final file = File(p.join(dir.path, WorkspaceStore.markerFileName));
      file.writeAsStringSync(
        jsonEncode({...marker(), 'future': true, 'color': 'ultraviolet'}),
      );
      final store = WorkspaceStore(dir.path);
      final before = await store.read();
      expect(before.organization.name, p.basename(dir.path));

      final renamed = before.organization.copyWith(name: 'Freelance');
      await store.writeOrganization(renamed);
      await store.queue.drain();
      expect(marker()['name'], 'Freelance');
      expect(marker()['future'], isTrue);
      expect(marker()['color'], 'ultraviolet');
      expect(store.isOwnWrite(file.path), isTrue);
      final after = await store.read();
      expect(after.organization.name, 'Freelance');
      expect(identical(after, before), isFalse);
    });

    test('an organization saved by a newer version is not written', () async {
      await WorkspaceStore.initialize(dir.path);
      File(
        p.join(dir.path, WorkspaceStore.markerFileName),
      ).writeAsStringSync(jsonEncode({'app': 'tasklet', 'formatVersion': 99}));
      final info = OrgInfo(name: p.basename(dir.path));
      await expectLater(
        WorkspaceStore.writeOrganizationAt(
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
    test('a settings file from before organizations lists its folder', () {
      final orgs = Prefs({PrefKeys.dataFolder: r'D:\Tasks\Tasklet'})
          .organizations;
      expect(orgs, hasLength(1));
      expect(orgs.single.folder, r'D:\Tasks\Tasklet');
      expect(orgs.single.info.name, 'Tasklet');
    });

    test(
      'the list round-trips, keeps its order and lists each folder once',
      () {
        final stored = encodeOrganizations([
          (
            folder: '/b',
            info: const OrgInfo(name: 'B', color: TaskletColor.pink),
          ),
          (folder: '/a', info: const OrgInfo(name: 'A', icon: null)),
        ]);
        final orgs = Prefs({
          PrefKeys.organizations: [
            ...jsonDecode(jsonEncode(stored)) as List<Object?>,
            {'folder': '/b', 'name': 'B again'},
            'junk',
            {'name': 'no folder'},
          ],
          PrefKeys.dataFolder: '/a',
        }).organizations;
        expect([for (final o in orgs) o.info.name], ['B', 'A']);
        expect(orgs.first.info.color, TaskletColor.pink);
        expect(orgs.last.info.icon, isNull);
      },
    );
  });
}
