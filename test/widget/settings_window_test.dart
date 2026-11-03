import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/ui/settings/settings_app.dart';

class _MemoryPrefs extends PrefsNotifier {
  final _values = <String, Object?>{PrefKeys.userName: 'Alex'};

  @override
  Prefs build() => Prefs(Map.of(_values));

  @override
  Future<void> set(String key, Object? value) async {
    _values[key] = value;
    // Like the real store: the write completes first, then the state updates (never inside a build or dispose).
    await Future<void>.value();
    state = Prefs(Map.of(_values));
  }
}

/// The Settings window is a fixed 520x440 (windows/runner/flutter_window.cpp). Every tab must fit it at 200% OS
/// text with nothing overflowing (docs/DESIGN_SYSTEM.md, layout robustness).
void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('every Settings tab fits 520x440 at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(520, 440);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsProvider.overrideWith(_MemoryPrefs.new)],
          child: const SettingsApp(),
        ),
      );
      await tester.pumpAndSettle();

      for (final tab in ['General', 'Sidebar', 'Notifications', 'Workspaces']) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
}
