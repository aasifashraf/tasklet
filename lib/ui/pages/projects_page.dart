import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Projects',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
