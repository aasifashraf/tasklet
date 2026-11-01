import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router.dart';
import '../state/reminders.dart';
import '../state/ui_state.dart';
import '../state/workspace.dart';
import '../ui/whats_new.dart';
import 'notifications.dart';
import 'windows.dart';

/// Handles commands that arrive from outside the main window — notification clicks and the Settings window —
/// bringing the main window to the front first (SPEC §12). The main window is never destroyed while Tasklet runs
/// (closing hides it), so commands always have a window to land in.
class AppCommands {
  AppCommands(this._container, this._reminders);
  final ProviderContainer _container;
  final ReminderService _reminders;

  void registerMainWindowHandler() {
    mainWindowChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case MainCommands.showReleaseNotes:
          await bringMainWindowToFront();
          await showWhatsNewFromAnywhere(_container);
        case MainCommands.sendTestNotification:
          await _reminders.sendTest();
          return await Notifications.allowed();
        case MainCommands.chooseFolder:
          final folder = call.arguments;
          if (folder is String) {
            await _container
                .read(workspaceProvider.notifier)
                .chooseFolder(folder);
          }
        default:
          throw MissingPluginException('Unknown command ${call.method}');
      }
      return null;
    });
  }

  /// Routes a clicked notification (SPEC §11.3): a single task opens in the detail panel; a summary opens Today
  /// or All Tasks.
  Future<void> handleNotificationTap(String? payload) async {
    if (payload == null) return;
    await bringMainWindowToFront();
    final ready = await _waitForWorkspace();
    if (!ready) return;
    if (payload.startsWith('task:')) {
      final [projectId, taskId] = payload.substring(5).split('/');
      _container
          .read(openTaskProvider.notifier)
          .open(TaskRef(projectId, taskId));
    } else if (payload.startsWith('route:')) {
      appRouter.go(payload.substring(6));
    }
  }

  /// Commands queued at startup run once the workspace has loaded rather than being dropped.
  Future<bool> _waitForWorkspace() async {
    for (var i = 0; i < 100; i++) {
      if (_container.read(workspaceDataProvider) != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }
}
