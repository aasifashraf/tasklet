import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ToastData {
  const ToastData({
    required this.id,
    required this.message,
    this.onUndo,
    this.duration = const Duration(seconds: 5),
  });

  final int id;
  final String message;
  final VoidCallback? onUndo;
  final Duration duration;
}

/// A single toast slot: a new toast replaces the previous one (SPEC §7.3).
class ToastController extends Notifier<ToastData?> {
  Timer? _timer;
  int _next = 0;

  @override
  ToastData? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(
    String message, {
    VoidCallback? onUndo,
    Duration duration = const Duration(seconds: 5),
  }) {
    _timer?.cancel();
    final toast = ToastData(
      id: _next++,
      message: message,
      onUndo: onUndo,
      duration: duration,
    );
    state = toast;
    _timer = Timer(duration, () {
      if (state?.id == toast.id) state = null;
    });
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }

  /// Runs the current toast's undo action (if any) and dismisses it.
  void undo() {
    final action = state?.onUndo;
    dismiss();
    action?.call();
  }
}

final toastProvider = NotifierProvider<ToastController, ToastData?>(
  ToastController.new,
);
