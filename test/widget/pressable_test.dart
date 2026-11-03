import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/ui/pages/list_parts.dart';
import 'package:tasklet/ui/theme.dart';
import 'package:tasklet/ui/widgets.dart';

void main() {
  late List<String> taps;
  late String toggled;

  Future<void> pump(WidgetTester tester) async {
    taps = [];
    toggled = 'active';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Row(
              children: [
                PropChip(label: 'High', onTap: () => taps.add('chip')),
                IconBtn(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: () => taps.add('close'),
                ),
                const IconBtn(icon: Icons.add, tooltip: 'Add', onPressed: null),
                PillToggle<String>(
                  options: const {'active': 'Active', 'archived': 'Archived'},
                  selected: toggled,
                  onChanged: (v) => setState(() => toggled = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the Pressable around [of] draws its keyboard focus ring.
  bool ring(WidgetTester tester, Finder of) {
    final pressable = find.ancestor(of: of, matching: find.byType(Pressable));
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: pressable.first,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.position == DecorationPosition.foreground,
            ),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).border != null;
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  testWidgets(
    'Tab reaches chips, icon buttons and toggle segments, skips disabled',
    (tester) async {
      await pump(tester);

      await tab(tester);
      expect(ring(tester, find.text('High')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, ['chip']);

      await tab(tester);
      expect(ring(tester, find.text('High')), isFalse);
      expect(ring(tester, find.byIcon(Icons.close)), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, ['chip', 'close']);

      // The disabled Add button is skipped.
      await tab(tester);
      expect(ring(tester, find.byIcon(Icons.add)), isFalse);
      expect(ring(tester, find.text('Active')), isTrue);

      await tab(tester);
      expect(ring(tester, find.text('Archived')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(toggled, 'archived');
    },
  );

  testWidgets('semantics: button, label, enabled and selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.byIcon(Icons.close)),
      isSemantics(
        isButton: true,
        label: 'Close',
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.add)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.text('Active')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Archived')),
      isSemantics(isButton: true, isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('a mouse click activates without showing the ring', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(taps, ['close']);
    expect(ring(tester, find.byIcon(Icons.close)), isFalse);
  });

  testWidgets(
    'a hover-only button in a row shows with keyboard focus; the ring moves '
    'to it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Pressable(
              onTap: () {},
              builder: (context, hovered) => Row(
                children: [
                  const Text('Row'),
                  Opacity(
                    opacity: hovered ? 1 : 0,
                    child: IconBtn(
                      icon: Icons.more_horiz,
                      tooltip: 'More',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      double more() => tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byIcon(Icons.more_horiz),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(more(), 0);

      await tab(tester);
      expect(ring(tester, find.text('Row')), isTrue);
      expect(more(), 1);

      await tab(tester);
      expect(ring(tester, find.text('Row')), isFalse);
      expect(ring(tester, find.byIcon(Icons.more_horiz)), isTrue);
      expect(more(), 1);
    },
  );
}
