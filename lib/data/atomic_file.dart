import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

const _encoder = JsonEncoder.withIndent('  ');

/// Pretty-printed JSON with a trailing newline — friendly to diff tools and sync clients.
String encodeJson(Object? value) => '${_encoder.convert(value)}\n';

final _random = Random();

/// Whether [path] is a temp file created by [writeFileAtomic].
bool isTempFile(String path) => p.basename(path).endsWith('.tmp');

/// Writes [contents] to a temp file next to [path], flushes it, then renames it over [path] (SPEC §2.5).
/// A crash or a sync client reading mid-save never sees a half-written file.
Future<void> writeFileAtomic(String path, String contents) async {
  final tmp = File(p.join(p.dirname(path), '.${p.basename(path)}.${_random.nextInt(1 << 32).toRadixString(36)}.tmp'));
  await tmp.writeAsString(contents, flush: true);
  try {
    await _renameWithRetry(tmp, path);
  } catch (_) {
    try {
      await tmp.delete();
    } on FileSystemException {
      // Best effort; a leftover .tmp file is ignored by readers.
    }
    rethrow;
  }
}

/// On Windows a rename can fail briefly while a sync client or antivirus holds the target open.
Future<void> _renameWithRetry(File tmp, String path) async {
  for (var attempt = 0; ; attempt++) {
    try {
      await tmp.rename(path);
      return;
    } on FileSystemException {
      if (attempt >= 5) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 40 << attempt));
    }
  }
}
