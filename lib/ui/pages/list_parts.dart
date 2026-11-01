import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// A pill-shaped two-or-more option segmented toggle (Projects: Active / Archived).
class PillToggle<T> extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(:key, :value) in options.entries)
            GestureDetector(
              onTap: () => onChanged(key),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: key == selected ? t.selected : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: key == selected ? t.primary : t.secondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A pill-shaped button that opens a menu (Dashboard project filter, Labels scope, Reports chips).
class PillMenuButton extends StatelessWidget {
  const PillMenuButton({
    super.key,
    required this.label,
    required this.menuChildren,
    this.leading,
    this.enabled = true,
  });
  final String label;
  final Widget? leading;
  final List<Widget> menuChildren;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => PropChip(
        icon: leading,
        label: '$label  ▾',
        maxLabelWidth: 220,
        onTap: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
      ),
    );
  }
}

/// The shared list row of the Projects / Views / Labels pages: leading icon, title, trailing cells, menu.
class ListRowShell extends StatelessWidget {
  const ListRowShell({
    super.key,
    required this.leading,
    required this.title,
    this.trailing = const [],
    this.onTap,
    this.onDoubleTap,
    this.menuChildren,
    this.dimmed = false,
  });

  final Widget leading;
  final Widget title;
  final List<Widget> trailing;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final List<Widget> Function()? menuChildren;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget row = Hoverable(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered && onTap != null ? t.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Opacity(
            opacity: dimmed ? 0.5 : 1,
            child: Row(
              children: [
                SizedBox(width: 22, child: Center(child: leading)),
                const SizedBox(width: 8),
                Expanded(child: title),
                for (final w in trailing) ...[const SizedBox(width: 12), w],
                if (menuChildren != null) ...[
                  const SizedBox(width: 8),
                  MenuAnchor(
                    menuChildren: menuChildren!(),
                    builder: (context, controller, _) => IconBtn(
                      icon: Icons.more_horiz,
                      tooltip: 'More',
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (menuChildren != null) {
      row = ContextMenuRegion(menuChildren: menuChildren!, child: row);
    }
    return row;
  }
}

/// "Active Projects 3" style heading above a list.
class ListHeading extends StatelessWidget {
  const ListHeading(this.label, this.count, {super.key});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
    child: Row(
      children: [
        Text(label, style: TextStyles.sectionLabel(context)),
        const SizedBox(width: 6),
        CountText(count),
      ],
    ),
  );
}

/// Progress bar + percentage (SPEC §4.5): 0% empty track, 1–49% neutral, 50–99% accent, 100% green.
class ProgressCell extends StatelessWidget {
  const ProgressCell({super.key, required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pct = total == 0 ? 0 : (done * 100 / total).floor();
    final fill = pct >= 100 ? t.success : (pct >= 50 ? t.accent : t.tertiary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 4,
          decoration: BoxDecoration(
            color: t.selected,
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: pct / 100,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: TextStyles.meta(context)
                .copyWith(color: pct >= 100 ? t.success : null),
          ),
        ),
      ],
    );
  }
}

/// Opens [menuChildren] from a tap on [child] (e.g. a color icon that opens the color grid).
class TapMenu extends StatelessWidget {
  const TapMenu({
    super.key,
    required this.menuChildren,
    required this.child,
    this.enabled = true,
  });
  final List<Widget> menuChildren;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: menuChildren,
    builder: (context, controller, _) => GestureDetector(
      onTap: enabled
          ? () => controller.isOpen ? controller.close() : controller.open()
          : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: child,
      ),
    ),
  );
}
