import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const _encoder = JsonEncoder.withIndent('  ');

/// Pretty-printed JSON with a trailing newline, friendly to diff tools and sync clients.
String encodeJson(Object? value) => '${_encoder.convert(value)}\n';

/// Exactly the UTF-8 bytes of [encodeJson] for [head] with its [listKey] set to [items] (each turned into JSON by
/// [itemJson]), built a few items at a time with a pause between them, so encoding a huge file (a 20,000-task
/// project) never blocks the UI isolate for more than a few milliseconds. Unlike an isolate, it doesn't have to
/// copy the whole object graph first.
Future<List<Uint8List>> encodeJsonInSlices<T>(
  Map<String, Object?> head,
  String listKey,
  List<T> items,
  Object? Function(T item) itemJson, {
  int slice = 250,
}) async {
  // The list is spliced in where a placeholder lands: a top-level key, so at the two-space indent, which no nested
  // value can produce.
  const placeholder = '\u0000tasklet-slices\u0000';
  final encodedHead = encodeJson({...head, listKey: placeholder});
  final marker = '\n  ${jsonEncode(listKey)}: ';
  final at = encodedHead.indexOf('$marker${jsonEncode(placeholder)}');
  // Kept as parts, never joined: one 44 MB buffer would mean big copies on this isolate.
  final out = <Uint8List>[
    utf8.encode(encodedHead.substring(0, at + marker.length)),
  ];
  if (items.isEmpty) {
    out.add(utf8.encode('[]'));
  } else {
    out.add(utf8.encode('[\n'));
    for (var start = 0; start < items.length; start += slice) {
      final end = min(start + slice, items.length);
      final part = StringBuffer();
      for (var i = start; i < end; i++) {
        // Raw newlines in pretty JSON are all structural (strings escape theirs), so indenting is safe.
        part
          ..write('    ')
          ..write(
            _encoder.convert(itemJson(items[i])).replaceAll('\n', '\n    '),
          )
          ..write(i < items.length - 1 ? ',\n' : '\n');
      }
      out.add(utf8.encode(part.toString()));
      await Future<void>.delayed(Duration.zero);
    }
    out.add(utf8.encode('  ]'));
  }
  out.add(
    utf8.encode(
      encodedHead.substring(
        at + marker.length + jsonEncode(placeholder).length,
      ),
    ),
  );
  return out;
}

final _random = Random();

/// Whether [path] is a temp file created by [writeFileAtomic].
bool isTempFile(String path) => p.basename(path).endsWith('.tmp');

/// Writes [contents] to a temp file next to [path], flushes it, then renames it over [path] (SPEC §2.5).
/// A crash or a sync client reading mid-save never sees a half-written file.
Future<void> writeFileAtomic(String path, String contents) =>
    writeBytesAtomic(path, [utf8.encode(contents)]);

/// [writeFileAtomic] for content that is already UTF-8 bytes.
Future<void> writeBytesAtomic(String path, List<Uint8List> parts) async {
  final tmp = File(
    p.join(
      p.dirname(path),
      '.${p.basename(path)}.${_random.nextInt(1 << 32).toRadixString(36)}.tmp',
    ),
  );
  try {
    final file = await tmp.open(mode: FileMode.writeOnly);
    try {
      // A part at a time (at most 1 MB per call): each async write copies its bytes for the IO thread.
      for (final part in parts) {
        for (var i = 0; i < part.length; i += 1 << 20) {
          await file.writeFrom(part, i, min(i + (1 << 20), part.length));
        }
      }
      await file.flush();
    } finally {
      await file.close();
    }
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
