import 'dart:io';

import 'package:path/path.dart' as p;

/// Sizes of the files in a workspace folder and its `projects/` folder, by path relative to the folder (for
/// Help > Export Diagnostics). Project files are named by their random ids, so no names leave the computer.
/// Unreadable entries are skipped; a missing folder gives an empty map.
Future<Map<String, int>> workspaceFileSizes(String folder) async {
  final sizes = <String, int>{};
  Future<void> scan(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      try {
        sizes[p.relative(entry.path, from: folder).replaceAll(r'\', '/')] =
            await entry.length();
      } on FileSystemException {
        // Mid-sync or locked: leave it out.
      }
    }
  }

  await scan(Directory(folder));
  await scan(Directory(p.join(folder, 'projects')));
  return sizes;
}
