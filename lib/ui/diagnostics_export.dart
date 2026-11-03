import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics.dart';
import '../core/local_date.dart';
import '../data/folder_stats.dart';
import '../platform/error_log.dart';
import '../platform/native.dart';
import '../platform/whats_new_notes.dart';
import '../state/clock.dart';
import '../state/prefs.dart';
import '../state/toast.dart';
import '../state/workspace.dart';

/// Help > Export Diagnostics…: saves a text report (versions, counts, file sizes, the error log; no task text or
/// names) for the user to attach to a bug report. Nothing is sent anywhere.
Future<void> exportDiagnostics(WidgetRef ref) async {
  final now = ref.read(nowProvider);
  final ws = ref.read(workspaceDataProvider);
  final report = diagnosticsReport(
    now: now,
    appVersion: currentRelease.version,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    dart: Platform.version,
    workspaceCount: ref.read(prefsProvider).workspaces.length,
    workspace: ws,
    syncedBy: ws == null ? null : cloudProviderFor(ws.folder),
    fileSizes: ws == null ? const {} : await workspaceFileSizes(ws.folder),
    log: await ErrorLog.recent(),
  );
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Export diagnostics',
    fileName: 'tasklet-diagnostics-${LocalDate.fromDateTime(now)}.txt',
    bytes: utf8.encode(report),
  );
  if (uri == null) return;
  ref
      .read(toastProvider.notifier)
      .show('Diagnostics saved. Attach the file to your bug report.');
}
