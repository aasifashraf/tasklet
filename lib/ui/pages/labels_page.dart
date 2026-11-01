import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class LabelsPage extends StatelessWidget {
  const LabelsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Labels',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
