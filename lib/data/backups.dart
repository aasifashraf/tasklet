import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An earlier version of a data file, kept by [Backups].
class Backup {
  const Backup({
    required this.path,
    required this.takenAt,
    required this.bytes,
  });
  final String path;

  /// When the file was replaced by a newer version (UTC).
  final DateTime takenAt;
  final int bytes;
}

/// Local version history of one workspace's files (docs/DECISIONS.md D12).
///
/// Before a file is overwritten, its current contents are copied to `<root>/<workspace key>/<file name>/`, at most
/// once per [interval] per file, keeping the newest [keep]. It lives in the app's own data folder, not the
/// (possibly synced) workspace folder, so it doesn't sync or clutter it and survives damage to it.
class Backups {
  Backups(
    String root,
    String workspaceFolder, {
    this.interval = const Duration(minutes: 10),
    this.keep = 20,
    DateTime Function()? clock,
  }) : dir = p.join(root, _keyFor(workspaceFolder)),
       _workspaceFolder = workspaceFolder,
       _now = clock ?? DateTime.now;

  final String dir;
  final Duration interval;
  final int keep;
  final String _workspaceFolder;
  final DateTime Function() _now;

  /// A short, stable folder name for a workspace path (32-bit FNV-1a over the canonical path).
  static String _keyFor(String folder) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(p.canonicalize(folder))) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _dirFor(String file) => p.join(dir, p.basenameWithoutExtension(file));

  /// Copies [file] into the history if it exists and the newest copy is older than [interval] (or [force]).
  Future<void> beforeOverwrite(String file, {bool force = false}) async {
    final source = File(file);
    if (!await source.exists()) return;
    final existing = await list(file);
    if (!force &&
        existing.isNotEmpty &&
        _now().toUtc().difference(existing.first.takenAt) < interval) {
      return;
    }
    final target = Directory(_dirFor(file));
    await target.create(recursive: true);
    final readme = File(p.join(dir, 'workspace.txt'));
    if (!await readme.exists()) {
      await readme.writeAsString(
        'Tasklet backups of the data folder:\n$_workspaceFolder\n',
      );
    }
    final stamp = _now().toUtc().toIso8601String().replaceAll(':', '-');
    await source.copy(p.join(target.path, '$stamp.json'));
    for (final old in existing.skip(keep - 1)) {
      try {
        await File(old.path).delete();
      } on FileSystemException {
        // Pruning is best effort.
      }
    }
  }

  /// Backups of [file], newest first.
  Future<List<Backup>> list(String file) async {
    final folder = Directory(_dirFor(file));
    if (!await folder.exists()) return const [];
    final backups = <Backup>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final stem = p.basenameWithoutExtension(entity.path);
      final t = stem.indexOf('T');
      final takenAt = t < 0
          ? null
          : DateTime.tryParse(
              stem.substring(0, t) + stem.substring(t).replaceAll('-', ':'),
            );
      if (takenAt == null) continue;
      backups.add(
        Backup(
          path: entity.path,
          takenAt: takenAt,
          bytes: await entity.length(),
        ),
      );
    }
    return backups..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }
}
