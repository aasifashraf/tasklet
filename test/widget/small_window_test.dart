import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// The smallest window Tasklet allows (main.dart) with 200% OS text, which covers 125% and 150% too: the shell, the
/// board, the New Task dialog and the detail panel must fit with nothing overflowing, and Create must be reachable
/// (docs/DESIGN_SYSTEM.md, layout robustness).
void main() {
  const window = Size(900, 600);

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final dir = Directory.systemTemp.createTempSync('tasklet_small_');
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
            task(
              't1',
              number: 1,
              title: 'Write the homepage copy',
              description: List.filled(
                40,
                'A long description line.',
              ).join('\n'),
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
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  }

  testWidgets('New Task fits at 900x600 with 200% text; Create is reachable', (
    tester,
  ) async {
    await openApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, rounds: 5);
    expect(find.text('Create Task'), findsOneWidget);

    // A long description grows the field to its cap; the dialog must still fit.
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, 'Title');
    await tester.enterText(fields.at(1), List.filled(30, 'line').join('\n'));
    await settle(tester, rounds: 3);

    final create = tester.getRect(find.text('Create Task'));
    expect(create.bottom, lessThanOrEqualTo(window.height));
    await tester.tap(find.text('Create Task'));
    await settle(tester);
    expect(find.text('Create Task'), findsNothing);
    expect(find.text('Title'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('the detail panel fits at 900x600 with 200% text', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('Write the homepage copy'));
    await settle(tester, rounds: 5);
    expect(find.text('WEB-1'), findsWidgets);

    final panel = tester.getRect(
      find
          .ancestor(
            of: find.text('WEB-1').last,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.right, lessThanOrEqualTo(window.width));
    expect(panel.bottom, lessThanOrEqualTo(window.height));

    await closeApp(tester);
  });
}
