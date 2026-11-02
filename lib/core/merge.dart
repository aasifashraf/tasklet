import 'models.dart';
import 'task_ops.dart';

// Three-way merge of a project file that changed on another computer while this one had unsaved-to-disk edits
// (docs/SYSTEM_DESIGN.md section 14). `base` is the version this computer last read or wrote, `mine` the one it is
// about to save, `theirs` what is on disk now.

/// Timestamps further in the future than this are treated as "now" when deciding which edit is newer, so one
/// computer with a wrong clock can't win every conflict.
const _maxClockSkew = Duration(minutes: 5);

/// The merged project plus notes for the user (tasks deleted on one side but edited on the other).
typedef MergeResult = ({Project project, List<String> notes});

MergeResult mergeProject({
  required Project base,
  required Project mine,
  required Project theirs,
  required DateTime now,
}) {
  final notes = <String>[];
  DateTime clamp(DateTime t) => t.isAfter(now.add(_maxClockSkew)) ? now : t;
  bool mineIsNewer(DateTime m, DateTime t) => !clamp(m).isBefore(clamp(t));

  // Project fields: a change on one side wins; if both changed a field, the more recently updated side wins.
  final merged = _mergeMaps(
    base.toJson()..remove('tasks'),
    mine.toJson()..remove('tasks'),
    theirs.toJson()..remove('tasks'),
    preferMine: mineIsNewer(mine.updatedAt, theirs.updatedAt),
  );

  final baseTasks = {for (final t in base.tasks) t.id: t};
  final mineTasks = {for (final t in mine.tasks) t.id: t};
  final theirTasks = {for (final t in theirs.tasks) t.id: t};
  final tasks = <Object?>[];
  final ids = {...mineTasks.keys, ...theirTasks.keys};
  for (final id in ids) {
    final b = baseTasks[id], m = mineTasks[id], t = theirTasks[id];
    if (m != null && t != null) {
      tasks.add(
        b == null
            ? (mineIsNewer(m.updatedAt, t.updatedAt) ? m : t).toJson()
            : _mergeMaps(
                b.toJson(),
                m.toJson(),
                t.toJson(),
                preferMine: mineIsNewer(m.updatedAt, t.updatedAt),
              ),
      );
    } else if (m != null) {
      // Missing on disk: created here (keep), or deleted there (keep only if edited here since).
      if (b == null) {
        tasks.add(m.toJson());
      } else if (!jsonEquals(b.toJson(), m.toJson())) {
        tasks.add(m.toJson());
        notes.add(
          '"${m.title}" was deleted on another computer after you changed it here; your version was kept.',
        );
      }
    } else if (t != null) {
      // Missing here: created there (keep), or deleted here (keep only if edited there since).
      if (b == null) {
        tasks.add(t.toJson());
      } else if (!jsonEquals(b.toJson(), t.toJson())) {
        tasks.add(t.toJson());
        notes.add(
          '"${t.title}" was changed on another computer after you deleted it here; it was kept.',
        );
      }
    }
  }
  // Entries this version can't read are kept from both sides (by id when they have one).
  final opaque = <Object?>[...theirs.opaqueTasks];
  final opaqueIds = {
    for (final o in opaque)
      if (o case {'id': final String id}) id,
  };
  for (final o in mine.opaqueTasks) {
    if (o case {'id': final String id} when opaqueIds.contains(id)) continue;
    opaque.add(o);
  }

  final next = [
    mine.nextNumber,
    theirs.nextNumber,
    base.nextNumber,
  ].reduce((a, b) => a > b ? a : b);
  var project = Project.fromJson({
    ...merged,
    'nextNumber': next,
    'updatedAt': (mineIsNewer(mine.updatedAt, theirs.updatedAt) ? mine : theirs)
        .updatedAt
        .toUtc()
        .toIso8601String(),
    'tasks': [...tasks, ...opaque],
  });
  // Both computers may have created a task with the same next number.
  project = resolveDuplicateNumbers(project) ?? project;
  return (project: project, notes: notes);
}

/// Field-by-field three-way merge of JSON objects: a value changed on one side wins; changed on both, [preferMine]
/// decides. Unknown fields from newer versions merge the same way.
Map<String, Object?> _mergeMaps(
  Map<String, Object?> base,
  Map<String, Object?> mine,
  Map<String, Object?> theirs, {
  required bool preferMine,
}) {
  final result = <String, Object?>{};
  for (final key in {...base.keys, ...mine.keys, ...theirs.keys}) {
    final b = base[key], m = mine[key], t = theirs[key];
    final mineChanged = !jsonEquals(b, m);
    final theirsChanged = !jsonEquals(b, t);
    final value = mineChanged && theirsChanged
        ? (preferMine ? m : t)
        : (mineChanged ? m : t);
    final present = mineChanged && theirsChanged
        ? (preferMine ? mine.containsKey(key) : theirs.containsKey(key))
        : (mineChanged ? mine.containsKey(key) : theirs.containsKey(key));
    if (present) result[key] = value;
  }
  return result;
}

/// Deep equality of decoded JSON values (maps, lists, scalars).
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !jsonEquals(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
