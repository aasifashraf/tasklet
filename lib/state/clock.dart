import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_date.dart';

/// The current time, re-evaluated every 30 seconds and whenever the app resumes (SPEC §9), so relative dates,
/// overdue cues, Today and the Dashboard roll over at midnight without a restart. Never call `DateTime.now()` in
/// widgets; watch this (or [todayProvider]) instead.
class NowNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    final lifecycle = AppLifecycleListener(onResume: tick, onShow: tick);
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
    return DateTime.now();
  }

  /// Re-reads the clock (also called on window focus and OS wake).
  void tick() => state = DateTime.now();
}

final nowProvider = NotifierProvider<NowNotifier, DateTime>(NowNotifier.new);

/// Today's local date; only notifies when the date actually changes.
final todayProvider = Provider<LocalDate>(
  (ref) => ref.watch(nowProvider.select(LocalDate.fromDateTime)),
);
