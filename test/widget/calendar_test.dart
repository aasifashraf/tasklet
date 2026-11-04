import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/state/workspace.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// The calendar layout (D17): tasks on their due dates; dragging one to another day sets its due date.
void main() {
  testWidgets('drag a task to another day', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = LocalDate.fromDateTime(DateTime.now());
    final dueDay = today.day <= 20 ? today.addDays(2) : today.addDays(-5);
    final target = dueDay.addDays(3);
    final dir = Directory.systemTemp.createTempSync('tasklet_calendar_');
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
            task('t1', number: 1, title: 'Launch', due: dueDay),
            task('t2', number: 2, title: 'Undated'),
          ],
        ),
      );
      final prefs = await PrefsStore.open(
        p.join(dir.path, 'device-prefs.json'),
      );
      await prefs.set(PrefKeys.dataFolder, dir.path);
      await prefs.set(PrefKeys.whatsNewSeen, currentRelease.id);
      await prefs.set(PrefKeys.boardDisplay('all'), {'layout': 'calendar'});
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

    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('1 task has no due date'), findsOneWidget);

    // The day cell of the target date: the day number in the same month view.
    final targetCell = find.text('${target.day}').first;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Launch')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset.lerp(
          tester.getCenter(find.text('Launch').first),
          tester.getCenter(targetCell) + const Offset(0, 30),
          i / 10,
        )!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, rounds: 8);

    final moved = ProviderScope.containerOf(
      tester.element(find.byType(TaskletApp)),
    ).read(workspaceDataProvider)!.projectById('p1')!.taskById('t1')!;
    expect(moved.dueDate, target);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('the layout control shows all three; one click picks any', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('tasklet_layouts_');
    // The layout choice is saved to the settings file in this folder; on a busy machine that write can still hold
    // the file when the test ends, so removing the folder retries briefly.
    addTearDown(() async {
      for (var i = 0; i < 20; i++) {
        try {
          dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    final prefs = await tester.runAsync(() async {
      await WorkspaceStore.initialize(dir.path);
      final store = WorkspaceStore(dir.path);
      await store.read();
      await store.writeProject(
        project('p1', name: 'Website', key: 'WEB', tasks: [task('t1')]),
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

    for (final name in ['Board view', 'List view', 'Calendar view']) {
      expect(find.byTooltip(name), findsOneWidget);
    }
    expect(find.text('Backlog'), findsWidgets); // board
    await tester.tap(find.byTooltip('Calendar view'));
    await settle(tester, rounds: 5);
    expect(find.text('Month'), findsOneWidget); // calendar, in one click
    await tester.tap(find.byTooltip('List view'));
    await settle(tester, rounds: 5);
    expect(find.text('Month'), findsNothing);

    // Let the layout choice finish saving before the folder is removed.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 10);
  });
}
