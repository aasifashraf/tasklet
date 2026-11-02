import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/workspace_store.dart';

import '../helpers.dart';

/// Two computers using one synced folder: each store stands for one computer with its own view of the files
/// (docs/SYSTEM_DESIGN.md section 14).
void main() {
  late Directory root;
  late String folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tasklet_two_');
    folder = root.path;
    await WorkspaceStore.initialize(folder);
    await WorkspaceStore(folder, clock: () => t0).writeProject(
      project(
        'p1',
        name: 'Web',
        key: 'WEB',
        nextNumber: 3,
        tasks: [
          task('a', number: 1, title: 'A'),
          task('b', number: 2, title: 'B'),
        ],
      ),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Project edited(Workspace ws, String id, String title, int minute) {
    final p1 = ws.projectById('p1')!;
    return p1.copyWith(
      tasks: [
        for (final t in p1.tasks)
          t.id == id ? t.copyWith(title: title, updatedAt: at(minute)) : t,
      ],
    );
  }

  test('edits to different tasks from two computers are both saved', () async {
    final laptop = WorkspaceStore(folder, clock: () => at(10));
    final desktop = WorkspaceStore(folder, clock: () => at(10));
    final onLaptop = await laptop.read();
    final onDesktop = await desktop.read(); // both start from the same file

    await laptop.writeProject(edited(onLaptop, 'a', 'A from laptop', 5));
    // The desktop hasn't seen that save yet and edits another task.
    await desktop.writeProject(edited(onDesktop, 'b', 'B from desktop', 6));

    final ws = await WorkspaceStore(folder, clock: () => at(10)).read();
    final p1 = ws.projectById('p1')!;
    expect(p1.taskById('a')!.title, 'A from laptop');
    expect(p1.taskById('b')!.title, 'B from desktop');
    expect(
      desktop.takeMergeNotes().first,
      contains('changed on another computer'),
    );
    expect(laptop.takeMergeNotes(), isEmpty);
  });

  test(
    "a store recognises its own save, and another computer's save as foreign",
    () async {
      final laptop = WorkspaceStore(folder, clock: () => at(10));
      final desktop = WorkspaceStore(folder, clock: () => at(10));
      final path = laptop.projectPath('p1');
      final onLaptop = await laptop.read();
      await desktop.read();

      await laptop.writeProject(edited(onLaptop, 'a', 'A2', 5));
      expect(laptop.isOwnWrite(path), isTrue);
      expect(desktop.isOwnWrite(path), isFalse);

      // Right after the laptop's save, the desktop saves: the laptop must not mistake it for its own.
      final onDesktop = await desktop.read();
      await desktop.writeProject(edited(onDesktop, 'b', 'B2', 6));
      expect(laptop.isOwnWrite(path), isFalse);
    },
  );

  test(
    'a version that changed but cannot be read yet is never overwritten',
    () async {
      final laptop = WorkspaceStore(folder, clock: () => at(10));
      final onLaptop = await laptop.read();
      final path = p.join(folder, 'projects', 'p1.json');
      await File(path).writeAsString(
        '{"id": "p1", "half-synced',
      ); // a sync client mid-download
      await expectLater(
        laptop.writeProject(edited(onLaptop, 'a', 'A2', 5)),
        throwsA(isA<UnsafeWriteException>()),
      );
      expect(await File(path).readAsString(), '{"id": "p1", "half-synced');
    },
  );

  test('unchanged files are written directly, without a merge', () async {
    final laptop = WorkspaceStore(folder, clock: () => at(10));
    final ws = await laptop.read();
    await laptop.writeProject(edited(ws, 'a', 'A2', 5));
    final again = await laptop.read();
    await laptop.writeProject(edited(again, 'b', 'B2', 6));
    expect(laptop.takeMergeNotes(), isEmpty);
  });
}
