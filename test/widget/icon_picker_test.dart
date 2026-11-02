import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/state/prefs.dart';
import 'package:tasklet/ui/icon_picker.dart';
import 'package:tasklet/ui/theme.dart';

class _MemoryPrefs extends PrefsNotifier {
  @override
  Prefs build() => Prefs(const {});

  @override
  Future<void> set(String key, Object? value) async =>
      state = Prefs({PrefKeys.recentIcons: value});
}

void main() {
  late List<(String?, TaskletColor)> picks;

  Future<void> open(WidgetTester tester, {String? icon}) async {
    picks = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWith(_MemoryPrefs.new)],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => IconPickerButton(
                  icon: icon,
                  color: TaskletColor.blue,
                  kind: GlyphKind.project,
                  onPick: (i, c) => picks.add((i, c)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconPickerButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'search, then pick an icon: it is reported and the picker closes',
    (tester) async {
      await open(tester);
      expect(find.byType(IconPicker), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'rocket');
      await tester.pump();
      await tester.tap(find.byTooltip('rocket').first);
      await tester.pumpAndSettle();
      expect(picks, [('rocket', TaskletColor.blue)]);
      expect(find.byType(IconPicker), findsNothing);
    },
  );

  testWidgets('Enter picks the best match; picked icons show under Recent', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'git branch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picks.single.$1, 'git-branch');

    await tester.tap(find.byType(IconPickerButton));
    await tester.pumpAndSettle();
    expect(find.text('Default and Recent'), findsOneWidget);
  });

  testWidgets('a color keeps the picker open; Default clears the icon', (
    tester,
  ) async {
    await open(tester, icon: 'rocket');
    await tester.tap(find.byTooltip('Teal'));
    await tester.pump();
    expect(picks, [('rocket', TaskletColor.teal)]);
    expect(find.byType(IconPicker), findsOneWidget);

    await tester.tap(find.byTooltip('Default'));
    await tester.pumpAndSettle();
    expect(picks.last, (null, TaskletColor.teal));
    expect(find.byType(IconPicker), findsNothing);
  });

  testWidgets('no match says so; Escape closes without a pick', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No icons match "zzzz".'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(IconPicker), findsNothing);
    expect(picks, isEmpty);
  });
}
