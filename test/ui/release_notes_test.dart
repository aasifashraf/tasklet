import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/platform/whats_new_notes.dart';

/// Every shipped version must come with in-app release notes and a changelog entry (tasklet-release skill).
void main() {
  List<int> parts(String v) => [for (final p in v.split('.')) int.parse(p)];

  test('the app version has release notes, newest first', () {
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    final version = match!.group(1)!;
    expect(
      currentRelease.version,
      version,
      reason:
          'pubspec.yaml is $version: add a ReleaseNotes entry for it at the top of '
          '`releases` in lib/platform/whats_new_notes.dart',
    );
    for (var i = 1; i < releases.length; i++) {
      final newer = parts(releases[i - 1].version);
      final older = parts(releases[i].version);
      final cmp = [for (var k = 0; k < 3; k++) newer[k].compareTo(older[k])]
          .firstWhere((c) => c != 0, orElse: () => 0);
      expect(cmp, 1, reason: 'releases must be unique and newest first');
    }
  });

  test('every release says something', () {
    for (final r in releases) {
      expect(
        r.features.isNotEmpty || r.fixes.isNotEmpty,
        isTrue,
        reason: r.version,
      );
    }
  });

  test('the changelog has the current version', () {
    expect(
      File('CHANGELOG.md').readAsStringSync(),
      contains('## ${currentRelease.version}'),
    );
  });
}
