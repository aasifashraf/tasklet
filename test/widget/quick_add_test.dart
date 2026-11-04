import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// Quick add in New Task (D17): tokens in the title set the fields and leave the title.
void main() {
  testWidgets('New Task: "Fix login !high #bug +WEB" sets the fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('tasklet_quickadd_');
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
          labels: [Label(id: 'l1', name: 'bug', color: TaskletColor.red)],
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, rounds: 5);
    final title = find
        .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(title, 'Fix login !high #bug +WEB');
    await tester.pump();
    expect(find.text('High · #bug · in Website'), findsOneWidget);

    await tester.tap(find.text('Create Task'));
    await settle(tester);
    final ws = ProviderScope.containerOf(
      tester.element(find.byType(TaskletApp)),
    ).read(workspaceDataProvider)!;
    final created = ws.projectById('p1')!.tasks.single;
    expect(created.title, 'Fix login');
    expect(created.priority, Priority.high);
    expect(created.labelIds, ['l1']);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
