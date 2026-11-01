import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/ui/theme.dart';
import 'package:tasklet/ui/widgets.dart';

void main() {
  testWidgets('segmented switch shows one pill and switches on tap', (
    tester,
  ) async {
    var selected = BoardLayout.board;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SegmentedIconSwitch<BoardLayout>(
                selected: selected,
                onChanged: (v) => setState(() => selected = v),
                options: const [
                  SegmentOption(
                    BoardLayout.board,
                    Icons.view_kanban_outlined,
                    'Board',
                  ),
                  SegmentOption(
                    BoardLayout.list,
                    Icons.view_list_rounded,
                    'List',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // One bordered container holding both options.
    expect(
      tester.getSize(find.byType(SegmentedIconSwitch<BoardLayout>)),
      const Size(64, 26),
    );
    final highlight = find.byType(AnimatedPositioned);
    final boardLeft = tester.getTopLeft(highlight).dx;

    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();
    expect(selected, BoardLayout.list);
    expect(
      tester.getTopLeft(highlight).dx,
      boardLeft + 30,
      reason: 'highlight slides to List',
    );
  });
}
