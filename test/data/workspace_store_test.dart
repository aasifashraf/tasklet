import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/atomic_file.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

void main() {
  late Directory root;
  late String folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasklet_store_');
    folder = root.path;
  });

  tearDown(() => root.delete(recursive: true));

  String projectsDir() => p.join(folder, 'projects');

  Future<void> writeRaw(String relative, Object? json) async {
    final file = File(p.join(folder, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(json is String ? json : jsonEncode(json));
  }

  Future<WorkspaceStore> opened() async {
    await WorkspaceStore.initialize(folder);
    return WorkspaceStore(folder, clock: () => t0);
  }

  test('initialize writes the marker and projects dir, no demo data', () async {
    await WorkspaceStore.initialize(folder);
    final marker = jsonDecode(await File(p.join(folder, 'tasklet-workspace.json')).readAsString());
    expect(marker, {'app': 'tasklet', 'formatVersion': 1});
    expect(await Directory(projectsDir()).list().isEmpty, isTrue);
    final ws = await WorkspaceStore(folder).read();
    expect(ws.projects, isEmpty);
    expect(ws.noProjectOnDisk, isFalse);
    expect(ws.noProject.key, 'TSK');
  });

  test('missing folder is an error, never recreated', () async {
    final missing = p.join(folder, 'gone');
    await expectLater(WorkspaceStore(missing).read(), throwsA(isA<WorkspaceFolderMissing>()));
    await expectLater(WorkspaceStore.initialize(missing), throwsA(isA<WorkspaceFolderMissing>()));
    expect(await Directory(missing).exists(), isFalse);
  });

  test('writes atomically and reads back, leaving no temp files', () async {
    final store = await opened();
    final pr = project('p1', name: 'Website', key: 'WEB', tasks: [task('t1')]);
    await store.writeProject(pr);
    final files = await Directory(projectsDir()).list().map((e) => p.basename(e.path)).toList();
    expect(files, ['p1.json']);
    final ws = await store.read();
    expect(ws.projects.single.toJson(), pr.toJson());
  });

  test('a leftover temp file from a crashed save is ignored', () async {
    final store = await opened();
    await store.writeProject(project('p1', key: 'WEB'));
    await writeRaw('projects/.p1.json.abc.tmp', '{"half": ');
    final ws = await store.read();
    expect(ws.projects.single.id, 'p1');
  });

  test('unknown fields survive a read-modify-write cycle on disk', () async {
    final json = project('p1', key: 'WEB', tasks: [task('t1')]).toJson()..['futureProjectField'] = 'keep';
    (json['tasks']! as List<Object?>)[0] = {...(json['tasks']! as List<Object?>)[0]! as Map<String, Object?>, 'x': 1};
    await writeRaw('projects/p1.json', json);
    final store = await opened();
    final ws = await store.read();
    await store.writeProject(ws.projects.single.copyWith(name: 'Renamed'));
    final saved = jsonDecode(await File(p.join(projectsDir(), 'p1.json')).readAsString()) as Map<String, Object?>;
    expect(saved['futureProjectField'], 'keep');
    expect(((saved['tasks']! as List<Object?>)[0]! as Map<String, Object?>)['x'], 1);
    expect(saved['name'], 'Renamed');
  });

  test('an unparsable project file is skipped and never overwritten', () async {
    await writeRaw('projects/p1.json', '{"id": "p1", "name": ');
    final store = await opened();
    final ws = await store.read();
    expect(ws.projects, isEmpty);
    await expectLater(store.writeProject(project('p1', key: 'WEB')), throwsA(isA<UnsafeWriteException>()));
    expect(await File(p.join(projectsDir(), 'p1.json')).readAsString(), '{"id": "p1", "name": ');
  });

  test('an unreadable No-Project file blocks lazily creating a new one', () async {
    await writeRaw('projects/$noProjectId.json', 'garbage');
    final store = await opened();
    final ws = await store.read();
    expect(ws.noProjectOnDisk, isFalse);
    final withTask = ws.noProject.copyWith(tasks: [task('t1')]);
    await expectLater(store.writeProject(withTask), throwsA(isA<UnsafeWriteException>()));
  });

  test('No-Project file is created lazily, only once it has a task', () async {
    final store = await opened();
    final ws = await store.read();
    await store.writeProject(ws.noProject);
    expect(await File(store.projectPath(noProjectId)).exists(), isFalse);
    await store.writeProject(ws.noProject.copyWith(tasks: [task('t1')]));
    final again = await store.read();
    expect(again.noProjectOnDisk, isTrue);
    expect(again.noProject.tasks.single.id, 't1');
    expect(again.projects, isEmpty, reason: 'No Project never appears as a real project');
  });

  test('No-Project identity is fixed even if the file was edited', () async {
    final np = Project.noProject(t0).copyWith(name: 'Hacked', key: 'XYZ', archived: true, tasks: [task('t1')]);
    await writeRaw('projects/$noProjectId.json', np.toJson());
    final ws = await (await opened()).read();
    expect(ws.noProject.name, 'No Project');
    expect(ws.noProject.key, 'TSK');
    expect(ws.noProject.archived, isFalse);
  });

  test('sync conflict copies are reported and left untouched', () async {
    final pr = project('p1', name: 'Website', key: 'WEB');
    await writeRaw('projects/p1.json', pr.toJson());
    final copyJson = pr.copyWith(name: 'Website (other machine)').toJson();
    await writeRaw('projects/p1 2.json', copyJson);
    final copyBytes = await File(p.join(projectsDir(), 'p1 2.json')).readAsString();

    final store = await opened();
    final ws = await store.read();
    expect(ws.projects.single.name, 'Website');
    expect(ws.conflicts.single.projectName, 'Website (other machine)');
    expect(p.basename(ws.conflicts.single.file), 'p1 2.json');

    await store.writeProject(ws.projects.single.copyWith(name: 'Edited'));
    expect(await File(p.join(projectsDir(), 'p1 2.json')).readAsString(), copyBytes);
  });

  test('project keys self-heal by createdAt and are persisted', () async {
    await writeRaw('projects/a.json', project('a', name: 'Web A', key: 'WEB', created: at(5)).toJson());
    await writeRaw('projects/b.json', project('b', name: 'Web B', key: 'WEB', created: at(0)).toJson());
    await writeRaw('projects/c.json', project('c', name: 'Legacy', key: '').toJson());
    final store = await opened();
    final ws = await store.read();
    expect({for (final pr in ws.projects) pr.id: pr.key}, {'a': 'WEB1', 'b': 'WEB', 'c': 'LEG'});
    final onDisk = jsonDecode(await File(p.join(projectsDir(), 'a.json')).readAsString()) as Map<String, Object?>;
    expect(onDisk['key'], 'WEB1');
  });

  test('project ids that are not safe file names are rejected', () async {
    await writeRaw('projects/evil.json', project('../evil', key: 'EVI').toJson());
    final store = await opened();
    expect((await store.read()).projects, isEmpty);
    await expectLater(store.writeProject(project('../x', key: 'X')), throwsA(isA<UnsafeWriteException>()));
  });

  group('labels.json and views.json', () {
    test('missing files read as empty and readable', () async {
      final ws = await (await opened()).read();
      expect(ws.labels, isEmpty);
      expect(ws.labelsReadable, isTrue);
      expect(ws.viewsReadable, isTrue);
    });

    test('round-trip', () async {
      final store = await opened();
      await store.read();
      await store.writeLabels([Label(id: 'l1', name: 'Bug', color: TaskletColor.red)]);
      await store.writeViews([SavedView(id: 'v1', name: 'Mine', createdAt: t0, updatedAt: t0)]);
      final ws = await store.read();
      expect(ws.labels.single.name, 'Bug');
      expect(ws.views.single.name, 'Mine');
    });

    test('unreadable labels.json is flagged and writes are refused', () async {
      await writeRaw('labels.json', '[{"id": "l1"');
      final store = await opened();
      final ws = await store.read();
      expect(ws.labelsReadable, isFalse);
      expect(ws.viewsReadable, isTrue);
      expect(() => store.writeLabels([]), throwsA(isA<UnsafeWriteException>()));
      expect(await File(p.join(folder, 'labels.json')).readAsString(), '[{"id": "l1"');
    });

    test('unreadable views.json is flagged and writes are refused', () async {
      await writeRaw('views.json', {'not': 'a list'});
      final store = await opened();
      expect((await store.read()).viewsReadable, isFalse);
      expect(() => store.writeViews([]), throwsA(isA<UnsafeWriteException>()));
    });
  });

  test('writes to the same file land in submission order', () async {
    final store = await opened();
    final base = project('p1', key: 'WEB');
    await Future.wait([for (var i = 0; i < 10; i++) store.writeProject(base.copyWith(name: 'v$i'))]);
    final ws = await store.read();
    expect(ws.projects.single.name, 'v9');
    expect(store.queue.inFlight, 0);
  });

  test('encodeJson is pretty and newline-terminated', () {
    expect(encodeJson({'a': 1}), '{\n  "a": 1\n}\n');
  });
}
