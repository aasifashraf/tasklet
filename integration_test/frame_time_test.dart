// Frame times on the All Tasks board with 10,000 tasks (docs/SYSTEM_DESIGN.md, phase 7). Local only, in profile
// mode (CI machines are too noisy):
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart \
//     --target=integration_test/frame_time_test.dart
// The frame summary (average / p90 / p99 build and raster times) lands in build/integration_response_data.json.
// Quit any running Tasklet first: profile and release builds hand off to a running copy and exit
// (windows/runner/main.cpp), which `flutter drive` reports as "the log reader stopped unexpectedly". In debug
// (`flutter test integration_test/frame_time_test.dart -d windows`) it runs next to an installed copy, but debug
// frame times say little, so the budget is only checked in profile.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/app.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/workspace_store.dart';
import 'package:tasklet/platform/whats_new_notes.dart';
import 'package:tasklet/router.dart';
import 'package:tasklet/state/prefs.dart';

const _projects = 10;
const _tasksPerProject = 1000;

Future<PrefsStore> _workspace(String dir) async {
  await WorkspaceStore.initialize(dir);
  final store = WorkspaceStore(dir);
  await store.read();
  final created = DateTime.utc(2026, 10, 1);
  for (var pi = 0; pi < _projects; pi++) {
    await store.writeProject(
      Project(
        id: 'p$pi',
        name: 'Project $pi',
        key: 'P${String.fromCharCode(65 + pi)}X',
        color: TaskletColor.values[pi % TaskletColor.values.length],
        nextNumber: _tasksPerProject + 1,
        createdAt: created,
        updatedAt: created,
        sortOrder: pi * 1000.0,
        tasks: [
          for (var i = 0; i < _tasksPerProject; i++)
            Task(
              id: 'p${pi}t$i',
              number: i + 1,
              title: 'Task $i of project $pi with a title long enough to wrap',
              description: 'Some notes for task $i.',
              status: TaskStatus.values[i % TaskStatus.values.length],
              priority: Priority.values[i % Priority.values.length],
              sortOrder: i * 1000.0,
              createdAt: created,
              updatedAt: created.add(Duration(minutes: i)),
              completedAt: i % 4 == 3 ? created.add(Duration(hours: i)) : null,
            ),
        ],
      ),
    );
  }
  await store.queue.drain();
  final prefs = await PrefsStore.open(p.join(dir, 'device-prefs.json'));
  await prefs.set(PrefKeys.dataFolder, dir);
  await prefs.set(PrefKeys.whatsNewSeen, currentRelease.id);
  return prefs;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('All Tasks with 10,000 tasks: scrolling and dragging', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('tasklet_frames_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = await _workspace(dir.path);

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsStoreProvider.overrideWithValue(prefs)],
        child: const TaskletApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    appRouter.go('/my-tasks');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Backlog'), findsWidgets);

    final columns = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );

    await binding.watchPerformance(() async {
      // Scroll each visible column down and back up.
      for (var i = 0; i < columns.evaluate().length && i < 4; i++) {
        await tester.fling(columns.at(i), const Offset(0, -1500), 2500);
        await tester.pumpAndSettle();
        await tester.fling(columns.at(i), const Offset(0, 1500), 2500);
        await tester.pumpAndSettle();
      }
      // Drag the first card across the board and back, slowly, like a hand.
      final card = find.textContaining('Task ').first;
      final from = tester.getCenter(card);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      for (var step = 1; step <= 60; step++) {
        final dx = step <= 30 ? step * 20.0 : (60 - step) * 20.0;
        await gesture.moveTo(from + Offset(dx, step.isEven ? 6 : 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }, reportKey: 'all_tasks_10k');

    final summary =
        binding.reportData!['all_tasks_10k'] as Map<String, Object?>;
    // ignore: avoid_print
    print('Frame summary: $summary');
    // Only profile builds give meaningful frame times.
    if (kProfileMode) {
      expect(
        summary['90th_percentile_frame_build_time_millis'] as num,
        lessThan(16),
      );
    }
  });
}
