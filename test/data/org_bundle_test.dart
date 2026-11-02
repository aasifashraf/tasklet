import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/org_bundle.dart';
import 'package:tasklet/core/organization.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

/// Export and import of a whole organization (docs/DECISIONS.md D15).
void main() {
  OrgBundle parse(Object? json) => OrgBundle.fromJson(
    jsonDecode(jsonEncode(json)),
    isSafeId: WorkspaceStore.isSafeProjectId,
  );

  Map<String, Object?> valid() => OrgBundle(
    organization: const OrgInfo(name: 'Acme', color: TaskletColor.teal),
    exportedAt: t0,
    labels: const [],
    views: const [],
    projects: [
      project('p1', tasks: [task('t1')]).toJson(),
    ],
  ).toJson();

  group('reading an export', () {
    test('round-trips', () {
      final b = parse(valid());
      expect(
        b.organization,
        const OrgInfo(name: 'Acme', color: TaskletColor.teal),
      );
      expect(b.projects.single['id'], 'p1');
      expect(b.taskCount, 1);
      expect(b.exportedAt, t0);
    });

    test('refuses what it is not, a newer format, and damaged projects', () {
      void refuses(Object? json, String message) => expect(
        () => parse(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      refuses([1, 2], "isn't a Tasklet organization export");
      refuses({...valid(), 'kind': 'report'}, "isn't a Tasklet");
      refuses({...valid(), 'formatVersion': 2}, 'newer version');
      refuses({...valid(), 'formatVersion': 'x'}, "can't be read");
      refuses({
        ...valid(),
        'projects': [
          {'id': '../evil', 'name': 'x'},
        ],
      }, 'damaged project');
      refuses({
        ...valid(),
        'projects': [
          {'id': 'p1', 'name': 'x'},
        ],
      }, "can't be read");
      final p1 = project('p1').toJson();
      refuses({
        ...valid(),
        'projects': [p1, p1],
      }, 'twice');
    });
  });

  group('folders', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('tasklet_bundle_'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'export then import gives the same organization, unknown fields included',
      () async {
        final from = p.join(root.path, 'Acme');
        Directory(from).createSync();
        await WorkspaceStore.initialize(
          from,
          organization: const OrgInfo(name: 'Acme'),
        );
        final store = WorkspaceStore(from);
        await store.read();
        final label = Label(id: 'bug', name: 'bug', color: TaskletColor.red);
        await store.writeLabels([label]);
        await store.writeViews([
          SavedView(id: 'v1', name: 'Urgent', createdAt: t0, updatedAt: t0),
        ]);
        // A field from a newer version, and a No Project task.
        File(store.projectPath('p1')).writeAsStringSync(
          jsonEncode({
            ...project(
              'p1',
              name: 'Billing',
              key: 'BIL',
              tasks: [task('t1', number: 4)],
            ).toJson(),
            'future': 'kept',
          }),
        );
        await store.writeProject(
          Project.noProject(t0).copyWith(tasks: [task('t2')]),
        );
        await store.queue.drain();
        final ws = await store.read();

        final bundle = parse(store.exportBundle(ws, t0).toJson());
        expect(bundle.projects, hasLength(2));

        final to = p.join(root.path, 'Copy');
        Directory(to).createSync();
        await WorkspaceStore.importBundle(
          to,
          bundle,
          const OrgInfo(name: 'Acme copy', icon: 'rocket'),
        );
        final copy = await WorkspaceStore(to).read();
        expect(copy.organization.name, 'Acme copy');
        expect(copy.organization.icon, 'rocket');
        expect(copy.projects.single.name, 'Billing');
        expect(copy.projects.single.tasks.single.number, 4);
        expect(copy.projects.single.extra['future'], 'kept');
        expect(copy.noProject.tasks.single.id, 't2');
        expect(copy.labels.single.name, 'bug');
        expect(copy.views.single.name, 'Urgent');
      },
    );

    test(
      'import needs an empty folder and leaves nothing behind on failure',
      () async {
        final bundle = parse(valid());
        final busy = p.join(root.path, 'Busy');
        Directory(busy).createSync();
        File(p.join(busy, 'notes.txt')).writeAsStringSync('mine');
        await expectLater(
          WorkspaceStore.importBundle(busy, bundle, const OrgInfo(name: 'X')),
          throwsA(isA<UnsafeWriteException>()),
        );
        expect(File(p.join(busy, 'notes.txt')).readAsStringSync(), 'mine');

        final bad = OrgBundle(
          organization: const OrgInfo(name: 'X'),
          exportedAt: t0,
          labels: const [],
          views: const [],
          projects: [
            project('ok').toJson(),
            {'id': 'CON', 'name': 'reserved on Windows'},
          ],
        );
        final empty = p.join(root.path, 'Empty');
        Directory(empty).createSync();
        await expectLater(
          WorkspaceStore.importBundle(empty, bad, const OrgInfo(name: 'X')),
          throwsA(isA<UnsafeWriteException>()),
        );
        expect(Directory(empty).listSync(), isEmpty);
      },
    );

    test('export waits while a project file is unreadable', () async {
      final from = p.join(root.path, 'Syncing');
      Directory(from).createSync();
      await WorkspaceStore.initialize(from);
      File(p.join(from, 'projects', 'half.json'))
          .writeAsStringSync('{"id": "ha');
      final store = WorkspaceStore(from);
      final ws = await store.read();
      expect(
        () => store.exportBundle(ws, t0),
        throwsA(isA<UnsafeWriteException>()),
      );
    });
  });
}
