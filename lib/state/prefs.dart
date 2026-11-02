import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/organization.dart';
import '../core/today_rules.dart';
import '../data/prefs_store.dart';

/// Overridden in main() with the opened store.
final prefsStoreProvider = Provider<PrefsStore>(
  (ref) => throw UnimplementedError('prefsStoreProvider must be overridden'),
);

/// Primary navigation items (SPEC §3.3). Dashboard is pinned first and can't be hidden or moved.
enum NavItem {
  dashboard('Dashboard', '/', Icons.space_dashboard_outlined),
  today('Today', '/today', Icons.wb_sunny_outlined),
  allTasks('All Tasks', '/my-tasks', Icons.checklist_rounded),
  projects('Projects', '/projects', Icons.view_in_ar_outlined),
  views('Quick Filters', '/views', Icons.filter_alt_outlined),
  labels('Labels', '/labels', Icons.label_outline_rounded),
  reports('Reports', '/reports', Icons.description_outlined);

  const NavItem(this.label, this.route, this.icon);
  final String label;
  final String route;
  final IconData icon;
}

enum ThemeChoice { auto, light, dark }

class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.hour = 9,
    this.minute = 0,
    this.includeOverdue = true,
    this.dayBefore = false,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final bool includeOverdue;
  final bool dayBefore;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'includeOverdue': includeOverdue,
    'dayBefore': dayBefore,
  };

  factory ReminderSettings.fromJson(Object? v) {
    if (v is! Map<String, Object?>) return const ReminderSettings();
    return ReminderSettings(
      enabled: v['enabled'] is bool ? v['enabled']! as bool : true,
      hour: v['hour'] is int ? v['hour']! as int : 9,
      minute: v['minute'] is int ? v['minute']! as int : 0,
      includeOverdue: v['includeOverdue'] is bool
          ? v['includeOverdue']! as bool
          : true,
      dayBefore: v['dayBefore'] is bool ? v['dayBefore']! as bool : false,
    );
  }

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? includeOverdue,
    bool? dayBefore,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    includeOverdue: includeOverdue ?? this.includeOverdue,
    dayBefore: dayBefore ?? this.dayBefore,
  );
}

/// An organization on this computer: its folder and (cached) identity.
typedef OrgEntry = ({String folder, OrgInfo info});

/// Whether two paths name the same folder (case-insensitive on Windows and macOS).
bool sameFolder(String a, String b) =>
    p.canonicalize(a).toLowerCase() == p.canonicalize(b).toLowerCase();

/// The stored form of [organizations] for [PrefKeys.organizations].
List<Map<String, Object?>> encodeOrganizations(List<OrgEntry> organizations) =>
    [
      for (final o in organizations) {'folder': o.folder, ...o.info.toJson()},
    ];

/// Keys of the device-local prefs file.
abstract final class PrefKeys {
  static const dataFolder = 'dataFolder';
  static const theme = 'theme';
  static const userName = 'userName';
  static const sidebarWidth = 'sidebarWidth';
  static const navOrder = 'navOrder';
  static const navHidden = 'navHidden';
  static const collapsedSidebarSections = 'collapsedSidebarSections';
  static const dashboardProject = 'dashboardProject';
  static const projectsShowArchived = 'projectsShowArchived';
  static const labelsScope = 'labelsScope';
  static const todayRules = 'todayRules';
  static const reminders = 'reminders';
  static const lastReminderDay = 'lastReminderDay';
  static const reminderEnabledSince = 'reminderEnabledSince';
  static const whatsNewSeen = 'whatsNewSeen';
  static const recentIcons = 'recentIcons';
  static const organizations = 'organizations';
  static String boardDisplay(String boardId) => 'display:$boardId';
  static String collapsedGroups(String boardId) => 'collapsed:$boardId';
}

/// An immutable snapshot of the device prefs with typed accessors.
class Prefs {
  Prefs(this._v);
  final Map<String, Object?> _v;

  /// The raw stored value of [key].
  Object? operator [](String key) => _v[key];

  T? _get<T>(String key) => _v[key] is T ? _v[key] as T : null;
  List<String> _list(String key) => [
    if (_v[key] case final List<Object?> l)
      for (final e in l)
        if (e is String) e,
  ];

  /// The open organization's folder.
  String? get dataFolder => _get<String>(PrefKeys.dataFolder);

  /// Organizations on this computer in the user's order, each folder once (docs/DECISIONS.md D15). The open folder
  /// is always listed, so a settings file from before organizations shows it as the first organization. Names,
  /// icons and colors are a cache of each folder's marker, refreshed when it opens.
  List<OrgEntry> get organizations {
    final list = <OrgEntry>[];
    void add(String folder, OrgInfo info) {
      if (!list.any((o) => sameFolder(o.folder, folder))) {
        list.add((folder: folder, info: info));
      }
    }

    if (_v[PrefKeys.organizations] case final List<Object?> stored) {
      for (final e in stored) {
        if (e case {'folder': final String folder}) {
          add(folder, OrgInfo.fromJson(e, folderName(folder)));
        }
      }
    }
    if (dataFolder case final current?) {
      add(current, OrgInfo(name: folderName(current)));
    }
    return list;
  }

  ThemeChoice get theme => ThemeChoice.values.firstWhere(
    (t) => t.name == _v[PrefKeys.theme],
    orElse: () => ThemeChoice.auto,
  );

  String get userName => _get<String>(PrefKeys.userName) ?? '';

  double get sidebarWidth =>
      (_get<num>(PrefKeys.sidebarWidth)?.toDouble() ?? 220).clamp(190, 300);

  /// Order of the movable nav items (everything but Dashboard); unknown/missing items keep their default slot.
  List<NavItem> get navOrder {
    final stored = [
      for (final name in _list(PrefKeys.navOrder))
        for (final n in NavItem.values)
          if (n.name == name && n != NavItem.dashboard) n,
    ];
    return [
      ...stored,
      for (final n in NavItem.values.skip(1))
        if (!stored.contains(n)) n,
    ];
  }

  /// Hidden nav items; Reports is hidden by default (SPEC §3.5).
  Set<NavItem> get navHidden {
    if (_v[PrefKeys.navHidden] is! List) return {NavItem.reports};
    return {
      for (final name in _list(PrefKeys.navHidden))
        for (final n in NavItem.values)
          if (n.name == name && n != NavItem.dashboard) n,
    };
  }

  /// Visible nav items in sidebar order (Dashboard first).
  List<NavItem> get visibleNav => [
    NavItem.dashboard,
    ...navOrder.where((n) => !navHidden.contains(n)),
  ];

  /// Sidebar sections are expanded by default except Archived.
  bool sidebarSectionCollapsed(String section) {
    final stored = _v[PrefKeys.collapsedSidebarSections];
    if (stored is Map<String, Object?> && stored[section] is bool) {
      return stored[section]! as bool;
    }
    return section == 'archived';
  }

  Map<String, Object?> get collapsedSidebarSections => {
    if (_v[PrefKeys.collapsedSidebarSections] case final Map<String, Object?> m)
      ...m,
  };

  String? get dashboardProject => _get<String>(PrefKeys.dashboardProject);
  bool get projectsShowArchived =>
      _get<bool>(PrefKeys.projectsShowArchived) ?? false;
  String? get labelsScope => _get<String>(PrefKeys.labelsScope);

  Set<TodayRule> get todayRules {
    final rules = {
      for (final name in _list(PrefKeys.todayRules))
        for (final r in TodayRule.values)
          if (r.name == name) r,
    };
    return rules.isEmpty ? TodayRule.values.toSet() : rules;
  }

  ReminderSettings get reminders =>
      ReminderSettings.fromJson(_v[PrefKeys.reminders]);
  String? get lastReminderDay => _get<String>(PrefKeys.lastReminderDay);
  String? get reminderEnabledSince =>
      _get<String>(PrefKeys.reminderEnabledSince);
  String? get whatsNewSeen => _get<String>(PrefKeys.whatsNewSeen);

  /// Icons picked most recently in the icon picker, newest first (at most [maxRecentIcons]).
  List<String> get recentIcons => _list(PrefKeys.recentIcons);
  static const maxRecentIcons = 16;

  ViewDisplay? boardDisplay(String boardId) =>
      _v[PrefKeys.boardDisplay(boardId)] is Map<String, Object?>
      ? ViewDisplay.fromJson(
          _v[PrefKeys.boardDisplay(boardId)]! as Map<String, Object?>,
        )
      : null;

  Set<TaskStatus> collapsedGroups(String boardId) => {
    for (final name in _list(PrefKeys.collapsedGroups(boardId)))
      for (final s in TaskStatus.values)
        if (s.json == name) s,
  };
}

class PrefsNotifier extends Notifier<Prefs> {
  @override
  Prefs build() {
    final store = ref.watch(prefsStoreProvider);
    final sub = store.changes.listen((_) => state = Prefs(store.values));
    ref.onDispose(sub.cancel);
    return Prefs(store.values);
  }

  Future<void> set(String key, Object? value) =>
      ref.read(prefsStoreProvider).set(key, value);
}

final prefsProvider = NotifierProvider<PrefsNotifier, Prefs>(PrefsNotifier.new);
