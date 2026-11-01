import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Reports',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
