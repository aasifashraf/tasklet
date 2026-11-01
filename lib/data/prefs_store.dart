import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:watcher/watcher.dart';

import 'atomic_file.dart';
import 'save_queue.dart';

/// Device-local settings in one JSON file (theme, name, sidebar, reminders, per-board display, …).
///
/// Shared by the main and Settings windows, which run in separate engines, so instead of an in-memory cache per
/// engine (shared_preferences), each window watches this file and reloads when the other one writes it. Every save
/// re-reads the file and changes only its own key, so two windows saving at once never undo each other.
class PrefsStore {
  PrefsStore._(this.path, this._values, this._queue);

  final String path;
  final SaveQueue _queue;
  Map<String, Object?> _values;
  final _controller = StreamController<void>.broadcast();
  StreamSubscription<WatchEvent>? _watch;
  Future<void> _reloading = Future.value();

  /// Opens [path]. A missing or corrupt file starts empty: device prefs are recoverable, unlike workspace data. A
  /// corrupt file is kept next to it as `<name>.corrupt` before anything overwrites it.
  static Future<PrefsStore> open(String path) async {
    var values = await _tryLoad(path);
    if (values == null) {
      values = {};
      try {
        await File(path).copy('$path.corrupt');
      } on FileSystemException {
        // Missing (first run) or unreadable: nothing to keep.
      }
    }
    return PrefsStore._(path, values, SaveQueue());
  }

  /// The file's values, `{}` if it doesn't exist, or null if it can't be read or parsed right now.
  static Future<Map<String, Object?>?> _tryLoad(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Emits after values change, from [set] or from another window writing the file.
  Stream<void> get changes => _controller.stream;

  /// A snapshot of every value.
  Map<String, Object?> get values => Map.unmodifiable(_values);

  T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  static Map<String, Object?> _with(
    Map<String, Object?> values,
    String key,
    Object? value,
  ) {
    final next = {...values};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return next;
  }

  /// Sets [key] (null removes it) and saves. [value] must be JSON-encodable.
  Future<void> set(String key, Object? value) {
    jsonEncode(value); // throws early if not encodable
    _values = _with(_values, key, value);
    _notify();
    return _queue.enqueue(path, () async {
      // Merge into what's on disk now: the other window may have saved a different key since we last read it.
      final onDisk = await _tryLoad(path);
      final merged = onDisk == null ? _values : _with(onDisk, key, value);
      await File(path).parent.create(recursive: true);
      await writeFileAtomic(path, encodeJson(merged));
      // Keys the other window added reach memory through the watcher, once no save of ours is pending.
    });
  }

  /// Starts reloading when another process writes the file.
  Future<void> watch() async {
    if (_watch != null) return;
    final file = File(path);
    if (!await file.exists()) await set('formatVersion', 1);
    final watcher = FileWatcher(path);
    _watch = watcher.events.listen(
      (_) => _reloading = _reloading.then((_) => _reload()),
    );
    await watcher.ready;
  }

  Future<void> _reload() async {
    // A queued save of ours will land shortly and trigger its own event; reading now could undo it in memory.
    if (_queue.isRecentOwnWrite(path, window: Duration.zero)) return;
    var loaded = await _tryLoad(path);
    if (loaded == null) {
      // Briefly locked by the other window's rename or an antivirus scan: try once more, else keep what we have.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      loaded = await _tryLoad(path);
      if (loaded == null) return;
    }
    if (jsonEncode(loaded) == jsonEncode(_values)) return;
    _values = loaded;
    _notify();
  }

  void _notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  Future<void> dispose() async {
    await _watch?.cancel();
    await _reloading;
    await _queue.drain();
    await _controller.close();
    await _queue.dispose();
  }
}
