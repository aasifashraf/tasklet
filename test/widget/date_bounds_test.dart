import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/local_date.dart';
import 'package:tasklet/state/clock.dart';
import 'package:tasklet/ui/task/pickers.dart';
import 'package:tasklet/ui/theme.dart';

import '../helpers.dart';

Widget _host(Widget child) => ProviderScope(
  overrides: [todayProvider.overrideWithValue(d('2026-10-15'))],
  child: MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: Center(child: child)),
  ),
);

MenuItemButton _item(WidgetTester tester, String label) =>
    tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(MenuItemButton),
      ),
    );

void main() {
  testWidgets('a start date cannot be picked after the due date', (
    tester,
  ) async {
    LocalDate? picked;
    await tester.pumpWidget(
      _host(
        DatePickerChip(
          date: null,
          placeholder: 'Start date',
          latest: d('2026-10-15'), // due today
          onPick: (date, _) => picked = date,
        ),
      ),
    );
    await tester.tap(find.text('Start date'));
    await tester.pumpAndSettle();
    expect(_item(tester, 'Today').onPressed, isNotNull);
    expect(
      _item(tester, 'Tomorrow').onPressed,
      isNull,
      reason: 'after the due date',
    );
    expect(
      _item(tester, 'Next Week').onPressed,
      isNull,
      reason: 'after the due date',
    );
    await tester.tap(find.text('Tomorrow'));
    expect(picked, isNull);
  });

  testWidgets('a due date cannot be picked before the start date', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DatePickerChip(
          date: null,
          placeholder: 'Due date',
          earliest: d('2026-10-16'), // starts tomorrow
          onPick: (_, _) {},
        ),
      ),
    );
    await tester.tap(find.text('Due date'));
    await tester.pumpAndSettle();
    expect(
      _item(tester, 'Today').onPressed,
      isNull,
      reason: 'before the start date',
    );
    expect(_item(tester, 'Tomorrow').onPressed, isNotNull);
  });

  testWidgets('the calendar is limited to the allowed range', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => pickCalendarDate(
              context,
              initial: d('2026-10-20'),
              earliest: d('2026-10-10'),
              latest: d('2026-10-15'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(LocalDate.fromDateTime(picker.firstDate), d('2026-10-10'));
    expect(LocalDate.fromDateTime(picker.lastDate), d('2026-10-15'));
    expect(
      LocalDate.fromDateTime(picker.initialDate!),
      d('2026-10-15'),
      reason: 'initial clamped into range',
    );
  });
}
