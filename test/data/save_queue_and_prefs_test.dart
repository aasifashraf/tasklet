import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tasklet/data/atomic_file.dart';
import 'package:tasklet/data/folder_watcher.dart';
import 'package:tasklet/data/prefs_store.dart';
import 'package:tasklet/data/save_queue.dart';

void main() {
  late Directory root;

  setUp(
    () async => root = await Directory.systemTemp.createTemp('tasklet_queue_'),
  );
  tearDown(() => root.delete(recursive: true));

  group('SaveQueue', () {
    test('counts in-flight writes and serializes per path', () async {
      final queue = SaveQueue();
      final order = <int>[];
      final gate = Completer<void>();
      final counts = <int>[];
      queue.inFlightChanges.listen(counts.add);

      final first = queue.enqueue('a.json', () async {
        await gate.future;
        order.add(1);
      });
      final second = queue.enqueue('a.json', () async => order.add(2));
      expect(queue.inFlight, 2);

      gate.complete();
      await Future.wait([first, second]);
      expect(order, [1, 2]);
      expect(queue.inFlight, 0);
      await Future<void>.delayed(
        Duration.zero,
      ); // broadcast events are delivered asynchronously
      expect(counts, [1, 2, 1, 0]);
    });

    test(
      'a failed write does not block later writes and reports its own error',
      () async {
        final queue = SaveQueue();
        final failing = queue.enqueue(
          'a.json',
          () async => throw const FileSystemException('locked'),
        );
        final ok = queue.enqueue('a.json', () async {});
        await expectLater(failing, throwsA(isA<FileSystemException>()));
        await expectLater(ok, completes);
        expect(queue.inFlight, 0);
      },
    );

    test('remembers own writes for a short window', () async {
      var now = DateTime(2026);
      final queue = SaveQueue(clock: () => now);
      final path = p.join(root.path, 'x.json');
      expect(queue.isRecentOwnWrite(path), isFalse);
      await queue.enqueue(path, () async {});
      expect(queue.isRecentOwnWrite(path), isTrue);
      now = now.add(const Duration(seconds: 3));
      expect(queue.isRecentOwnWrite(path), isFalse);
    });
  });

  group('PrefsStore', () {
    test('missing or corrupt file starts empty; values persist', () async {
      final path = p.join(root.path, 'sub', 'prefs.json');
      final prefs = await PrefsStore.open(path);
      expect(prefs.get<String>('name'), isNull);
      await prefs.set('name', 'Ada');
      await prefs.set('sidebarWidth', 240.0);
      await prefs.dispose();

      final again = await PrefsStore.open(path);
      expect(again.get<String>('name'), 'Ada');
      expect(again.get<double>('sidebarWidth'), 240.0);
      expect(
        again.get<int>('name'),
        isNull,
        reason: 'wrong type reads as null',
      );
      await again.set('name', null);
      expect(again.get<String>('name'), isNull);
      await again.dispose();

      await File(path).writeAsString('{oops');
      final corrupt = await PrefsStore.open(path);
      expect(corrupt.get<String>('name'), isNull);
      await corrupt.dispose();
    });

    test('rejects values that are not JSON-encodable', () async {
      final prefs = await PrefsStore.open(p.join(root.path, 'prefs.json'));
      expect(
        () => prefs.set('bad', Object()),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      await prefs.dispose();
    });
  });

  group('FolderWatcher', () {
    test('reports external changes once per burst and ignores own writes and temp files', () async {
      final queue = SaveQueue();
      final watcher = FolderWatcher(
        root.path,
        isOwnWrite: queue.isRecentOwnWrite,
        usePolling: true,
        pollingDelay: const Duration(milliseconds: 50),
        debounce: const Duration(milliseconds: 100),
      );
      var events = 0;
      watcher.changes.listen((_) => events++);
      await watcher.start();

      final own = p.join(root.path, 'own.json');
      await queue.enqueue(own, () => writeFileAtomic(own, '{}'));
      await File(p.join(root.path, '.x.json.1.tmp')).writeAsString('{}');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events, 0);

      await File(p.join(root.path, 'a.json')).writeAsString('{}');
      await File(p.join(root.path, 'b.json')).writeAsString('{}');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events, 1);
      await watcher.dispose();
    });

    test(
      'a burst that never pauses still reports at least every maxWait',
      () async {
        final watcher = FolderWatcher(
          root.path,
          isOwnWrite: (_) => false,
          usePolling: true,
          pollingDelay: const Duration(milliseconds: 40),
          debounce: const Duration(milliseconds: 300),
          maxWait: const Duration(milliseconds: 400),
        );
        var events = 0;
        watcher.changes.listen((_) => events++);
        await watcher.start();
        // A sync client rewriting files faster than the debounce for ~1.6 s.
        for (var i = 0; i < 16; i++) {
          await File(p.join(root.path, 'busy.json')).writeAsString('{"i":$i}');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(events, greaterThanOrEqualTo(2));
        await watcher.dispose();
      },
    );
  });
}
