import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class ViewsPage extends StatelessWidget {
  const ViewsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Views',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
