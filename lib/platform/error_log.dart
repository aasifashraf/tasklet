import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Local-only error log (`<app support>/logs/tasklet.log`, kept under ~1 MB). Nothing is ever sent anywhere; it
/// exists so a user can attach it to a bug report.
abstract final class ErrorLog {
  static File? _file;
  static const _maxBytes = 1024 * 1024;

  /// Routes uncaught Flutter and async errors to the log (and still to the console).
  static void install(String supportDir) {
    _file = File(p.join(supportDir, 'logs', 'tasklet.log'));
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, context: 'flutter');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, context: 'async');
      return true; // handled: don't crash the app over a stray async error
    };
  }

  /// The end of the log (the rotated `.1` file first), at most [maxBytes], for Export Diagnostics.
  static Future<String> recent({int maxBytes = 200 * 1024}) async {
    final file = _file;
    if (file == null) return '';
    final parts = <String>[];
    for (final f in [File('${file.path}.1'), file]) {
      try {
        if (await f.exists()) {
          parts.add(utf8.decode(await f.readAsBytes(), allowMalformed: true));
        }
      } on FileSystemException {
        // Locked or unreadable: export what we have.
      }
    }
    final all = parts.join();
    return all.length <= maxBytes ? all : all.substring(all.length - maxBytes);
  }

  static void record(Object error, StackTrace? stack, {String context = ''}) {
    debugPrint('Tasklet error ($context): $error');
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        file.renameSync('${file.path}.1');
      }
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} [$context] $error\n$stack\n\n',
        mode: FileMode.append,
      );
    } on FileSystemException {
      // Logging must never fail the app.
    }
  }
}
