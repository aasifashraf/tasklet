import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/ui/theme.dart';

/// Guards for the design system (docs/DESIGN_SYSTEM.md): readable text tokens and house style in UI strings.
void main() {
  double contrast(Color fg, Color bg) {
    final over = Color.alphaBlend(fg, bg);
    final a = over.computeLuminance(), b = bg.computeLuminance();
    final (hi, lo) = a > b ? (a, b) : (b, a);
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final (name, t) in [('light', Tokens.light), ('dark', Tokens.dark)]) {
    test('$name text tokens are readable on every surface', () {
      for (final bg in [t.background, t.sidebar, t.surface, t.raised]) {
        expect(contrast(t.primary, bg), greaterThanOrEqualTo(7));
        expect(contrast(t.secondary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(t.tertiary, bg), greaterThanOrEqualTo(3));
      }
    });
  }

  test('UI code follows the house style', () {
    final problems = <String>[];
    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    for (final file in files.where((f) => f.path.endsWith('.dart'))) {
      final isTheme = file.path.endsWith('theme.dart');
      for (final (i, line) in file.readAsLinesSync().indexed) {
        final where = '${file.path}:${i + 1}';
        if (line.contains('—')) {
          problems.add('$where em dash (use a colon, comma or "to")');
        }
        if (RegExp(r'''['"][^'"]*\.\.\.[^'"]*['"]''').hasMatch(line) &&
            !line.contains('...[')) {
          problems.add('$where "..." in a string (use the ellipsis character)');
        }
        if (!isTheme && line.contains('Color(0x')) {
          problems.add('$where raw color (add a token in theme.dart)');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
