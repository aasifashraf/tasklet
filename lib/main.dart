import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/prefs_store.dart';
import 'state/prefs.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Non-sandboxed on macOS (docs/DECISIONS.md D10).
  if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
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

  final support = await getApplicationSupportDirectory();
  final prefs = await PrefsStore.open(p.join(support.path, 'settings.json'));
  await prefs.watch();

  runApp(
    ProviderScope(
      overrides: [prefsStoreProvider.overrideWithValue(prefs)],
      child: const TaskletApp(),
    ),
  );
}
