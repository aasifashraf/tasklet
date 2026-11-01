import 'models.dart';

// Project keys & task IDs (SPEC §2.4).

final _letter = RegExp('[A-Za-z]');
final _trailingDigits = RegExp(r'\d+$');

/// First 3 letters of [name] (everything else stripped), uppercased; `PRJ` when there are none.
String baseKeyFor(String name) {
  final letters = _letter
      .allMatches(name)
      .take(3)
      .map((m) => m[0]!)
      .join()
      .toUpperCase();
  return letters.isEmpty ? 'PRJ' : letters;
}

/// [base] if free, otherwise [base]1, [base]2, … — the first not in [taken]. `TSK` is always taken.
String nextFreeKey(String base, Set<String> taken) {
  bool isTaken(String k) => k == noProjectKey || taken.contains(k);
  if (!isTaken(base)) return base;
  for (var i = 1; ; i++) {
    final candidate = '$base$i';
    if (!isTaken(candidate)) return candidate;
  }
}

/// The key a brand-new project named [name] would get, given the existing [projects] (used for the live
/// "Task IDs: WEB-1" preview and on creation).
String keyForNewProject(String name, Iterable<Project> projects) =>
    nextFreeKey(baseKeyFor(name), {for (final p in projects) p.key});

/// Resolves every project's key for a full workspace read.
///
/// Keys are sticky: a project keeps its stored key unless another project created earlier claims the same one
/// (or it collides with the reserved `TSK`), in which case it gets the next free suffix of its base. Projects with
/// no stored key (legacy files) get one from their name. Processing in `createdAt` order makes the oldest project
/// win every contest, so offline-created duplicates self-heal once synced.
///
/// Returns only the projects whose key changed (id → new key); callers persist those.
Map<String, String> resolveProjectKeys(Iterable<Project> projects) {
  final ordered = [...projects.where((p) => !p.isNoProject)]
    ..sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  final taken = <String>{};
  final changed = <String, String>{};
  for (final project in ordered) {
    final stored = project.key.trim().toUpperCase();
    final String key;
    if (stored.isNotEmpty &&
        stored != noProjectKey &&
        !taken.contains(stored)) {
      key = stored;
    } else {
      final base = stored.isEmpty
          ? baseKeyFor(project.name)
          : stored.replaceFirst(_trailingDigits, '');
      key = nextFreeKey(base.isEmpty ? 'PRJ' : base, taken);
    }
    taken.add(key);
    if (key != project.key) changed[project.id] = key;
  }
  return changed;
}
