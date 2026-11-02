import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/organization.dart';
import '../router.dart';
import '../state/reminders.dart';
import '../state/ui_state.dart';
import '../state/workspace.dart';
import 'notifications.dart';
import 'windows.dart';

/// Handles commands that arrive from outside the main window (notification clicks and the Settings window),
/// bringing the main window to the front first (SPEC §12). The main window is never destroyed while Tasklet runs
/// (closing hides it), so commands always have a window to land in.
class AppCommands {
  AppCommands(this._container, this._reminders);
  final ProviderContainer _container;
  final ReminderService _reminders;

  void registerMainWindowHandler() {
    mainWindowChannel.setMethodCallHandler((call) async {
      final workspace = _container.read(workspaceProvider.notifier);
      switch (call.method) {
        case MainCommands.showReleaseNotes:
          // The main window's shell opens the sheet with its own context; don't wait for it to close.
          await bringMainWindowToFront();
          _container.read(releaseNotesRequestProvider.notifier).fire();
        case MainCommands.sendTestNotification:
          await _reminders.sendTest();
          return await Notifications.allowed();
        case MainCommands.chooseFolder:
          final folder = call.arguments;
          if (folder is String) {
            await workspace.chooseFolder(folder);
          }
        case MainCommands.switchOrganization:
          final folder = call.arguments;
          if (folder is String) {
            await bringMainWindowToFront();
            final path = appRouter.state.uri.path;
            await workspace.switchOrganization(folder);
            // A project or quick-filter page belongs to the organization just left.
            if (path.startsWith('/projects/') || path.startsWith('/views/')) {
              appRouter.go('/');
            }
          }
        case MainCommands.updateOrganization:
          if (call.arguments case {'folder': final String folder}) {
            await workspace.updateOrganization(
              folder,
              OrgInfo.fromJson(call.arguments, folderName(folder)),
            );
          }
        case MainCommands.removeOrganization:
          final folder = call.arguments;
          if (folder is String) await workspace.removeOrganization(folder);
        case MainCommands.moveOrganization:
          if (call.arguments case {
            'folder': final String folder,
            'delta': final int delta,
          }) {
            await workspace.moveOrganization(folder, delta);
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
