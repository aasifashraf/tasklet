import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class AllTasksPage extends StatelessWidget {
  const AllTasksPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'All Tasks',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}

class ProjectBoardPage extends StatelessWidget {
  const ProjectBoardPage({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Project',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}

class ViewBoardPage extends StatelessWidget {
  const ViewBoardPage({super.key, required this.viewId});
  final String viewId;

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'View',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
