import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_date.dart';
import '../core/reminder.dart';
import '../platform/notifications.dart';
import 'prefs.dart';
import 'workspace.dart';

/// Notification payloads: open a task, or a page.
abstract final class ReminderPayload {
  static String task(String projectId, String taskId) =>
      'task:$projectId/$taskId';
  static String route(String path) => 'route:$path';
}

/// Sends the daily due-date summary (SPEC §11.3): once per calendar day at the configured time, catching up the
/// next time it checks if the app wasn't running or the PC was asleep. "Last sent day" persists across restarts.
class ReminderService {
  ReminderService(this._container);
  final ProviderContainer _container;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
    Future<void>.delayed(const Duration(seconds: 5), check);
  }

  void dispose() => _timer?.cancel();

  Future<void> check() async {
    final prefs = _container.read(prefsProvider);
    final settings = prefs.reminders;
    final ws = _container.read(workspaceDataProvider);
    if (!settings.enabled || ws == null) return;
    final now = DateTime.now();
    if (!reminderIsDue(
      now: now,
      hour: settings.hour,
      minute: settings.minute,
      lastSentDay: prefs.lastReminderDay,
    )) {
      return;
    }
    final today = LocalDate.fromDateTime(now);
    // Mark first so a slow notification can never be sent twice.
    await _container
        .read(prefsProvider.notifier)
        .set(PrefKeys.lastReminderDay, today.toString());
    final digest = buildDigest(
      ws.activeTasks,
      today,
      includeOverdue: settings.includeOverdue,
      dayBefore: settings.dayBefore,
    );
    if (digest != null) await _send(digest);
  }

  /// "Send Test Notification": today's real content now, or a reassuring note if nothing is due (SPEC §11.3).
  Future<void> sendTest() async {
    final prefs = _container.read(prefsProvider);
    final settings = prefs.reminders;
    final ws = _container.read(workspaceDataProvider);
    final digest = ws == null
        ? null
        : buildDigest(
            ws.activeTasks,
            LocalDate.fromDateTime(DateTime.now()),
            includeOverdue: settings.includeOverdue,
            dayBefore: settings.dayBefore,
          );
    if (digest != null) {
      await _send(digest);
    } else {
      await Notifications.show(
        'Reminders are on',
        "Nothing's due right now. You'll get a summary at ${settings.timeLabel} when something is.",
        payload: ReminderPayload.route('/today'),
      );
    }
  }

  Future<void> _send(ReminderDigest digest) => Notifications.show(
    digest.title,
    digest.body,
    payload: switch (digest.singleTask) {
      final e? => ReminderPayload.task(e.project.id, e.task.id),
      null => ReminderPayload.route(
        digest.includesTodayOrOverdue ? '/today' : '/my-tasks',
      ),
    },
  );
}
