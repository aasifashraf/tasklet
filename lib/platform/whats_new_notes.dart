import 'package:flutter/material.dart';

/// One feature row in the What's New sheet (SPEC §13).
class ReleaseFeature {
  const ReleaseFeature(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

/// The notes for one shipped version.
class ReleaseNotes {
  const ReleaseNotes({
    required this.version,
    required this.month,
    this.features = const [],
    this.fixes = const [],
  });

  /// The app version (`pubspec.yaml` without the build number). Dismissing the sheet marks it as read.
  final String version;

  /// "November 2026", shown as "November 2026 Update".
  final String month;
  final List<ReleaseFeature> features;
  final List<String> fixes;

  String get id => version;
  String get subtitle => '$month Update · Version $version';
}

/// Every release, newest first. **Each release adds an entry here** (and to CHANGELOG.md); a test fails when the
/// `pubspec.yaml` version has none. The sheet shows the newest release first and earlier ones below it.
const releases = <ReleaseNotes>[
  ReleaseNotes(
    version: '1.1.1',
    month: 'November 2026',
    fixes: [
      'Organizations are now called workspaces, the word Tasklet already used for a data folder: the Workspace menu, New Workspace and Settings > Workspaces. Your folders, settings and exports work as before.',
    ],
  ),
  ReleaseNotes(
    version: '1.1.0',
    month: 'November 2026',
    features: [
      ReleaseFeature(
        Icons.workspaces_outlined,
        'Workspaces',
        'Keep work, freelance and open source apart. Each workspace has its own projects, labels and quick filters in its own folder, so each can sync through a different service. Switch at the top of the sidebar or with Ctrl+Alt+1 to 9.',
      ),
      ReleaseFeature(
        Icons.drive_file_move_outlined,
        'Move, export and import',
        'Move a project to another workspace from its menu. Export a workspace to one file and import it as a new workspace, from the Workspace menu.',
      ),
      ReleaseFeature(
        Icons.palette_outlined,
        'Icons and 16 colors',
        'Give projects, labels and quick filters an icon from about 640 project-related icons, with search, and pick from 16 colors. Click an icon to change it.',
      ),
      ReleaseFeature(
        Icons.rocket_launch_outlined,
        'A head start',
        'A new workspace comes with bug, feature, refactor and security labels and everyday quick filters like Overdue, Due Soon and High Priority. Your first one also has a sample Tasklet project with our plan.',
      ),
      ReleaseFeature(
        Icons.speed,
        'Faster with big workspaces',
        'Boards update right away after an edit, search keeps up while you type, and the dashboard and reports stay quick with tens of thousands of tasks.',
      ),
    ],
    fixes: [
      'Green, orange and yellow are a little darker in the light theme, so icons and dots stay easy to see.',
    ],
  ),
  ReleaseNotes(
    version: '1.0.3',
    month: 'November 2026',
    features: [
      ReleaseFeature(
        Icons.history,
        'Restore earlier versions',
        'Tasklet keeps recent versions of each project, your labels and quick filters on this computer. Use Restore Previous Version in a project menu, or the history button on the Labels and Quick Filters pages.',
      ),
      ReleaseFeature(
        Icons.auto_fix_high_outlined,
        'Repairs after syncing',
        'If two computers created the same task number, or one task ended up in two projects, Tasklet fixes it and tells you what changed.',
      ),
    ],
    fixes: [
      'Undo changes back only what it changed, so edits synced from another computer are kept.',
      'The task panel stays open when you move its task to another project.',
      'Dropping a card between two cards always puts it exactly there.',
      'Opening Settings twice quickly opens one window, and brings back a minimized one.',
      'Changes from your sync service show up promptly even while it is busy.',
      'Reports count done tasks correctly in every case, and very long date ranges stay fast.',
      'Choosing or creating a data folder explains what went wrong if it fails.',
    ],
  ),
  ReleaseNotes(
    version: '1.0.2',
    month: 'November 2026',
    features: [
      ReleaseFeature(
        Icons.speed_outlined,
        'Fast with big workspaces',
        'Large folders open without freezing, and switching back to Tasklet is instant, even with tens of thousands of tasks.',
      ),
    ],
    fixes: [
      'Your last edit is saved when you quit from the tray or File → Exit.',
      'Changes made in the Settings window and the main window no longer overwrite each other.',
      'A data folder that goes missing (for example an unplugged drive) is never recreated empty.',
      'Moving a task to another project can no longer lose it if saving fails.',
      'New Task can no longer create the same task twice.',
      'Search keeps up while you type on large boards.',
      'Easier-to-read secondary text in the light theme.',
      'The list layout scrollbar works correctly.',
      'Errors are written to a local log file to help with bug reports.',
      "What's New now shows every release, newest first.",
    ],
  ),
  ReleaseNotes(
    version: '1.0.1',
    month: 'November 2026',
    features: [
      ReleaseFeature(
        Icons.folder_outlined,
        'Your tasks, your files',
        'Everything is plain JSON in a folder you choose. Put it in OneDrive, Dropbox or iCloud Drive to sync.',
      ),
      ReleaseFeature(
        Icons.view_kanban_outlined,
        'Board and list',
        'Drag cards between columns, reorder by hand, or sort by priority, due date and more.',
      ),
      ReleaseFeature(
        Icons.wb_sunny_outlined,
        'Today and Dashboard',
        "See what's due, starting, or overdue, and what you finished this week.",
      ),
      ReleaseFeature(
        Icons.layers_outlined,
        'Quick filters',
        'Save any combination of filters and open it in one click from the sidebar.',
      ),
      ReleaseFeature(
        Icons.description_outlined,
        'Reports for any AI',
        'Turn on Reports in Settings → Sidebar, then export a ready-made progress report, with optional Mermaid charts, for any AI assistant.',
      ),
    ],
    fixes: ['First public release for Windows.'],
  ),
];

/// The newest release: the app's version and what the sheet opens with.
ReleaseNotes get currentRelease => releases.first;
