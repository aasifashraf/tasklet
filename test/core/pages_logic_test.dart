import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/dashboard.dart';
import 'package:tasklet/core/date_format.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/reminder.dart';
import 'package:tasklet/core/today_rules.dart';

import '../helpers.dart';

void main() {
  final today = d('2026-10-15');
  final now = DateTime(2026, 10, 15, 10);

  group('date labels', () {
    test('relative and short dates', () {
      expect(relativeDate(today, today), 'Today');
      expect(relativeDate(d('2026-10-16'), today), 'Tomorrow');
      expect(relativeDate(d('2026-10-14'), today), 'Yesterday');
      expect(relativeDate(d('2026-11-03'), today), 'Nov 3');
      expect(relativeDate(d('2027-11-09'), today), 'Nov 9, 2027');
    });

    test('combined date pill', () {
      expect(datePillLabel(null, null, today), isNull);
      expect(datePillLabel(d('2026-10-20'), null, today), 'Oct 20 →');
      expect(datePillLabel(null, d('2026-10-20'), today), 'Oct 20');
      expect(datePillLabel(d('2026-10-20'), d('2026-10-20'), today), 'Oct 20');
      expect(
        datePillLabel(d('2026-10-20'), d('2026-10-27'), today),
        'Oct 20 → Oct 27',
      );
    });

    test('greeting by hour with optional name', () {
      expect(greeting(DateTime(2026, 1, 1, 9), ''), 'Good morning');
      expect(greeting(DateTime(2026, 1, 1, 12), 'Ada'), 'Good afternoon, Ada');
      expect(greeting(DateTime(2026, 1, 1, 18), ' '), 'Good evening');
      expect(fullDate(d('2026-10-23')), 'Friday, October 23');
    });
  });

  group('today rules', () {
    test('matches any enabled rule', () {
      final due = task('a', due: today);
      final starts = task('b', start: today);
      final late = task('c', due: d('2026-10-01'));
      final lateDone = task('d', due: d('2026-10-01'), status: TaskStatus.done);
      final all = TodayRule.values.toSet();
      expect(
        [
          due,
          starts,
          late,
          lateDone,
        ].where((t) => matchesToday(t, all, today)).length,
        3,
      );
      expect(matchesToday(starts, {TodayRule.dueToday}, today), isFalse);
    });

    test('the last rule cannot be turned off', () {
      expect(toggleTodayRule({TodayRule.overdue}, TodayRule.overdue), {
        TodayRule.overdue,
      });
      expect(
        toggleTodayRule({
          TodayRule.overdue,
          TodayRule.dueToday,
        }, TodayRule.overdue),
        {TodayRule.dueToday},
      );
      expect(toggleTodayRule({TodayRule.overdue}, TodayRule.dueToday), {
        TodayRule.overdue,
        TodayRule.dueToday,
      });
    });
  });

  group('dashboard', () {
    final tasks = [
      entry(task('overdue', due: d('2026-10-10'))),
      entry(task('today', due: today, priority: Priority.low)),
      entry(task('todayUrgent', due: today, priority: Priority.urgent)),
      entry(task('week', due: d('2026-10-21'))),
      entry(task('later', due: d('2026-10-22'))),
      entry(task('undated')),
      entry(
        task(
          'doneRecent',
          status: TaskStatus.done,
          completed: DateTime(2026, 10, 14),
        ),
      ),
      entry(
        task(
          'doneOld',
          status: TaskStatus.done,
          completed: DateTime(2026, 10, 1),
        ),
      ),
    ];

    test('glance counts', () {
      final g = glanceFor(tasks, today, now);
      expect(g.overdue, 1);
      expect(g.dueToday, 2);
      expect(g.dueThisWeek, 3);
      expect(g.doneThisWeek, 1);
    });

    test('up next: due asc, then priority, max 6, excludes undated and beyond a week', () {
      expect(upNext(tasks, today).map((e) => e.task.id), [
        'overdue',
        'todayUrgent',
        'today',
        'week',
      ]);
    });

    test('recently completed in the last 7 days', () {
      expect(recentlyCompleted(tasks, now).map((e) => e.task.id), [
        'doneRecent',
      ]);
    });
  });

  group('reminder digest', () {
    ReminderDigest? digest(
      List<Task> ts, {
      bool overdue = true,
      bool dayBefore = false,
    }) => buildDigest(
      [for (final t in ts) entry(t)],
      today,
      includeOverdue: overdue,
      dayBefore: dayBefore,
    );

    test('nothing due → no notification', () {
      expect(digest([task('a'), task('b', due: d('2026-10-20'))]), isNull);
    });

    test('single task uses its title as the body', () {
      final r = digest([task('a', title: 'Pay rent', due: today)])!;
      expect(r.title, 'Due Today');
      expect(r.body, 'Pay rent');
      expect(r.singleTask, isNotNull);
      expect(digest([task('a', due: d('2026-10-01'))])!.title, 'Overdue');
      expect(
        digest([task('a', due: d('2026-10-16'))], dayBefore: true)!.title,
        'Due Tomorrow',
      );
    });

    test(
      'multiple tasks lead with the most urgent group and summarize the rest',
      () {
        final r = digest([
          task('a', due: today),
          task('b', due: today),
          task('c', due: d('2026-10-01')),
          task('d', due: d('2026-10-02')),
          task('e', due: d('2026-10-16')),
        ], dayBefore: true)!;
        expect(r.title, '2 tasks due today');
        expect(r.body, 'Plus 2 overdue and 1 due tomorrow.');
        expect(r.includesTodayOrOverdue, isTrue);
      },
    );

    test('only one group → no body; tomorrow-only opens All Tasks', () {
      final r = digest([
        task('a', due: d('2026-10-16')),
        task('b', due: d('2026-10-16')),
      ], dayBefore: true)!;
      expect(r.title, '2 tasks due tomorrow');
      expect(r.body, isNull);
      expect(r.includesTodayOrOverdue, isFalse);
      expect(
        digest([
          task('a', due: d('2026-10-01')),
          task('b', due: d('2026-10-02')),
        ])!.title,
        '2 overdue tasks',
      );
    });

    test('overdue excluded when the setting is off; done tasks ignored', () {
      expect(digest([task('a', due: d('2026-10-01'))], overdue: false), isNull);
      expect(digest([task('a', due: today, status: TaskStatus.done)]), isNull);
    });
  });

  group('reminder schedule', () {
    test('once per day at or after the configured time', () {
      expect(
        reminderIsDue(
          now: DateTime(2026, 10, 15, 8, 59),
          hour: 9,
          minute: 0,
          lastSentDay: null,
        ),
        isFalse,
      );
      expect(
        reminderIsDue(
          now: DateTime(2026, 10, 15, 9),
          hour: 9,
          minute: 0,
          lastSentDay: null,
        ),
        isTrue,
      );
      expect(
        reminderIsDue(
          now: DateTime(2026, 10, 15, 23),
          hour: 9,
          minute: 0,
          lastSentDay: '2026-10-14',
        ),
        isTrue,
      );
      expect(
        reminderIsDue(
          now: DateTime(2026, 10, 15, 23),
          hour: 9,
          minute: 0,
          lastSentDay: '2026-10-15',
        ),
        isFalse,
      );
    });

    test('enabling after the time has passed waits until tomorrow', () {
      expect(
        markSentIfTimePassed(
          now: DateTime(2026, 10, 15, 10),
          hour: 9,
          minute: 0,
        ),
        '2026-10-15',
      );
      expect(
        markSentIfTimePassed(
          now: DateTime(2026, 10, 15, 8),
          hour: 9,
          minute: 0,
          current: 'x',
        ),
        'x',
      );
    });
  });
}
