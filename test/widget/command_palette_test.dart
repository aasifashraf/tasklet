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

/// Ctrl+K command palette and the ? shortcut sheet, on the real app.
void main() {
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('tasklet_palette_');
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
          tasks: [task('t1', number: 1, title: 'Write the homepage copy')],
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
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, rounds: 3);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, rounds: 5);
  }

  String path() => appRouter.routerDelegate.currentConfiguration.uri.path;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  }

  testWidgets('Ctrl+K: open a project by name, a task by its ID', (
    tester,
  ) async {
    await openApp(tester);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(
      find.text('Type a command, project, quick filter or task'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'website');
    await tester.pump();
    expect(find.text('Project'), findsOneWidget);
    await submit(tester);
    expect(path(), '/projects/p1');

    await ctrl(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byType(TextField).last, 'web-1');
    await tester.pump();
    expect(
      find.text('WEB-1'),
      findsWidgets,
    ); // the palette row (and the card behind)
    await submit(tester);
    expect(find.text('Add a description…'), findsOneWidget); // the task panel
    await close(tester);
  });

  testWidgets('Ctrl+K runs menu commands too', (tester) async {
    await openApp(tester);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byType(TextField).last, 'all tasks');
    await tester.pump();
    await submit(tester);
    expect(path(), '/my-tasks');
    await close(tester);
  });

  testWidgets('? opens the shortcut sheet, but types in a text field', (
    tester,
  ) async {
    await openApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester, rounds: 3);
    expect(find.text('Keyboard Shortcuts'), findsWidgets);
    expect(find.text('Ctrl+N'), findsOneWidget); // New Task, from the menus
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 3);

    // In the palette's field, ? is just a character.
    await ctrl(tester, LogicalKeyboardKey.keyK);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyEvent(
      LogicalKeyboardKey.slash,
      character: '?',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester, rounds: 3);
    expect(handled, isFalse);
    expect(find.text('Keyboard Shortcuts'), findsNothing);
    await close(tester);
  });

  testWidgets('Ctrl+F on a project board opens its search', (tester) async {
    await openApp(tester);
    appRouter.go('/projects/p1');
    await settle(tester, rounds: 5);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(tester.takeException(), isNull);
    expect(find.text('Search title, ID, description'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Ctrl+Shift+F searches tasks only; Ctrl+K also has commands', (
    tester,
  ) async {
    await openApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, rounds: 3);
    expect(find.textContaining('Type to search every task'), findsOneWidget);

    // "web" matches the Website project's name and its task ID: only the task is listed.
    await tester.enterText(find.byType(TextField).last, 'web');
    await tester.pump();
    Finder inDialog(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inDialog('Write the homepage copy'), findsOneWidget);
    expect(inDialog('Website · Todo'), findsOneWidget);
    expect(inDialog('Project'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 3);

    await ctrl(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byType(TextField).last, 'web');
    await tester.pump();
    // Ctrl+K lists the project too.
    expect(inDialog('Project'), findsOneWidget);
    await close(tester);
  });
}
