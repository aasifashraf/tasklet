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
    bool usePolling = false,
    this.pollingDelay = const Duration(seconds: 2),
  }) : _polling = usePolling;

  final String folder;
  final Duration debounce;
  final Duration pollingDelay;
  final bool Function(String path) isOwnWrite;
  bool _polling;

  final _controller = StreamController<void>.broadcast();
  StreamSubscription<WatchEvent>? _subscription;
  Timer? _timer;

  Stream<void> get changes => _controller.stream;

  /// Completes once the watcher is ready to report changes.
  Future<void> start() async {
    final watcher = _polling
        ? PollingDirectoryWatcher(folder, pollingDelay: pollingDelay)
        : DirectoryWatcher(folder);
    _subscription = watcher.events.listen(
      _onEvent,
      onError: (Object _) => _fallBackToPolling(),
    );
    await watcher.ready;
  }

  void _onEvent(WatchEvent event) {
    if (!event.path.endsWith('.json') ||
        isTempFile(event.path) ||
        isOwnWrite(event.path)) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!_controller.isClosed) _controller.add(null);
    });
  }

  Future<void> _fallBackToPolling() async {
    if (_polling) return;
    _polling = true;
    await _subscription?.cancel();
    await start();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _subscription?.cancel();
    await _controller.close();
  }
}
