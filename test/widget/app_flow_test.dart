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
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';

import '../helpers.dart';

/// Lets real file I/O (store reads, watcher) finish between frames.
Future<void> settle(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('opens a folder, shows the board and the detail panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('tasklet_widget_');
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
          tasks: [
            task('t1', number: 1, title: 'Write the homepage copy'),
            task(
              't2',
              number: 2,
              title: 'Ship it',
              status: TaskStatus.done,
              completed: t0,
            ),
          ],
        ),
      );
      final prefs = await PrefsStore.open(
        p.join(dir.path, 'device-prefs.json'),
      );
      await prefs.set(PrefKeys.dataFolder, dir.path);
      return prefs;
    });

    // Build inside runAsync so the workspace's real file reads complete.
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

    // Sidebar shows the project; All Tasks shows the board with both tasks.
    expect(find.text('Website'), findsWidgets);
    appRouter.go('/my-tasks');
    await settle(tester, rounds: 5);
    expect(find.text('Write the homepage copy'), findsOneWidget);
    expect(find.text('Recent first'), findsOneWidget);

    // Opening a task shows the detail panel with its ID.
    await tester.tap(find.text('Write the homepage copy'));
    await settle(tester, rounds: 5);
    expect(find.text('WEB-1'), findsWidgets);
    expect(find.text('Add a description…'), findsOneWidget);

    // Escape closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 5);
    expect(find.text('Add a description…'), findsNothing);

    // Dispose providers (timers, watcher) before the test ends.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
