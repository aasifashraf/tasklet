import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/ui/task/pickers.dart';
import 'package:tasklet/ui/theme.dart';

/// Label and project pickers (SPEC §7.2): short lists are plain menus; long ones get a search field and build only
/// the rows in view.
void main() {
  List<(Label, Project?)> labels(int n) => [
    for (var i = 0; i < n; i++)
      (Label(id: 'l$i', name: 'label $i', color: TaskletColor.blue), null),
  ];

  Future<List<String>> openPicker(
    WidgetTester tester,
    List<(Label, Project?)> available,
  ) async {
    final toggled = <String>[];
    var selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => LabelsPicker(
                selected: selected,
                available: available,
                onToggle: (l) => setState(() {
                  toggled.add(l.id);
                  selected = [
                    for (final id in selected)
                      if (id != l.id) id,
                    if (!selected.contains(l.id)) l.id,
                  ];
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(LabelsPicker));
    await tester.pumpAndSettle();
    return toggled;
  }

  testWidgets('a short list is a plain menu with every label', (tester) async {
    await openPicker(tester, labels(5));
    expect(find.byType(TextField), findsNothing);
    for (var i = 0; i < 5; i++) {
      expect(find.text('label $i'), findsOneWidget);
    }
  });

  testWidgets('a long list searches, builds only visible rows, Enter toggles', (
    tester,
  ) async {
    final toggled = await openPicker(tester, labels(500));
    expect(find.byType(TextField), findsOneWidget);
    // Lazily built: nowhere near 500 rows exist.
    expect(find.textContaining('label ').evaluate().length, lessThan(40));

    await tester.enterText(find.byType(TextField), 'label 42');
    await tester.pump();
    expect(find.widgetWithText(MenuItemButton, 'label 42'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'label 7'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(toggled, ['l42']);
    // The menu stays open for more toggles, with the row checked.
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
  });
}
