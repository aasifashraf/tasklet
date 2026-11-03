import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/merge.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

/// Randomized checks of the two-computer merge (docs/DECISIONS.md D13): each round edits, deletes and creates
/// tasks on both sides of a random project, merges, and checks rules that must hold for every input.
void main() {
  const rounds = 300;
  final now = t0.add(const Duration(days: 1));

  Map<String, Object?> json(Task t) => t.toJson();
  Map<String, Task> byId(Project p) => {for (final t in p.tasks) t.id: t};

  Project randomBase(Random r) {
    final n = r.nextInt(12) + 1;
    return project(
      'p',
      nextNumber: n + 1,
      tasks: [
        for (var i = 0; i < n; i++)
          task(
            'b$i',
            number: i + 1,
            title: 'Task $i',
            status: TaskStatus.values[r.nextInt(TaskStatus.values.length)],
            updated: at(i),
          ),
      ],
    );
  }

  /// One computer's edits: change fields of some tasks, delete some, create some (numbers from its own counter,
  /// so both sides can pick the same number).
  Project edit(Random r, Project base, String side, int minute) {
    var next = base.nextNumber;
    final tasks = <Task>[];
    for (final t in base.tasks) {
      final roll = r.nextInt(10);
      if (roll == 0) continue; // deleted
      if (roll < 4) {
        final j = json(t);
        switch (r.nextInt(4)) {
          case 0:
            j['title'] = '${t.title} ($side)';
          case 1:
            j['priority'] =
                Priority.values[r.nextInt(Priority.values.length)].value;
          case 2:
            j['dueDate'] =
                '2026-11-${(r.nextInt(28) + 1).toString().padLeft(2, '0')}';
          default:
            j['description'] = 'note from $side';
        }
        j['updatedAt'] = at(minute + r.nextInt(30)).toUtc().toIso8601String();
        tasks.add(Task.fromJson(j));
      } else {
        tasks.add(t);
      }
    }
    for (var i = r.nextInt(3); i > 0; i--) {
      tasks.add(
        task(
          '$side${next}_$minute',
          number: next++,
          title: 'New on $side',
          updated: at(minute),
        ),
      );
    }
    return Project.fromJson({
      ...base.toJson(),
      'nextNumber': next,
      'updatedAt': at(minute).toUtc().toIso8601String(),
      'tasks': [for (final t in tasks) t.toJson()],
    });
  }

  test('one side unchanged: the result is the other side', () {
    final r = Random(1);
    for (var i = 0; i < rounds; i++) {
      final base = randomBase(r);
      final changed = edit(r, base, 'm', 100);
      for (final (mine, theirs) in [(changed, base), (base, changed)]) {
        final merged = mergeProject(
          base: base,
          mine: mine,
          theirs: theirs,
          now: now,
        ).project;
        expect(
          {for (final t in merged.tasks) t.id: json(t)},
          {for (final t in changed.tasks) t.id: json(t)},
          reason: 'round $i',
        );
      }
    }
  });

  test('ids, one-sided fields, unique numbers, determinism', () {
    final r = Random(2);
    for (var i = 0; i < rounds; i++) {
      final base = randomBase(r);
      final mine = edit(r, base, 'm', 100);
      final theirs = edit(r, base, 't', 200);
      MergeResult run() =>
          mergeProject(base: base, mine: mine, theirs: theirs, now: now);
      final merged = run().project;
      final b = byId(base),
          m = byId(mine),
          t = byId(theirs),
          out = byId(merged);
      final reason = 'round $i';

      // Ids: nothing from nowhere; creations kept; deletions honored unless the other side edited the task.
      expect(out.keys.toSet().difference({...m.keys, ...t.keys}), isEmpty);
      for (final id in {...m.keys, ...t.keys}.difference(b.keys.toSet())) {
        expect(out, contains(id), reason: '$reason: created $id kept');
      }
      for (final id in b.keys) {
        final inM = m.containsKey(id), inT = t.containsKey(id);
        if (inM && inT) {
          expect(out, contains(id), reason: reason);
        } else if (inM != inT) {
          final other = inM ? m[id]! : t[id]!;
          final editedThere = json(other).toString() != json(b[id]!).toString();
          expect(out.containsKey(id), editedThere, reason: '$reason: $id');
        } else {
          expect(out, isNot(contains(id)), reason: reason);
        }
      }

      // A field changed on one side only takes that side's value.
      for (final id in b.keys) {
        if (!m.containsKey(id) || !t.containsKey(id)) continue;
        final jb = json(b[id]!), jm = json(m[id]!), jt = json(t[id]!);
        final jo = json(out[id]!);
        for (final key in {...jb.keys, ...jm.keys, ...jt.keys}) {
          if (key == 'number' || key == 'updatedAt') continue;
          final mChanged = '${jm[key]}' != '${jb[key]}';
          final tChanged = '${jt[key]}' != '${jb[key]}';
          if (mChanged && !tChanged) {
            expect('${jo[key]}', '${jm[key]}', reason: '$reason: $id.$key');
          }
          if (tChanged && !mChanged) {
            expect('${jo[key]}', '${jt[key]}', reason: '$reason: $id.$key');
          }
        }
      }

      // Numbers stay unique and below nextNumber.
      final numbers = [for (final x in merged.tasks) x.number];
      expect(numbers.toSet().length, numbers.length, reason: reason);
      expect(
        numbers.every((n) => n < merged.nextNumber),
        isTrue,
        reason: reason,
      );

      // Same inputs, same output.
      expect(
        run().project.toJson().toString(),
        merged.toJson().toString(),
        reason: reason,
      );
    }
  });
}
