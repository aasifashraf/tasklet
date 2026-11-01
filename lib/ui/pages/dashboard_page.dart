import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Dashboard',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
