import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/colors.dart';
import 'package:tasklet/core/diagnostics.dart';
import 'package:tasklet/core/models.dart';
import 'package:tasklet/core/workspace_info.dart';

import '../helpers.dart';

void main() {
  String report(Workspace? ws, {String log = ''}) => diagnosticsReport(
    now: t0,
    appVersion: '1.1.1',
    os: 'windows 10.0',
    dart: '3.13.5',
    workspaceCount: 2,
    workspace: ws,
    syncedBy: 'OneDrive',
    fileSizes: const {'projects/p1.json': 2048, 'tasklet-workspace.json': 120},
    log: log,
  );

  test('counts and sizes, never task text or names', () {
    final ws = Workspace(
      folder: '/Users/someone/Secret Folder',
      info: const WorkspaceInfo(name: 'Secret Workspace'),
      projects: [
        project(
          'p1',
          name: 'Secret Project',
          tasks: [
            task('a', number: 1, title: 'Secret title', description: 'Secret'),
            task('b', number: 2, status: TaskStatus.done),
          ],
          labels: [
            Label(id: 'l1', name: 'Secret label', color: TaskletColor.red),
          ],
        ),
        project('p2', name: 'Secret Archive', archived: true),
      ],
      noProject: Project.noProject(t0),
      noProjectOnDisk: false,
      labels: [Label(id: 'l2', name: 'Secret', color: TaskletColor.blue)],
      hiddenEntryCount: 3,
    );
    final text = report(ws);
    expect(text, isNot(contains('Secret')));
    expect(text, contains('Tasklet: 1.1.1'));
    expect(text, contains('Projects: 2 (1 archived)'));
    expect(text, contains('Tasks: 2 (1 open, 1 done)'));
    expect(text, contains('Workspace labels: 1'));
    expect(text, contains('Project labels: 1'));
    expect(text, contains('Hidden entries (newer version or damaged): 3'));
    expect(text, contains('== Files (2, 2.1 KB)'));
    expect(text, contains('2.0 KB  projects/p1.json'));
  });

  test('no workspace and an empty log still make a report', () {
    final text = report(null);
    expect(text, contains('None open.'));
    expect(text, contains('== Error log\nEmpty.'));
    expect(report(null, log: 'boom\n'), contains('== Error log\nboom'));
  });
}
