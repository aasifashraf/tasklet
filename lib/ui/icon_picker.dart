import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/colors.dart';
import '../state/prefs.dart';
import 'glyphs.dart';
import 'icons/project_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the picker's "Default" glyph looks like: cube, dot, or filter (quick filters).
enum GlyphKind { project, label, view }

/// Opens the icon and color picker under the widget of [context] (the glyph that was clicked), or centered when
/// [anchored] is false (opened from a menu, whose item is gone by then). [onPick] runs on every change: picking a
/// color keeps the picker open and re-tints the icons, picking an icon (or Default) closes it.
Future<void> showIconPicker(
  BuildContext context, {
  bool anchored = true,
  required String? icon,
  required TaskletColor color,
  required GlyphKind kind,
  required void Function(String? icon, TaskletColor color) onPick,
}) {
  final box = anchored ? context.findRenderObject() as RenderBox? : null;
  final rect = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _BelowAnchor(rect),
      child: IconPicker(icon: icon, color: color, kind: kind, onPick: onPick),
    ),
  );
}

/// "Change Icon and Color…" for the ⋯ / right-click menus of projects and labels.
Widget iconMenuItem(
  BuildContext context, {
  required String? icon,
  required TaskletColor color,
  required GlyphKind kind,
  required void Function(String? icon, TaskletColor color) onPick,
}) => menuItem(
  'Change Icon and Color…',
  leading: TaskletIcon(
    icon: icon,
    color: Tokens.of(context).named(color),
    size: 12,
    fallback: switch (kind) {
      GlyphKind.project => CubeIcon.new,
      GlyphKind.label => ColorDot.new,
      GlyphKind.view => FunnelIcon.new,
    },
  ),
  onPressed: () => showIconPicker(
    context,
    anchored: false,
    icon: icon,
    color: color,
    kind: kind,
    onPick: onPick,
  ),
);

/// A project or label glyph that opens the icon picker when clicked.
class IconPickerButton extends StatelessWidget {
  const IconPickerButton({
    super.key,
    required this.icon,
    required this.color,
    required this.kind,
    required this.onPick,
    this.size = 15,
    this.dotSize = 10,
    this.enabled = true,
  });
  final String? icon;
  final TaskletColor color;
  final GlyphKind kind;
  final void Function(String? icon, TaskletColor color) onPick;
  final double size;
  final double dotSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final glyph = TaskletIcon(
      icon: icon,
      color: Tokens.of(context).named(color),
      size: size,
      fallback: switch (kind) {
        GlyphKind.project => CubeIcon.new,
        GlyphKind.label => ({key, required color, size = 0}) => ColorDot(
          key: key,
          color: color,
          size: dotSize,
        ),
        GlyphKind.view => FunnelIcon.new,
      },
    );
    if (!enabled) return glyph;
    return GestureDetector(
      onTap: () => showIconPicker(
        context,
        icon: icon,
        color: color,
        kind: kind,
        onPick: onPick,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(message: 'Change icon and color', child: glyph),
      ),
    );
  }
}

/// Below the anchor, or above it when there's no room, kept inside the window.
class _BelowAnchor extends SingleChildLayoutDelegate {
  _BelowAnchor(this.anchor);
  final Rect? anchor;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    if (a == null) {
      return Offset(
        (size.width - child.width) / 2,
        (size.height - child.height) / 2,
      );
    }
    final below = a.bottom + 4;
    final y = below + child.height <= size.height - _margin
        ? below
        : a.top - 4 - child.height;
    return Offset(
      a.left.clamp(
        _margin,
        math.max(_margin, size.width - child.width - _margin),
      ),
      y.clamp(_margin, math.max(_margin, size.height - child.height - _margin)),
    );
  }

  @override
  bool shouldRelayout(_BelowAnchor old) => old.anchor != anchor;
}

class IconPicker extends ConsumerStatefulWidget {
  const IconPicker({
    super.key,
    required this.icon,
    required this.color,
    required this.kind,
    required this.onPick,
  });
  final String? icon;
  final TaskletColor color;
  final GlyphKind kind;
  final void Function(String? icon, TaskletColor color) onPick;

  @override
  ConsumerState<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends ConsumerState<IconPicker> {
  late final String? _icon = widget.icon;
  late TaskletColor _color = widget.color;
  String _query = '';

  void _pickIcon(String? name) {
    if (name != null) {
      final recent = ref.read(prefsProvider).recentIcons;
      ref
          .read(prefsProvider.notifier)
          .set(
            PrefKeys.recentIcons,
            [
              name,
              ...recent.where((r) => r != name),
            ].take(Prefs.maxRecentIcons).toList(),
          );
    }
    widget.onPick(name, _color);
    Navigator.of(context).pop();
  }

  void _pickColor(TaskletColor c) {
    setState(() => _color = c);
    widget.onPick(_icon, c);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final tint = t.named(_color);
    final results = searchIcons(_query);
    final recent = [
      for (final name in ref.watch(prefsProvider).recentIcons) ?iconFor(name),
    ];

    Widget grid(List<Widget> cells) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid.extent(
        maxCrossAxisExtent: 34,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: cells,
      ),
    );
    Widget header(String text) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(text, style: TextStyles.meta(context)),
      ),
    );
    Widget cell(ProjectIcon i) => _Cell(
      tooltip: i.name,
      selected: i.name == _icon,
      onTap: () => _pickIcon(i.name),
      child: Icon(i.data, size: 16, color: tint),
    );
    final defaultCell = _Cell(
      tooltip: 'Default',
      selected: iconFor(_icon) == null,
      onTap: () => _pickIcon(null),
      child: switch (widget.kind) {
        GlyphKind.project => CubeIcon(color: tint, size: 16),
        GlyphKind.label => ColorDot(color: tint, size: 10),
        GlyphKind.view => FunnelIcon(color: tint, size: 16),
      },
    );

    return Material(
      color: t.raised,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 356,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                autofocus: true,
                style: TextStyles.body(context),
                onChanged: (q) => setState(() => _query = q),
                onSubmitted: (q) {
                  final best = searchIcons(q).firstOrNull;
                  if (best != null) _pickIcon(best.name);
                },
                decoration: InputDecoration(
                  hintText: 'Search icons',
                  prefixIcon: Icon(Icons.search, size: 15, color: t.tertiary),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              // All 17 on one row: 17 x 18 + 16 x 2 = 338 of the 340 available.
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final c in TaskletColor.values)
                    _Cell(
                      tooltip: c.name[0].toUpperCase() + c.name.substring(1),
                      selected: c == _color,
                      size: 18,
                      onTap: () => _pickColor(c),
                      child: ColorDot(color: t.named(c), size: 11),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (_query.trim().isNotEmpty) ...[
                    if (results.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No icons match "${_query.trim()}".',
                            style: TextStyles.bodySecondary(context),
                          ),
                        ),
                      )
                    else ...[
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      grid([for (final i in results) cell(i)]),
                    ],
                  ] else ...[
                    header(recent.isEmpty ? 'Default' : 'Default and Recent'),
                    grid([defaultCell, for (final i in recent) cell(i)]),
                    for (final c in iconCategories) ...[
                      header(c.name),
                      grid([for (final i in c.icons) cell(i)]),
                    ],
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A square, focusable picker cell: arrow keys move between cells, Enter picks.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
    this.size = 32,
  });
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: selected ? t.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: t.hover,
          focusColor: t.selected,
          splashFactory: NoSplash.splashFactory,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
