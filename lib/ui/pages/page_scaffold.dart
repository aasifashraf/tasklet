import 'package:flutter/material.dart';

import '../theme.dart';

/// A page's header bar (title + optional leading icon + actions) above its body (SPEC §3.2).
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.actions = const [],
    this.toolbar,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  /// Secondary toolbar strip for board/list pages.
  final Widget? toolbar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  title,
                  style: TextStyles.pageTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              for (final a in actions) ...[const SizedBox(width: 6), a],
            ],
          ),
        ),
        if (toolbar != null)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: toolbar,
          ),
        Expanded(child: body),
      ],
    );
  }
}
