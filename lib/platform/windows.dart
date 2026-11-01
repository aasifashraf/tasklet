import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Messages from the Settings window to the main window (each window runs its own engine). One-to-many: the main
/// window registers the handler and any window may call it (the default "paired" mode only lets two windows that
/// both registered talk to each other).
const mainWindowChannel = WindowMethodChannel(
  'tasklet/main',
  mode: ChannelMode.unidirectional,
);

/// Commands the main window accepts over [mainWindowChannel].
abstract final class MainCommands {
  static const showReleaseNotes = 'showReleaseNotes';
  static const sendTestNotification = 'sendTestNotification';
  static const chooseFolder = 'chooseFolder';
}

const _settingsArgument = 'settings';

/// Whether this engine is the Settings window (`main()` receives `["multi_window", id, argument]` there).
bool isSettingsWindow(List<String> args) =>
    args.length >= 3 &&
    args[0] == 'multi_window' &&
    args[2] == _settingsArgument;

/// Opens the Settings window, or brings it forward if it's already open (SPEC §11).
Future<void> openSettingsWindow() async {
  for (final window in await WindowController.getAll()) {
    if (window.arguments == _settingsArgument) {
      await window.show();
      return;
    }
  }
  await WindowController.create(
    const WindowConfiguration(
      arguments: _settingsArgument,
      hiddenAtLaunch: false,
    ),
  );
}

/// Brings the main window to the front (it may be hidden in the tray).
Future<void> bringMainWindowToFront() async {
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.show();
  await windowManager.focus();
}

/// Sends [method] to the main window from the Settings window.
Future<T?> sendToMainWindow<T>(String method, [Object? arguments]) async {
  try {
    return await mainWindowChannel.invokeMethod<T>(method, arguments);
  } on WindowChannelException {
    return null; // main window not ready
  } on MissingPluginException {
    return null;
  }
}
