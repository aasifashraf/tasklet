import 'package:flutter/material.dart';

import '../widgets.dart';
import 'page_scaffold.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Today',
    body: EmptyState(
      title: 'Coming soon',
      message: 'This page is being built.',
    ),
  );
}
