import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

Map<String, Object?> roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('opaque entries', () {
    test(
      'a task with a status from a newer version is hidden and preserved',
      () {
        final json = roundTrip(
          project('p1', tasks: [task('t1', number: 1)]).toJson(),
        );
        final future = {
          ...task('t2', number: 2).toJson(),
          'status': 'canceled',
          'reason': 'dup',
        };
        (json['tasks']! as List<Object?>).add(future);

        final p = Project.fromJson(json);
        expect(p.tasks.map((t) => t.id), ['t1']);
        expect(p.opaqueTasks, [future]);
        expect(p.hiddenEntryCount, 1);
        expect(p.nextNumber, 3, reason: 'hidden task numbers are never reused');

        final written = roundTrip(p.copyWith(name: 'Edited').toJson());
        expect((written['tasks']! as List<Object?>).last, future);
      },
    );

    test('a damaged task does not hide the rest of the project', () {
      final json = roundTrip(
        project('p1', tasks: [task('t1', number: 1)]).toJson(),
      );
      (json['tasks']! as List<Object?>).addAll([
        {'id': 'broken'},
        'not even an object',
      ]);
      final p = Project.fromJson(json);
      expect(p.tasks.single.id, 't1');
      expect(p.opaqueTasks.length, 2);
    });

    test('duplicate task ids: the first wins, later copies are preserved', () {
      final json = roundTrip(
        project(
          'p1',
          tasks: [
            task('t1', number: 1, title: 'first'),
            task('t1', number: 2, title: 'second'),
          ],
        ).toJson(),
      );
      final p = Project.fromJson(json);
      expect(p.tasks.single.title, 'first');
      expect(p.opaqueTasks.length, 1);
      expect(p.nextNumber, 3);
    });

    test('project labels are lenient too', () {
      final json = roundTrip(
        project(
          'p1',
          labels: [Label(id: 'l1', name: 'Bug', color: TaskletColor.red)],
        ).toJson(),
      );
      (json['labels']! as List<Object?>).add({'id': 'l2'});
      final p = Project.fromJson(json);
      expect(p.labels.single.id, 'l1');
      expect(p.opaqueLabels.length, 1);
    });

    test('damage to the project itself still fails the whole file', () {
      final json = roundTrip(project('p1').toJson())..remove('name');
      expect(() => Project.fromJson(json), throwsFormatException);
      expect(
        () => Project.fromJson({...project('p1').toJson(), 'tasks': 'oops'}),
        throwsFormatException,
      );
    });
  });

  group('unknown colors', () {
    test('show as neutral and are written back unchanged', () {
      final json = {...project('p1').toJson(), 'color': 'ultraviolet'};
      final p = Project.fromJson(json);
      expect(p.color, TaskletColor.neutral);
      expect(p.copyWith(name: 'x').toJson()['color'], 'ultraviolet');
      expect(
        p.copyWith(color: TaskletColor.green).toJson()['color'],
        'green',
        reason: 'picking a color replaces the unknown one',
      );
    });

    test('labels and views keep unknown colors too', () {
      final label = Label.fromJson({
        'id': 'l',
        'name': 'L',
        'color': 'ultraviolet',
      });
      expect(label.toJson()['color'], 'ultraviolet');
      expect(label.copyWith(color: TaskletColor.red).toJson()['color'], 'red');
      final view = SavedView.fromJson({
        ...SavedView(id: 'v', name: 'V', createdAt: t0, updatedAt: t0).toJson(),
        'color': 'ultraviolet',
      });
      expect(view.toJson()['color'], 'ultraviolet');
    });

    test('the 8 colors added in 1.1 round-trip', () {
      for (final c in TaskletColor.values) {
        final p = Project.fromJson(
          roundTrip(project('p').copyWith(color: c).toJson()),
        );
        expect(p.color, c);
        expect(p.unknownColor, isNull);
      }
    });

    test('a non-string color is invalid', () {
      expect(
        () => Label.fromJson({'id': 'l', 'name': 'L', 'color': 3}),
        throwsFormatException,
      );
    });
  });

  group('icons', () {
    test('projects and labels keep their icon; none is not written', () {
      final p = Project.fromJson(
        roundTrip(project('p').copyWith(icon: 'rocket').toJson()),
      );
      expect(p.icon, 'rocket');
      expect(p.copyWith(name: 'x').icon, 'rocket');
      expect(p.copyWith(clearIcon: true).toJson().containsKey('icon'), isFalse);
      expect(project('p').toJson().containsKey('icon'), isFalse);

      final l = Label.fromJson({
        'id': 'l',
        'name': 'L',
        'color': 'red',
        'icon': 'bug',
      });
      expect(l.icon, 'bug');
      expect(l.copyWith(color: TaskletColor.blue).toJson()['icon'], 'bug');
      expect(l.copyWith(clearIcon: true).toJson().containsKey('icon'), isFalse);
    });

    test('an icon name this version lacks is kept and written back', () {
      final p = Project.fromJson({
        ...project('p').toJson(),
        'icon': 'quantum-widget',
      });
      expect(p.copyWith(name: 'x').toJson()['icon'], 'quantum-widget');
    });

    test('quick filters keep their icon, and one this version lacks', () {
      final v = SavedView(
        id: 'v',
        name: 'V',
        createdAt: t0,
        updatedAt: t0,
      ).copyWith(icon: 'flag');
      expect(SavedView.fromJson(roundTrip(v.toJson())).icon, 'flag');
      expect(v.copyWith(clearIcon: true).toJson().containsKey('icon'), isFalse);
      final future = SavedView.fromJson({...v.toJson(), 'icon': 'quantum'});
      expect(future.copyWith(name: 'W').toJson()['icon'], 'quantum');
    });

    test('a non-string icon from a newer version is kept as is', () {
      final icon = {'set': 'emoji', 'value': 'rocket'};
      final p = Project.fromJson({...project('p').toJson(), 'icon': icon});
      expect(p.icon, isNull);
      expect(p.toJson()['icon'], icon);
      final l = Label.fromJson({'id': 'l', 'name': 'L', 'icon': icon});
      expect(l.icon, isNull);
      expect(l.toJson()['icon'], icon);
    });
  });
}
