import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/starter.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';

/// Starter content goes only into new, empty folders (docs/DECISIONS.md D16).
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('tasklet_starter_'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    root.deleteSync(recursive: true);
  });

  String folder(String name) =>
      (Directory(p.join(root.path, name))..createSync()).path;
  StarterContent starter() =>
      starterContent(newId: _ids(), now: t0, withSampleProject: true);

  test(
    'an empty folder gets the starter labels, quick filters and project',
    () async {
      final dir = folder('New');
      await WorkspaceStore.initialize(
        dir,
        starter: starterContent(
          newId: _ids(),
          now: t0,
          withSampleProject: true,
        ),
      );
      final ws = await WorkspaceStore(dir).read();
      expect(ws.labels, hasLength(4));
      expect(ws.views, hasLength(5));
      expect(ws.projects.single.name, 'Tasklet');
    },
  );

  test('a folder with anything of Tasklet in it gets nothing', () async {
    for (final (name, make) in <(String, void Function(String))>[
      (
        'marker',
        (d) =>
            File(p.join(d, WorkspaceStore.markerFileName))
                .writeAsStringSync('{"app":"tasklet"}'),
      ),
      (
        'labels',
        (d) =>
            File(p.join(d, WorkspaceStore.labelsFileName))
                .writeAsStringSync('[]'),
      ),
      (
        'views',
        (d) =>
            File(p.join(d, WorkspaceStore.viewsFileName))
                .writeAsStringSync('[]'),
      ),
      (
        'project',
        (d) {
          Directory(p.join(d, 'projects')).createSync();
          File(p.join(d, 'projects', 'p1.json'))
              .writeAsStringSync(jsonEncode(project('p1').toJson()));
        },
      ),
    ]) {
      final dir = folder(name);
      make(dir);
      await WorkspaceStore.initialize(dir, starter: starter());
      final ws = await WorkspaceStore(dir).read();
      expect(ws.labels, isEmpty, reason: name);
      expect(ws.views, isEmpty, reason: name);
      expect(
        ws.projects.where((x) => x.name == 'Tasklet'),
        isEmpty,
        reason: name,
      );
    }
  });

  test('the first workspace gets the sample project, later ones only labels and filters', () async {
    final prefs = await PrefsStore.open(p.join(root.path, 'prefs.json'));
    final container = ProviderContainer(
      overrides: [prefsStoreProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final controller = container.read(workspaceProvider.notifier);
    Future<Workspace> opened() async {
      for (var i = 0; i < 100; i++) {
        final ws = container.read(workspaceDataProvider);
        if (ws != null) return ws;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('the workspace did not open');
    }

    await controller.addWorkspace(folder('First'));
    final first = await opened();
    expect(first.projects.single.name, 'Tasklet');
    expect(first.labels, hasLength(4));

    await controller.addWorkspace(folder('Second'));
    final second = await opened();
    expect(second.folder, endsWith('Second'));
    expect(second.projects, isEmpty);
    expect(second.labels, hasLength(4));
    expect(second.views.where((v) => v.inSidebar), hasLength(3));

    // A folder that already has Tasklet data gets nothing.
    final existing = folder('Existing');
    await WorkspaceStore.initialize(existing);
    await controller.addWorkspace(existing);
    final third = await opened();
    expect(third.folder, endsWith('Existing'));
    expect(third.labels, isEmpty);
  });
}

String Function() _ids() {
  var n = 0;
  return () => 'starter-${n++}';
}
