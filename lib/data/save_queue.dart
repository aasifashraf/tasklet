import 'dart:async';

import 'package:path/path.dart' as p;

/// Serializes writes per file and tracks how many are in flight (SPEC §9).
///
/// - Writes to the same path run strictly in submission order, so a later save always lands last.
/// - [inFlight] lets callers skip background refreshes while this instance is saving.
/// - Recently written paths are remembered so the folder watcher can ignore the app's own writes.
class SaveQueue {
  SaveQueue({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;
  final _tails = <String, Future<void>>{};
  final _ownWrites = <String, DateTime>{};
  final _inFlightController = StreamController<int>.broadcast();
  int _inFlight = 0;

  int get inFlight => _inFlight;

  /// Emits the in-flight count whenever it changes.
  Stream<int> get inFlightChanges => _inFlightController.stream;

  static String _key(String path) => p.canonicalize(path);

  /// Runs [write] for [path] after any earlier queued write for the same path. A failure of an earlier write does
  /// not block later ones; each caller sees only its own write's error.
  Future<void> enqueue(String path, Future<void> Function() write) {
    final key = _key(path);
    _setInFlight(_inFlight + 1);
    final previous = _tails[key] ?? Future<void>.value();
    late final Future<void> tail;
    tail = previous
        .catchError((Object _) {})
        .then((_) async {
          _ownWrites[key] = _now();
          try {
            await write();
          } finally {
            _ownWrites[key] = _now();
          }
        })
        .whenComplete(() {
          _setInFlight(_inFlight - 1);
          if (identical(_tails[key], tail)) _tails.remove(key);
        });
    _tails[key] = tail;
    return tail;
  }

  /// Whether this instance wrote [path] within [window] (used to ignore watcher events caused by our own saves).
  bool isRecentOwnWrite(String path, {Duration window = const Duration(seconds: 2)}) {
    final key = _key(path);
    if (_tails.containsKey(key)) return true;
    final at = _ownWrites[key];
    return at != null && _now().difference(at) <= window;
  }

  /// Completes when every queued write has finished.
  Future<void> drain() async {
    while (_tails.isNotEmpty) {
      await Future.wait(_tails.values.map((f) => f.catchError((Object _) {})));
    }
  }

  void _setInFlight(int value) {
    _inFlight = value;
    if (!_inFlightController.isClosed) _inFlightController.add(value);
  }

  Future<void> dispose() => _inFlightController.close();
}
