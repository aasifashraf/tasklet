import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:watcher/watcher.dart';

import 'atomic_file.dart';
import 'save_queue.dart';

/// Device-local settings in one JSON file (theme, name, sidebar, reminders, per-board display, …).
///
/// Shared by the main and Settings windows, which run in separate engines — so instead of an in-memory cache per
/// engine (shared_preferences), each window watches this file and reloads when the other one writes it.
class PrefsStore {
  PrefsStore._(this.path, this._values, this._queue);

  final String path;
  final SaveQueue _queue;
  Map<String, Object?> _values;
  final _controller = StreamController<void>.broadcast();
  StreamSubscription<WatchEvent>? _watch;

  /// Opens [path]. A missing or corrupt file starts empty — device prefs are recoverable, unlike workspace data.
  static Future<PrefsStore> open(String path) async =>
      PrefsStore._(path, await _load(path), SaveQueue());

  static Future<Map<String, Object?>> _load(String path) async {
    try {
      final json = jsonDecode(await File(path).readAsString());
      return json is Map<String, Object?> ? json : {};
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  /// Emits after values change — from [set] or from another window writing the file.
  Stream<void> get changes => _controller.stream;

  T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  /// Sets [key] (null removes it) and saves. [value] must be JSON-encodable.
  Future<void> set(String key, Object? value) {
    final next = {..._values};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    final contents = encodeJson(next); // throws early if not encodable
    _values = next;
    _notify();
    return _queue.enqueue(path, () async {
      await File(path).parent.create(recursive: true);
      await writeFileAtomic(path, contents);
    });
  }

  /// Starts reloading when another process writes the file.
  Future<void> watch() async {
    if (_watch != null) return;
    final file = File(path);
    if (!await file.exists()) await set('formatVersion', 1);
    final watcher = FileWatcher(path);
    _watch = watcher.events.listen((_) async {
      if (_queue.isRecentOwnWrite(path)) return;
      _values = await _load(path);
      _notify();
    });
    await watcher.ready;
  }

  void _notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  Future<void> dispose() async {
    await _watch?.cancel();
    await _queue.drain();
    await _controller.close();
    await _queue.dispose();
  }
}
