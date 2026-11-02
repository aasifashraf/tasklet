// Performance benchmark of the store and core rules on a generated workspace (docs/PERFORMANCE.md).
//   python -I tool/bench/generate.py <dir> 100000
//   dart tool/bench/bench.dart <dir>
import 'dart:async';
import 'dart:io';

import 'package:tasklet/core/board_patch.dart';
import 'package:tasklet/core/dashboard.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/report.dart';
import 'package:tasklet/core/sorting.dart';
import 'package:tasklet/core/task_ops.dart' as ops;
import 'package:tasklet/data/workspace_store.dart';

/// Runs [f] [runs] times; prints p50 / p95 / max total time and the longest main-isolate stall.
Future<T> timed<T>(String label, Future<T> Function() f, {int runs = 1}) async {
  late T result;
  final totals = <int>[], stalls = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    var last = sw.elapsedMicroseconds, maxGap = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = sw.elapsedMicroseconds;
      if (now - last > maxGap) maxGap = now - last;
      last = now;
    });
    result = await f();
    final end = sw.elapsedMicroseconds;
    if (end - last > maxGap) maxGap = end - last;
    ticker.cancel();
    totals.add(end ~/ 1000);
    stalls.add(maxGap ~/ 1000);
  }
  totals.sort();
  stalls.sort();
  int pct(List<int> l, double q) => l[((l.length - 1) * q).round()];
  stdout.writeln(
    '${label.padRight(46)} p50 ${pct(totals, .5).toString().padLeft(6)}  p95 ${pct(totals, .95).toString().padLeft(6)}  '
    'max ${totals.last.toString().padLeft(6)} ms   UI stall max ${stalls.last.toString().padLeft(5)} ms',
  );
  return result;
}

Future<void> main(List<String> args) async {
  final store = WorkspaceStore(args.first);
  var ws = await timed('open: read() first time', store.read);
  await timed('refresh: read(), nothing changed', store.read, runs: 5);
  final tasks = ws.activeTasks.toList();
  final big = ws.projects.reduce(
    (a, b) => a.tasks.length > b.tasks.length ? a : b,
  );
  stdout.writeln(
    'tasks ${tasks.length}, projects ${ws.projects.length}, largest project ${big.tasks.length}',
  );
  final today = LocalDate(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 1, 12);

  await timed('All Tasks board: filter + groupAndSort', () async {
    final f = BoardFilters.empty;
    return groupAndSort(
      tasks.where((e) => matchesFilters(e, f, today)),
      ViewDisplay(),
    ).length;
  }, runs: 5);
  await timed(
    'largest project board: groupAndSort',
    () async => groupAndSort([
      for (final t in big.tasks) ProjectTask(big, t),
    ], ViewDisplay()).length,
    runs: 5,
  );
  final allGroups = groupAndSort(tasks, ViewDisplay());
  await timed('All Tasks board after one edit (patched)', () async {
    final t = big.tasks[big.tasks.length ~/ 3];
    final edited = ops.putTask(
      big,
      t.copyWith(priority: Priority.urgent, updatedAt: now),
      now,
    );
    final after = ws.copyWith(
      projects: [for (final p in ws.projects) p.id == big.id ? edited : p],
    );
    final diff = diffTasks(ws, after)!;
    return patchGroups(
      allGroups,
      ViewDisplay(),
      removed: diff.removed.values,
      added: diff.added,
    ).length;
  }, runs: 5);
  await timed('search "deploy cache" (cold, builds cache)', () async {
    final q = SearchQuery('deploy cache');
    return tasks.where(q.matches).length;
  });
  await timed('search "deploy cachex" (warm)', () async {
    final q = SearchQuery('deploy cachex');
    return tasks.where(q.matches).length;
  }, runs: 5);
  final deploy = SearchQuery('deploy');
  final deployGroups = groupAndSort(tasks.where(deploy.matches), ViewDisplay());
  await timed('search, typing more ("deploy" then "deploy c")', () async {
    final q = SearchQuery('deploy c');
    return [
      for (final g in deployGroups.values)
        for (final e in g)
          if (q.matches(e)) e,
    ].length;
  }, runs: 5);
  await timed('dashboard: glance + upNext + recent', () async {
    glanceFor(tasks, today, now);
    upNext(tasks, today);
    return recentlyCompleted(tasks, now).length;
  }, runs: 5);
  await timed('reports: tasks in "This Month"', () async {
    final period = periodFor(PeriodPreset.thisMonth, today, firstDayOfWeek: 1);
    return reportTasks(ws, const ReportFilters(), period).length;
  }, runs: 5);
  await timed(
    'sidebar counts: open tasks',
    () async => ws.activeTasks.where((e) => !e.task.isDone).length,
    runs: 5,
  );
  await timed('label usage map (fresh snapshot)', () async {
    ws = ws.copyWith();
    return ws.labelUsage.length;
  }, runs: 5);
  await timed('edit one task in largest project (in memory)', () async {
    final t = big.tasks[big.tasks.length ~/ 2];
    return ops.putTask(big, t.copyWith(title: '${t.title}!'), now).tasks.length;
  }, runs: 5);
  await timed('save largest project (encode + atomic write)', () async {
    await store.writeProject(big);
    await store.queue.drain();
  }, runs: 3);
  await timed('save a typical project', () async {
    await store.writeProject(ws.projects[5]);
    await store.queue.drain();
  }, runs: 5);
  stdout.writeln(
    'RSS now ${(ProcessInfo.currentRss / 1048576).round()} MB, peak ${(ProcessInfo.maxRss / 1048576).round()} MB',
  );
}
