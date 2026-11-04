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

/// Editing in the task panel (SPEC §7.4): title and description autosave after a pause and on close; an emptied
/// title is never saved and comes back.
void main() {
  late String folder;

  Future<void> openPanel(WidgetTester tester, {String description = ''}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('tasklet_panel_');
    addTearDown(() => dir.deleteSync(recursive: true));
    folder = dir.path;
    final prefs = await tester.runAsync(() async {
      await WorkspaceStore.initialize(dir.path);
      final store = WorkspaceStore(dir.path);
      await store.read();
      await store.writeProject(
        project(
          'p1',
          name: 'Website',
          key: 'WEB',
          tasks: [
            task(
              't1',
              number: 1,
              title: 'Write the homepage copy',
              description: description,
            ),
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
    await tester.tap(find.text('Write the homepage copy'));
    await settle(tester, rounds: 5);
    expect(find.text('WEB-1'), findsWidgets);
  }

  Task current(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TaskletApp)))
          .read(workspaceDataProvider)!
          .projects
          .single
          .tasks
          .single;

  String onDisk() =>
      File(p.join(folder, 'projects', 'p1.json')).readAsStringSync();

  Finder field(String text) =>
      find.widgetWithText(TextField, text).hitTestable();

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  }

  testWidgets('the title saves after a pause, also to disk', (tester) async {
    await openPanel(tester);
    await tester.enterText(
      field('Write the homepage copy'),
      'Ship the homepage',
    );
    // Nothing yet: the save waits for a 500 ms pause in typing.
    expect(current(tester).title, 'Write the homepage copy');
    await settle(tester, rounds: 12);
    expect(current(tester).title, 'Ship the homepage');
    // The optimistic edit is in memory at once; the file follows when the save queue runs.
    for (var i = 0; i < 20 && !onDisk().contains('Ship the homepage'); i++) {
      await settle(tester, rounds: 2);
    }
    expect(onDisk(), contains('"title": "Ship the homepage"'));
    await close(tester);
  });

  testWidgets('the description saves when the panel closes with Escape', (
    tester,
  ) async {
    await openPanel(tester);
    await tester.enterText(field('Add a description…'), 'Two paragraphs.');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 8);
    expect(find.text('Add a description…'), findsNothing);
    expect(current(tester).description, 'Two paragraphs.');
    await close(tester);
  });

  testWidgets('an emptied title is not saved and comes back', (tester) async {
    await openPanel(tester);
    await tester.enterText(field('Write the homepage copy'), '   ');
    await settle(tester, rounds: 12);
    expect(current(tester).title, 'Write the homepage copy');
    // Leaving the field brings the title back.
    await tester.tap(field('Add a description…'));
    await settle(tester, rounds: 3);
    expect(find.text('Write the homepage copy'), findsWidgets);
    expect(current(tester).title, 'Write the homepage copy');
    await close(tester);
  });

  testWidgets('a Markdown description: checkboxes toggle, a click edits', (
    tester,
  ) async {
    const before = 'Steps:\n- [ ] draft\n- [x] review';
    const after = 'Steps:\n- [x] draft\n- [x] review';
    await openPanel(tester, description: before);
    expect(find.text('draft'), findsOneWidget); // rendered, not the raw text
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester, rounds: 12);
    expect(current(tester).description, after);

    await tester.tap(find.text('Steps:'));
    await settle(tester, rounds: 3);
    expect(find.widgetWithText(TextField, after), findsOneWidget);
    await close(tester);
  });
}
