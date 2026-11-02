/// The 16 named colors shared by projects, labels, and views (SPEC §8.2; 8 more in docs/DECISIONS.md D14).
///
/// `neutral` is a deliberate "no color" choice and is never auto-assigned.
enum TaskletColor {
  blue,
  purple,
  green,
  orange,
  red,
  yellow,
  magenta,
  teal,
  cyan,
  indigo,
  pink,
  lime,
  amber,
  brown,
  slate,
  neutral;

  static TaskletColor? tryParse(Object? value) {
    for (final c in values) {
      if (c.name == value) return c;
    }
    return null;
  }

  String toJson() => name;

  /// Colors eligible for automatic assignment (everything except neutral), in rotation order.
  static const List<TaskletColor> rotation = [
    blue,
    purple,
    green,
    orange,
    red,
    yellow,
    magenta,
    teal,
    indigo,
    pink,
    lime,
    cyan,
    amber,
    brown,
    slate,
  ];

  /// The first rotation color not in [used]; cycles from the start when all are used.
  static TaskletColor nextUnused(Iterable<TaskletColor> used) {
    final counts = {for (final c in rotation) c: 0};
    for (final c in used) {
      if (counts.containsKey(c)) counts[c] = counts[c]! + 1;
    }
    final fewest = counts.values.reduce((a, b) => a < b ? a : b);
    return rotation.firstWhere((c) => counts[c] == fewest);
  }
}
