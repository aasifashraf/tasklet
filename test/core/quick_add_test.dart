import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/quick_add.dart';

import '../helpers.dart';

void main() {
  final today = d('2026-11-03'); // Tuesday
  final bug = Label(id: 'l1', name: 'bug', color: TaskletColor.red);
  final ux = Label(
    id: 'l2',
    name: 'good first issue',
    color: TaskletColor.blue,
  );
  final web = project('p1', name: 'Website', key: 'WEB');
  final api = project('p2', name: 'API Platform', key: 'API');

  QuickAdd parse(String text) => parseQuickAdd(
    text,
    today: today,
    labels: [bug, ux],
    projects: [web, api],
  );

  test('the example from the roadmap', () {
    final q = parse('Fix login tomorrow !high #bug +WEB');
    expect(q.title, 'Fix login');
    expect(q.due.toString(), '2026-11-04');
    expect(q.priority, Priority.high);
    expect(q.labels, [bug]);
    expect(q.project, web);
  });

  test('dates', () {
    String? due(String text) => parse(text).due?.toString();
    expect(due('x today'), '2026-11-03');
    expect(due('x friday'), '2026-11-06');
    expect(due('x tue'), '2026-11-10'); // a weekday means the next one
    expect(due('x next week'), '2026-11-09');
    expect(due('x in 3 days'), '2026-11-06');
    expect(due('x in 2 weeks'), '2026-11-17');
    expect(due('x nov 20'), '2026-11-20');
    expect(due('x 5 jan'), '2027-01-05'); // past this year: next year
    expect(due('x 2026-12-24'), '2026-12-24');
    expect(due('x feb 30'), isNull);
  });

  test('only real labels, projects and priorities are taken', () {
    final q = parse('Make #1 priority +1 bump !important #nope');
    expect(q.title, 'Make #1 priority +1 bump !important #nope');
    expect(q.isEmpty, isTrue);
  });

  test('labels with spaces by dashes; projects by name start; !1-!4', () {
    final q = parse('Docs #good-first-issue +api !1');
    expect(q.labels, [ux]);
    expect(q.project, api);
    expect(q.priority, Priority.urgent);
    expect(q.title, 'Docs');
  });
}
