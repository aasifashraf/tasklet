import 'dart:async';

import 'package:watcher/watcher.dart';

import 'atomic_file.dart';

/// Watches the data folder for changes made by other processes (sync clients, another Tasklet) and emits one
/// debounced event per burst (SPEC §9). Events for the app's own recent writes and for temp files are ignored.
/// Falls back to polling if the native watcher fails (common on network and some cloud-sync folders).
class FolderWatcher {
  FolderWatcher(
    this.folder, {
    required this.isOwnWrite,
    this.debounce = const Duration(milliseconds: 300),
    this.maxWait = const Duration(seconds: 2),
    bool usePolling = false,
    this.pollingDelay = const Duration(seconds: 2),
  }) : _polling = usePolling;

  final String folder;
  final Duration debounce;

  /// A burst that never pauses (a sync client touching many files) still reports at least this often.
  final Duration maxWait;
  final Duration pollingDelay;
  final bool Function(String path) isOwnWrite;
  bool _polling;
  bool _disposed = false;

  final _controller = StreamController<void>.broadcast();
  StreamSubscription<WatchEvent>? _subscription;
  Timer? _timer;
  final _sinceFirstPending = Stopwatch();

  Stream<void> get changes => _controller.stream;

  /// Completes once the watcher is ready to report changes.
  Future<void> start() async {
    final watcher = _polling
        ? PollingDirectoryWatcher(folder, pollingDelay: pollingDelay)
        : DirectoryWatcher(folder);
    _subscription = watcher.events.listen(
      _onEvent,
      onError: (Object _) => unawaited(_fallBackToPolling()),
    );
    await watcher.ready;
  }

  void _onEvent(WatchEvent event) {
    if (!event.path.endsWith('.json') ||
        isTempFile(event.path) ||
        isOwnWrite(event.path)) {
      return;
    }
    if (!_sinceFirstPending.isRunning) _sinceFirstPending.start();
    _timer?.cancel();
    _timer = Timer(
      _sinceFirstPending.elapsed >= maxWait ? Duration.zero : debounce,
      _emit,
    );
  }

  void _emit() {
    _sinceFirstPending
      ..stop()
      ..reset();
    if (!_controller.isClosed) _controller.add(null);
  }

  Future<void> _fallBackToPolling() async {
    if (_polling || _disposed) return;
    _polling = true;
    await _subscription?.cancel();
    if (_disposed) return;
    try {
      await start();
    } catch (_) {
      // Polling couldn't start either; window focus still refreshes.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    await _controller.close();
  }
}
