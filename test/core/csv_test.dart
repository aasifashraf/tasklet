import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/csv.dart';
import 'package:tasklet/core/models.dart';

import '../helpers.dart';

void main() {
  test('parse: quotes, doubled quotes, line breaks, CRLF, BOM, semicolons', () {
    expect(parseCsv('﻿a,b\r\n"x, y","say ""hi"""\r\n"two\nlines",z\n'), [
      ['a', 'b'],
      ['x, y', 'say "hi"'],
      ['two\nlines', 'z'],
    ]);
    expect(parseCsv('Title;Due\nOne;2026-11-05\n'), [
      ['Title', 'Due'],
      ['One', '2026-11-05'],
    ]);
  });

  test('export then import keeps the fields', () {
    final bug = Label(id: 'l1', name: 'bug', color: TaskletColor.red);
    final p = project(
      'p1',
      name: 'Website',
      key: 'WEB',
      labels: [bug],
      tasks: [
        task(
          't1',
          number: 3,
          title: 'Fix "login", now',
          description: 'Line one\nline two',
          status: TaskStatus.inProgress,
          priority: Priority.high,
          due: d('2026-11-05'),
          labels: ['l1'],
        ),
      ],
    );
    final ws = Workspace(
      folder: '/x',
      projects: [p],
      noProject: Project.noProject(t0),
      noProjectOnDisk: false,
    );
    final csv = tasksToCsv(ws, [ProjectTask(p, p.tasks.single)]);
    expect(csv, startsWith('﻿ID,Title,'));
    final back = importTasks(csv)!.single;
    expect(back.title, 'Fix "login", now');
    expect(back.description, 'Line one\nline two');
    expect(back.status, TaskStatus.inProgress);
    expect(back.priority, Priority.high);
    expect(back.due.toString(), '2026-11-05');
    expect(back.labels, ['bug']);
    expect(back.project, 'Website');
  });

  test("Todoist's format: CONTENT, PRIORITY 1 = highest, only task rows", () {
    final tasks = importTasks(
      'TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,DATE\n'
      'section,Errands,,,,\n'
      'task,Buy milk @home,,1,1,2026-11-06\n'
      'note,remember the oat one,,,,\n'
      'task,Call bank,,4,1,\n',
    )!;
    expect(tasks.map((t) => t.title), ['Buy milk @home', 'Call bank']);
    expect(tasks.first.priority, Priority.urgent);
    expect(tasks.first.due.toString(), '2026-11-06');
    expect(tasks.last.priority, Priority.none);
  });

  test('no title column: not a task file', () {
    expect(importTasks('a,b\n1,2\n'), isNull);
    expect(importTasks(''), isNull);
  });
}
