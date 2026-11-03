import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

/// Dragging cards on the real board (SPEC §5.1): to another column changes the status, within a column under
/// Manual order changes the order.
void main() {
  Future<void> openBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('tasklet_drag_');
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
          nextNumber: 5,
          tasks: [
            task('a', number: 1, title: 'Alpha', sortOrder: 1000),
            task('b', number: 2, title: 'Bravo', sortOrder: 2000),
            task('c', number: 3, title: 'Charlie', sortOrder: 3000),
            task(
              'd',
              number: 4,
              title: 'Delta',
              status: TaskStatus.inProgress,
              sortOrder: 1000,
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
    expect(find.text('Alpha'), findsOneWidget);
  }

  Task taskNamed(WidgetTester tester, String title) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskletApp)),
    );
    final ws = container.read(workspaceDataProvider)!;
    return ws.projects
        .expand((p) => p.tasks)
        .firstWhere((t) => t.title == title);
  }

  /// Drags the card titled [title] with the mouse to [to], in small steps like a hand would.
  Future<void> dragCard(WidgetTester tester, String title, Offset to) async {
    final from = tester.getCenter(find.text(title));
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    // The drop saves to disk, then the card settles into place.
    await settle(tester, rounds: 20);
  }

  testWidgets('a card dropped on another column takes its status', (
    tester,
  ) async {
    await openBoard(tester);
    final inProgress = tester.getCenter(find.text('In Progress'));
    final delta = tester.getRect(find.text('Delta'));
    await dragCard(tester, 'Alpha', Offset(inProgress.dx, delta.bottom + 60));
    expect(taskNamed(tester, 'Alpha').status, TaskStatus.inProgress);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a card dropped above another in its column moves there', (
    tester,
  ) async {
    await openBoard(tester);
    final alpha = tester.getRect(find.text('Alpha'));
    await dragCard(tester, 'Charlie', Offset(alpha.center.dx, alpha.top - 4));
    final charlie = taskNamed(tester, 'Charlie');
    expect(charlie.status, TaskStatus.todo);
    expect(charlie.sortOrder, lessThan(taskNamed(tester, 'Alpha').sortOrder));

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
