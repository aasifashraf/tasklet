import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/csv.dart';
import '../core/local_date.dart';
import '../core/models.dart';
import '../state/clock.dart';
import '../state/toast.dart';
import '../state/workspace.dart';

/// Export Tasks as CSV… (D17): every task in the workspace, Done and archived projects included, for a
/// spreadsheet or another app.
Future<void> exportTasksCsv(WidgetRef ref) async {
  final ws = ref.read(workspaceDataProvider);
  if (ws == null) return;
  final tasks = [
    for (final p in ws.allProjects)
      for (final t in p.tasks) ProjectTask(p, t),
  ];
  final name =
      '${ws.info.name}-${LocalDate.fromDateTime(ref.read(nowProvider))}'
          .replaceAll(RegExp(r'[<>:"/\|?*\x00-\x1F]'), '-');
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Export tasks as CSV',
    fileName: '$name.csv',
    bytes: utf8.encode(tasksToCsv(ws, tasks)),
  );
  if (uri == null) return;
  ref.read(toastProvider.notifier).show('Exported ${tasks.length} tasks.');
}

/// Import Tasks from CSV… (D17): Tasklet's export, Todoist's and Linear's CSV exports, or any file with a Title
/// column. Rows go to the project they name, else to [projectId] (the open project), else No Project.
Future<void> importTasksCsv(WidgetRef ref, {String? projectId}) async {
  final toast = ref.read(toastProvider.notifier);
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Import tasks from CSV',
    type: FileType.custom,
    allowedExtensions: const ['csv', 'txt'],
  );
  final path = picked.singleOrNull?.path;
  if (path == null) return;
  final String text;
  try {
    final file = File(path);
    if (await file.length() > 50 * 1024 * 1024) {
      toast.show("Couldn't import: the file is over 50 MB.");
      return;
    }
    text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
  } on FileSystemException catch (e) {
    toast.show("Couldn't read the file: ${e.message}.");
    return;
  }
  final tasks = importTasks(text);
  if (tasks == null) {
    toast.show(
      "Couldn't import: the file has no Title (or Name, Content) column.",
    );
    return;
  }
  final count = await ref
      .read(workspaceProvider.notifier)
      .importTasks(tasks, intoProjectId: projectId);
  toast.show(count == 1 ? 'Imported 1 task.' : 'Imported $count tasks.');
}
