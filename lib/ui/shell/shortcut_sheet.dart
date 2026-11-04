import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';
import 'app_menu.dart';

/// Help > Keyboard Shortcuts (Ctrl+/ or ?): every menu command that has a shortcut, read from the same command
/// table as the menus so it can't drift, plus the keys that only work in one place.
Future<void> showShortcutSheet(
  BuildContext context,
  List<CommandGroup> groups,
) => showDialog<void>(
  context: context,
  builder: (context) => _ShortcutSheet(groups: groups),
);

/// Shortcuts that belong to one place rather than a menu.
List<(String, String)> _inPlace() => [
  ('Close a panel, menu, dialog or search', 'Esc'),
  (
    'Create the task in New Task',
    shortcutLabel(accel(LogicalKeyboardKey.enter)),
  ),
  ('From a task title to its description', 'Enter'),
  (
    'Delete the focused or open task',
    shortcutLabel(accel(LogicalKeyboardKey.backspace)),
  ),
  ('Move between buttons and fields', 'Tab'),
  ('Move in menus, pickers and the palette', '↑ ↓'),
];

class _ShortcutSheet extends StatelessWidget {
  const _ShortcutSheet({required this.groups});
  final List<CommandGroup> groups;

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<(String, String)>)>[
      for (final g in groups)
        (
          g.label,
          [
            for (final c in g.items)
              if (c != null && c.shortcut != null)
                (c.label, shortcutLabel(c.shortcut!)),
          ],
        ),
      ('Anywhere', _inPlace()),
    ].where((s) => s.$2.isNotEmpty).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Keyboard Shortcuts',
                      style: TextStyles.pageTitle(context),
                    ),
                  ),
                  IconBtn(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  for (final (title, rows) in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        title,
                        style: TextStyles.sectionLabel(context),
                      ),
                    ),
                    for (final (label, keys) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyles.body(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _Keys(keys),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys(this.keys);
  final String keys;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(keys, style: TextStyles.meta(context)),
    );
  }
}
