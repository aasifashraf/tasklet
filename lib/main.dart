import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/prefs_store.dart';
import 'platform/app_commands.dart';
import 'platform/error_log.dart';
import 'platform/lifecycle.dart';
import 'platform/notifications.dart';
import 'platform/windows.dart';
import 'state/prefs.dart';
import 'state/reminders.dart';
import 'state/workspace.dart';
import 'ui/settings/settings_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Non-sandboxed on macOS (docs/DECISIONS.md D10).
  if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();

  final support = await getApplicationSupportDirectory();
  ErrorLog.install(support.path);
  final prefs = await PrefsStore.open(p.join(support.path, 'settings.json'));
  await prefs.watch();
  final overrides = [prefsStoreProvider.overrideWithValue(prefs)];

  // The Settings window runs in its own engine (SPEC §11).
  if (isSettingsWindow(args)) {
    runApp(ProviderScope(overrides: overrides, child: const SettingsApp()));
    return;
  }

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(900, 600),
    center: true,
    title: 'Tasklet',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final container = ProviderContainer(overrides: overrides);
  final reminders = ReminderService(container);
  final commands = AppCommands(container, reminders)
    ..registerMainWindowHandler();
  // The tray and notifications are optional: a failure there must never leave the window blank.
  try {
    await AppLifecycle.instance.init();
  } catch (e, s) {
    ErrorLog.record(e, s, context: 'tray');
  }
  try {
    await Notifications.init(commands.handleNotificationTap);
  } catch (e, s) {
    ErrorLog.record(e, s, context: 'notifications');
  }
  reminders.start();
  // Quitting waits (briefly) for pending saves so the last edit isn't lost.
  AppLifecycle.instance.beforeQuit.add(
    () => container.read(workspaceProvider.notifier).flushSaves(),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const TaskletApp()),
  );
}
