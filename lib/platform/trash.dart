import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

const _channel = MethodChannel('tasklet/native');

/// Moves [path] to the Recycle Bin (Windows) or Trash (macOS). Returns false — without deleting anything — when
/// the file's volume can't hold it there, so the caller can fall back to a recoverable location.
Future<bool> moveToOsTrash(String path) async {
  if (Platform.isWindows) return _recycleWindows(path);
  if (Platform.isMacOS) {
    try {
      return await _channel.invokeMethod<bool>('trashItem', path) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
  return false;
}

/// Only fixed local drives have a Recycle Bin. On network, removable, and unknown drives SHFileOperation silently
/// deletes permanently even with FOF_ALLOWUNDO, so those are refused up front.
bool _recycleWindows(String path) {
  final absolute = p.absolute(path);
  return using((arena) {
    final root = p.rootPrefix(absolute);
    if (win32.GetDriveType(
          win32.PCWSTR(root.toNativeUtf16(allocator: arena)),
        ) !=
        win32.DRIVE_FIXED) {
      return false;
    }

    final op = arena<win32.SHFILEOPSTRUCT>();
    op.ref
      ..wFunc = win32.FO_DELETE
      // pFrom must be double-null terminated; toNativeUtf16 adds the second terminator.
      ..pFrom = win32.PWSTR('$absolute\u0000'.toNativeUtf16(allocator: arena))
      ..pTo = win32.PWSTR(nullptr.cast())
      ..fFlags =
          win32.FOF_ALLOWUNDO |
          win32.FOF_NOCONFIRMATION |
          win32.FOF_SILENT |
          win32.FOF_NOERRORUI;
    final result = win32.SHFileOperation(op);
    return result.value == 0 && !op.ref.fAnyOperationsAborted;
  });
}
