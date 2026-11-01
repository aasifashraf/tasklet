import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/project_keys.dart';

import '../helpers.dart';

void main() {
  group('baseKeyFor', () {
    test('first three letters, uppercased, ignoring everything else', () {
      expect(baseKeyFor('Website Redesign'), 'WEB');
      expect(baseKeyFor('g e t started'), 'GET');
      expect(baseKeyFor('3D Printing'), 'DPR');
      expect(baseKeyFor('A.I. lab'), 'AIL');
      expect(baseKeyFor('Go'), 'GO');
    });

    test('falls back to PRJ when there are no letters', () {
      expect(baseKeyFor('2026'), 'PRJ');
      expect(baseKeyFor(''), 'PRJ');
      expect(baseKeyFor('日本'), 'PRJ');
    });
  });

  group('nextFreeKey', () {
    test('appends 1, 2, … until free', () {
      expect(nextFreeKey('WEB', {}), 'WEB');
      expect(nextFreeKey('WEB', {'WEB'}), 'WEB1');
      expect(nextFreeKey('WEB', {'WEB', 'WEB1'}), 'WEB2');
    });

    test('TSK is always reserved', () {
      expect(nextFreeKey('TSK', {}), 'TSK1');
      expect(keyForNewProject('Tsk tracking', []), 'TSK1');
    });
  });

  group('resolveProjectKeys', () {
    test('stored keys are kept (sticky across renames)', () {
      final p = project('p1', name: 'Renamed to Something Else', key: 'WEB');
      expect(resolveProjectKeys([p]), isEmpty);
    });

    test('legacy project without key gets one from its name', () {
      expect(resolveProjectKeys([project('p1', name: 'Garden', key: '')]), {'p1': 'GAR'});
    });

    test('oldest project keeps a contested key, newer gets the next suffix', () {
      final older = project('b', name: 'Web A', key: 'WEB', created: at(0));
      final newer = project('a', name: 'Web B', key: 'WEB', created: at(5));
      expect(resolveProjectKeys([newer, older]), {'a': 'WEB1'});
    });

    test('a real project claiming TSK is moved off it', () {
      expect(resolveProjectKeys([project('p1', name: 'Tasks', key: 'TSK')]), {'p1': 'TSK1'});
    });

    test('contested suffixed key strips digits before re-suffixing', () {
      final a = project('a', key: 'WEB', created: at(0));
      final b = project('b', key: 'WEB1', created: at(1));
      final c = project('c', key: 'WEB1', created: at(2));
      expect(resolveProjectKeys([a, b, c]), {'c': 'WEB2'});
    });

    test('ignores the No-Project bucket', () {
      final noProject = Project.noProject(t0);
      expect(resolveProjectKeys([noProject]), isEmpty);
    });
  });
}
