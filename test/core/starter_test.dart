import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/starter.dart';
import 'package:tasklet/ui/icons/project_icons.dart';

import '../helpers.dart';

/// What a new organization starts with (docs/DECISIONS.md D16).
void main() {
  var n = 0;
  String id() => 'id${n++}';
  final content = starterContent(newId: id, now: t0, withSampleProject: true);

  test('four labels with icons the picker has', () {
    expect(
      [for (final l in content.labels) l.name],
      ['bug', 'feature', 'refactor', 'security'],
    );
    for (final l in content.labels) {
      expect(iconFor(l.icon), isNotNull, reason: l.name);
    }
  });

  test(
    'quick filters use only status, priority and due date, and round-trip',
    () {
      final names = {for (final v in content.views) v.name};
      expect(names, hasLength(content.views.length));
      expect(content.views.where((v) => v.inSidebar), hasLength(3));
      for (final v in content.views) {
        expect(iconFor(v.icon), isNotNull, reason: v.name);
        expect(v.filters.projects, isEmpty, reason: v.name);
        expect(v.filters.labels, isEmpty, reason: v.name);
        expect(v.filters.activeCategoryCount, greaterThan(0), reason: v.name);
        final back = SavedView.fromJson(
          jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>,
        );
        expect(back.toJson(), v.toJson());
      }
    },
  );

  test('the sample project covers every status with valid tasks', () {
    final p = content.projects.single;
    expect(p.name, 'Tasklet');
    expect(p.key, isNot(noProjectKey));
    expect(iconFor(p.icon), isNotNull);
    expect({for (final t in p.tasks) t.status}, TaskStatus.values.toSet());
    expect({for (final t in p.tasks) t.id}, hasLength(p.tasks.length));
    expect(
      [for (final t in p.tasks) t.number],
      [for (var i = 1; i <= p.tasks.length; i++) i],
    );
    expect(p.nextNumber, p.tasks.length + 1);
    final labelIds = {for (final l in content.labels) l.id};
    for (final t in p.tasks) {
      expect(t.labelIds.every(labelIds.contains), isTrue, reason: t.title);
      expect(t.isDone, t.completedAt != null, reason: t.title);
    }
    // It survives a save and a read.
    final back = Project.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>,
    );
    expect(back.tasks, hasLength(p.tasks.length));
  });

  test('later organizations get no sample project', () {
    final later = starterContent(newId: id, now: t0, withSampleProject: false);
    expect(later.projects, isEmpty);
    expect(later.labels, hasLength(4));
    expect(later.views, hasLength(content.views.length));
  });
}
