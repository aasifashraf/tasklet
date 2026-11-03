import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
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

    test('$name accent: button text reads on it, and it reads as a focus ring '
        'and icon on every surface', () {
      expect(contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
      for (final bg in [t.background, t.sidebar, t.surface, t.raised]) {
        expect(contrast(t.accent, bg), greaterThanOrEqualTo(3));
      }
    });

    test('$name project and label colors read as glyphs on every surface', () {
      for (final c in TaskletColor.values) {
        for (final bg in [t.background, t.sidebar, t.surface, t.raised]) {
          expect(
            contrast(t.named(c), bg),
            greaterThanOrEqualTo(3),
            reason: '${c.name} on $bg',
          );
        }
      }
    });
  }

  test('UI code follows the house style', () {
    final problems = <String>[];
    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    for (final file in files.where((f) => f.path.endsWith('.dart'))) {
      final isTheme = file.path.endsWith('theme.dart');
      // The menu bar styles its own submenus; every other menu uses submenuItem.
      final ownsSubmenus =
          file.path.endsWith('widgets.dart') ||
          file.path.endsWith('app_menu.dart');
      for (final (i, line) in file.readAsLinesSync().indexed) {
        final where = '${file.path}:${i + 1}';
        if (line.contains('\u2014')) {
          problems.add('$where em dash (use a colon, comma or "to")');
        }
        // Spread operators (`...list`, `...?map[k]`) aren't text; drop them before looking inside strings.
        final code = line.replaceAll(RegExp(r'\.\.\.(?=[?\[{(A-Za-z_])'), '');
        if (RegExp(r'''['"][^'"]*\.\.\.[^'"]*['"]''').hasMatch(code)) {
          problems.add('$where "..." in a string (use the ellipsis character)');
        }
        if (!isTheme && line.contains('Color(0x')) {
          problems.add('$where raw color (add a token in theme.dart)');
        }
        if (!isTheme &&
            !file.path.endsWith('glyphs.dart') &&
            RegExp(r'Radius\.circular\(\d').hasMatch(line)) {
          problems.add('$where raw radius (use Radii)');
        }
        if (!isTheme && line.contains('fontSize:')) {
          problems.add('$where raw font size (use a TextStyles style)');
        }
        if (!ownsSubmenus && line.contains('SubmenuButton(')) {
          problems.add(
            '$where raw SubmenuButton (use submenuItem so it lines up)',
          );
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
