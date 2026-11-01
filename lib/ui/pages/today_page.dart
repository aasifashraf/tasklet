import 'package:flutter/material.dart';

import '../../state/boards.dart';
import 'board_pages.dart';

/// Today (SPEC §4.2): a flat list of tasks due today, starting today, or overdue — whichever rules are on.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const BoardPage(kind: TodayBoard(), title: 'Today');
}
