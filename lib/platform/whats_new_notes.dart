import 'package:flutter/material.dart';

/// One feature row in the What's New sheet (SPEC §13).
class ReleaseFeature {
  const ReleaseFeature(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

class ReleaseNotes {
  const ReleaseNotes({
    required this.id,
    required this.subtitle,
    required this.features,
    this.fixes = const [],
  });

  /// Bump only when a release ships new notes; dismissing marks this id as read.
  final String id;
  final String subtitle;
  final List<ReleaseFeature> features;
  final List<String> fixes;
}

const currentRelease = ReleaseNotes(
  id: '1.0.0',
  subtitle: 'November 2026 Update',
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
      'Saved views',
      'Save any combination of filters as a view and pin it to the sidebar.',
    ),
    ReleaseFeature(
      Icons.description_outlined,
      'Reports for any AI',
      'Turn on Reports in Settings → Sidebar, then export a ready-made progress report, with optional Mermaid charts, for any AI assistant.',
    ),
  ],
  fixes: ['First release.'],
);
