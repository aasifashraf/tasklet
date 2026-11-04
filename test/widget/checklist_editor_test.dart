import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/ui/task/checklist_editor.dart';
import 'package:tasklet/ui/theme.dart';

void main() {
  testWidgets('add with Enter, tick, rename, remove', (tester) async {
    var items = <ChecklistItem>[];
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ChecklistEditor(
              items: items,
              newId: () => 'id${next++}',
              onChanged: (v) => setState(() => items = v),
            ),
          ),
        ),
      ),
    );

    for (final step in ['Bump the version', 'Tag it']) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a step'),
        step,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(items.map((i) => i.text), ['Bump the version', 'Tag it']);
    expect(find.text('0/2'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(items.first.done, isTrue);
    expect(find.text('1/2'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tag it'), 'Tag v1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(items.last.text, 'Tag v1');

    await tester.tap(find.byTooltip('Remove step').first);
    await tester.pump();
    expect(items.map((i) => i.text), ['Tag v1']);
  });
}
