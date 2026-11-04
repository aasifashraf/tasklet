import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/filters.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/reminder.dart';
import 'package:tasklet/core/today_rules.dart';

import '../helpers.dart';

/// Snooze (`snoozedUntil`): an open task is put away until a day.
void main() {
  final today = d('2026-11-03');
  final p = project('p1', key: 'WEB');
  Task snoozed(String until, {TaskStatus status = TaskStatus.todo}) => task(
    't1',
    title: 'Renew the certificate',
    due: today,
    status: status,
  ).copyWith(snoozedUntil: d(until));

  test('round trip; the key is absent when not snoozed', () {
    final t = snoozed('2026-11-10');
    expect(t.toJson()['snoozedUntil'], '2026-11-10');
    expect(Task.fromJson(t.toJson()).snoozedUntil, d('2026-11-10'));
    expect(task('t2').toJson().containsKey('snoozedUntil'), isFalse);
    expect(t.copyWith(snoozedUntil: null).snoozedUntil, isNull);
  });

  test('snoozed until a later day; back on that day; done tasks never', () {
    expect(isSnoozed(snoozed('2026-11-04'), today), isTrue);
    expect(isSnoozed(snoozed('2026-11-03'), today), isFalse);
    expect(isSnoozed(snoozed('2026-11-01'), today), isFalse);
    expect(
      isSnoozed(snoozed('2026-11-10', status: TaskStatus.done), today),
      isFalse,
    );
    expect(isSnoozed(task('t2'), today), isFalse);
  });

  test('boards leave it out unless searching', () {
    final e = ProjectTask(p, snoozed('2026-11-10'));
    final none = BoardFilters();
    expect(shownOnBoard(e, none, today, SearchQuery('')), isFalse);
    expect(shownOnBoard(e, none, today, SearchQuery('certificate')), isTrue);
    expect(shownOnBoard(e, none, today, SearchQuery('WEB-1')), isTrue);
    final back = ProjectTask(p, snoozed('2026-11-03'));
    expect(shownOnBoard(back, none, today, SearchQuery('')), isTrue);
  });

  test('not on Today and not in reminders until its day', () {
    final rules = TodayRule.values.toSet();
    expect(matchesToday(snoozed('2026-11-10'), rules, today), isFalse);
    expect(matchesToday(snoozed('2026-11-03'), rules, today), isTrue);
    expect(
      buildDigest(
        [ProjectTask(p, snoozed('2026-11-10'))],
        today,
        includeOverdue: true,
        dayBefore: true,
      ),
      isNull,
    );
    expect(
      buildDigest(
        [ProjectTask(p, snoozed('2026-11-03'))],
        today,
        includeOverdue: true,
        dayBefore: true,
      ),
      isNotNull,
    );
  });

  test('Done window: older Done tasks leave the board unless searching', () {
    Task doneOn(String day) => task(
      'd',
      title: 'Shipped',
      status: TaskStatus.done,
      completed: DateTime.parse('${day}T12:00:00Z'),
    );
    final none = BoardFilters();
    bool shown(Task t, {String search = ''}) => shownOnBoard(
      ProjectTask(p, t),
      none,
      today,
      SearchQuery(search),
      doneWithinDays: 7,
    );
    expect(shown(doneOn('2026-10-27')), isTrue); // exactly 7 days ago
    expect(shown(doneOn('2026-10-26')), isFalse);
    expect(shown(doneOn('2026-10-26'), search: 'shipped'), isTrue);
    expect(shown(task('o', due: today)), isTrue); // open tasks unaffected
    final display = ViewDisplay(doneWithinDays: 30);
    expect(ViewDisplay.fromJson(display.toJson()).doneWithinDays, 30);
    expect(ViewDisplay().toJson().containsKey('doneWithinDays'), isFalse);
  });
}
