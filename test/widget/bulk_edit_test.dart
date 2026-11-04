import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// Bulk edit (D17): Ctrl+click selects, the bar edits every selected task, one Undo restores them.
void main() {
  testWidgets('select two cards, set their priority, undo', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('tasklet_bulk_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = await tester.runAsync(() async {
      await WorkspaceStore.initialize(dir.path);
      final store = WorkspaceStore(dir.path);
      await store.read();
      await store.writeProject(
        project(
          'p1',
          name: 'Website',
          key: 'WEB',
          nextNumber: 4,
          tasks: [
            task('a', number: 1, title: 'Alpha', sortOrder: 1000),
            task('b', number: 2, title: 'Bravo', sortOrder: 2000),
            task('c', number: 3, title: 'Charlie', sortOrder: 3000),
          ],
        ),
      );
      final prefs = await PrefsStore.open(
        p.join(dir.path, 'device-prefs.json'),
      );
      await prefs.set(PrefKeys.dataFolder, dir.path);
      await prefs.set(PrefKeys.whatsNewSeen, currentRelease.id);
      return prefs;
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsStoreProvider.overrideWithValue(prefs!)],
          child: const TaskletApp(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await settle(tester);
    appRouter.go('/my-tasks');
    await settle(tester, rounds: 5);

    Map<String, Priority> priorities() => {
      for (final t in ProviderScope.containerOf(
        tester.element(find.byType(TaskletApp)),
      ).read(workspaceDataProvider)!.projectById('p1')!.tasks)
        t.title: t.priority,
    };

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, rounds: 3);
    expect(find.text('2 tasks selected'), findsOneWidget);
    expect(find.text('Add a description…'), findsNothing); // nothing opened

    await tester.tap(find.text('Priority ▾'));
    await settle(tester, rounds: 3);
    await tester.tap(find.text('High').last);
    // The Undo toast appears once the change is saved.
    for (var i = 0; i < 20 && find.text('Undo').evaluate().isEmpty; i++) {
      await settle(tester, rounds: 2);
    }
    expect(priorities(), {
      'Alpha': Priority.high,
      'Bravo': Priority.none,
      'Charlie': Priority.high,
    });

    await tester.tap(find.text('Undo'));
    await settle(tester, rounds: 8);
    expect(priorities().values.toSet(), {Priority.none});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 3);
    expect(find.textContaining('selected'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
