import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/ui/icons/project_icons.dart';

/// The icon catalog for projects and labels (tool/icons/catalog.txt, docs/DECISIONS.md D14).
void main() {
  final all = {
    for (final c in iconCategories)
      for (final i in c.icons) i.name: i,
  };

  test('a large, project-related catalog where every name resolves', () {
    expect(all.length, greaterThanOrEqualTo(600));
    expect(iconCategories.length, 14);
    for (final c in iconCategories) {
      expect(c.icons, isNotEmpty, reason: c.name);
      expect(c.icons.map((i) => i.name).toSet().length, c.icons.length);
    }
    for (final name in all.keys) {
      expect(iconFor(name)?.name, name);
    }
    // The same name always means the same glyph.
    for (final c in iconCategories) {
      for (final i in c.icons) {
        expect(i.data, all[i.name]!.data, reason: i.name);
        expect(i.data.fontFamily, 'Lucide');
      }
    }
  });

  test('none and unknown names have no icon', () {
    expect(iconFor(null), isNull);
    expect(iconFor('quantum-widget'), isNull);
  });

  test('search finds by name, tag and category, name matches first', () {
    expect(searchIcons(''), isEmpty);
    expect(searchIcons('rocket').first.name, 'rocket');
    final money = searchIcons('money').map((i) => i.name);
    expect(money, contains('wallet'));
    expect(
      searchIcons('git branch').map((i) => i.name),
      contains('git-branch'),
    );
    expect(searchIcons('zzzz'), isEmpty);
    final names = searchIcons('chart').map((i) => i.name).toList();
    expect(names.toSet().length, names.length, reason: 'each icon once');
    expect(names.first, startsWith('chart'));
  });
}
