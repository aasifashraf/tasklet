import 'colors.dart';

/// An organization is one data folder (docs/DECISIONS.md D15). Its name, icon and color live in that folder's
/// marker file (`tasklet-workspace.json`), so they sync with the folder.
class OrgInfo {
  const OrgInfo({
    required this.name,
    this.icon = defaultIcon,
    this.color = TaskletColor.blue,
  });

  static const defaultIcon = 'building-2';
  static const maxNameLength = 60;

  /// Reads the identity from a marker's JSON. Anything missing or invalid falls back: the name to [folderName], so
  /// a folder from before organizations shows under its own name.
  factory OrgInfo.fromMarker(Map<String, Object?>? marker, String folderName) {
    final name = marker?['name'];
    final icon = marker?['icon'];
    return OrgInfo(
      name: name is String && name.trim().isNotEmpty ? name.trim() : folderName,
      // Missing: the default icon; null: the user picked the plain cube.
      icon: icon is String
          ? icon
          : (marker?.containsKey('icon') ?? false ? null : defaultIcon),
      color: TaskletColor.tryParse(marker?['color']) ?? TaskletColor.blue,
    );
  }

  /// Device prefs keep the same fields as the marker (a cache for the switcher).
  factory OrgInfo.fromJson(Object? json, String folderName) =>
      OrgInfo.fromMarker(
        json is Map<String, Object?> ? json : null,
        folderName,
      );

  final String name;

  /// A project-icon name (lib/ui/icons); null shows the plain cube.
  final String? icon;
  final TaskletColor color;

  OrgInfo copyWith({
    String? name,
    String? icon,
    bool clearIcon = false,
    TaskletColor? color,
  }) => OrgInfo(
    name: name ?? this.name,
    icon: clearIcon ? null : (icon ?? this.icon),
    color: color ?? this.color,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'icon': icon,
    'color': color.toJson(),
  };

  /// [marker] with only the fields that differ from [before] replaced, so values from a newer version (an unknown
  /// color, other keys) survive a rename.
  Map<String, Object?> applyTo(Map<String, Object?> marker, OrgInfo before) {
    final result = {...marker};
    if (name != before.name) result['name'] = name;
    if (icon != before.icon) result['icon'] = icon;
    if (color != before.color) result['color'] = color.toJson();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is OrgInfo &&
      other.name == name &&
      other.icon == icon &&
      other.color == color;

  @override
  int get hashCode => Object.hash(name, icon, color);
}

/// The last part of a folder path ("D:\Work\Acme" → "Acme"), for an organization without a stored name.
String folderName(String path) {
  final parts = path.split(RegExp(r'[\\/]'))..removeWhere((s) => s.isEmpty);
  return parts.isEmpty ? path : parts.last;
}
