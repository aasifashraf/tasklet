import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/ui/shell/sidebar.dart';

import '../helpers.dart';
import 'app_flow_test.dart' show settle;

/// The sidebar's sections are lazy slivers: hundreds of projects build only the rows in view.
void main() {
  const count = 400;

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('tasklet_sidebar_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = await tester.runAsync(() async {
      await WorkspaceStore.initialize(dir.path);
      final store = WorkspaceStore(dir.path);
      await store.read();
      for (var i = 0; i < count; i++) {
        final pr = project('p$i', name: 'Project $i', key: 'PRO');
        await store.writeProject(pr.copyWith(sortOrder: i * 1000.0));
      }
      await store.queue.drain();
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
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await settle(tester);
  }

  testWidgets('hundreds of projects: only the rows in view are built', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project ${count - 1}'), findsNothing);
    final built = find.textContaining('Project ').evaluate().length;
    expect(built, lessThan(60));

    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(Sidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('Project ${count - 1}'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
