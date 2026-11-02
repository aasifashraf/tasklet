import 'package:flutter/widgets.dart';

part 'project_icons.g.dart';

// Icons for projects and labels (docs/DECISIONS.md D14): a curated set of Lucide icons by category. Edit
// tool/icons/catalog.txt and run `python -I tool/icons/gen_catalog.py`. Every entry is a const IconData, so release
// builds keep only these glyphs of the icon font.

class ProjectIcon {
  const ProjectIcon(this.name, this.data, this.keywords);

  /// The Lucide name stored in the data files ("rocket").
  final String name;
  final IconData data;

  /// Lowercase search text: the name, Lucide's tags and the category.
  final String keywords;
}

class IconCategory {
  const IconCategory(this.name, this.icons);
  final String name;
  final List<ProjectIcon> icons;
}

final Map<String, ProjectIcon> _byName = {
  for (final c in iconCategories)
    for (final i in c.icons) i.name: i,
};

/// The icon for a stored name, or null for none or a name this version doesn't have (drawn as the default glyph).
ProjectIcon? iconFor(String? name) => name == null ? null : _byName[name];

/// Icons whose name, tags or category contain every word of [query], each once, best matches first: name starts
/// with the query, then name contains it, then the rest.
List<ProjectIcon> searchIcons(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return const [];
  final q = words.join('-');
  int rank(ProjectIcon i) =>
      i.name.startsWith(q) ? 0 : (i.name.contains(q) ? 1 : 2);
  final matches = [
    for (final i in _byName.values)
      if (words.every(i.keywords.contains)) i,
  ];
  // List.sort isn't stable; break ties by catalog order.
  final order = {for (final (n, i) in matches.indexed) i: n};
  return matches..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : order[a]!.compareTo(order[b]!);
  });
}
