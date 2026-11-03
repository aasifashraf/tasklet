import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Rebuilds [builder] with the current hover state.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// The one clickable shell: hover, keyboard focus (accent ring, shown only when focus came from the keyboard),
/// Enter/Space activation, click cursor, disabled state and button semantics. [builder] paints the hover and
/// selected backgrounds; its `hovered` is also true while keyboard focus is on it or inside it, so hover-only
/// affordances (a row's ⋯) appear for keyboard users too. [borderRadius] matches its shape so the ring follows it.
/// A null [onTap] is a disabled button: no hover, no focus, tertiary styling is up to [builder].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.borderRadius = Radii.small,
    this.onDoubleTap,
    this.selected,
    this.semanticLabel,
    this.tooltip,
  });
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget Function(BuildContext context, bool hovered) builder;
  final double borderRadius;
  final bool? selected;
  final String? semanticLabel;
  final String? tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  // Repaints when focus moves between this widget and something inside it (hasFocus stays true, the ring moves).
  late final _node = FocusNode()
    ..addListener(() {
      if (mounted) setState(() {});
    });
  bool _hovered = false;

  /// Keyboard focus is on this widget or inside it (FocusableActionDetector reports focus within).
  bool _focusWithin = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(widget.borderRadius);
    final ring = enabled && _focusWithin && _node.hasPrimaryFocus;
    Widget child = FocusableActionDetector(
      focusNode: _node,
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focusWithin = v),
      actions: {
        if (enabled)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => onTap(),
          ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: enabled ? widget.onDoubleTap : null,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ring
              ? BoxDecoration(
                  border: Border.all(
                    color: Tokens.of(context).accent,
                    width: 2,
                  ),
                  borderRadius: radius,
                )
              : const BoxDecoration(),
          child: widget.builder(context, enabled && (_hovered || _focusWithin)),
        ),
      ),
    );
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel ?? widget.tooltip,
      // An explicit label replaces what the children would read ("Expand Projects", not "Projects").
      excludeSemantics: widget.semanticLabel != null,
      child: child,
    );
  }
}

/// The one property-pill shell used everywhere (SPEC §8.5): 24px tall, hairline border, small icon + text.
class PropChip extends StatelessWidget {
  const PropChip({
    super.key,
    this.icon,
    this.label,
    this.onTap,
    this.tooltip,
    this.maxLabelWidth = 140,
  });
  final Widget? icon;
  final String? label;
  final VoidCallback? onTap;
  final String? tooltip;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget shell(bool hovered) => Container(
      height: 24,
      padding: EdgeInsets.symmetric(horizontal: label == null ? 5 : 8),
      decoration: BoxDecoration(
        color: hovered ? t.hover : Colors.transparent,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?icon,
          if (icon != null && label != null) const SizedBox(width: 5),
          if (label != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.chip(context),
              ),
            ),
        ],
      ),
    );
    // A chip without onTap only shows a value (card chips in read-only mode), so it isn't a button.
    if (onTap == null) {
      final chip = shell(false);
      return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
    }
    return Pressable(
      onTap: onTap,
      borderRadius: Radii.large,
      tooltip: tooltip,
      builder: (context, hovered) => shell(hovered),
    );
  }
}

/// A compact square icon button.
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 26,
    this.iconSize = 15,
    this.color,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;

  /// Icon-only, so the tooltip is also its screen-reader label.
  final String tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      selected: active ? true : null,
      builder: (context, hovered) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? t.selected : (hovered ? t.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: onPressed == null
              ? t.tertiary
              : (color ?? (active ? t.primary : t.secondary)),
        ),
      ),
    );
  }
}

/// Explains why a page is empty and what to do next (SPEC §8.7).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon,
  });
  final String title;
  final String message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 28, color: t.tertiary),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                style: TextStyles.section(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: TextStyles.bodySecondary(context),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a context menu at the pointer on right-click (and on long-press for touch).
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.menuChildren,
    required this.child,
    this.onOpen,
  });
  final List<Widget> Function() menuChildren;
  final Widget child;
  final VoidCallback? onOpen;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final _controller = MenuController();

  void _open(Offset localPosition) {
    widget.onOpen?.call();
    _controller.open(position: localPosition);
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    menuChildren: _controller.isOpen ? widget.menuChildren() : const [],
    builder: (context, controller, child) => GestureDetector(
      onSecondaryTapDown: (d) {
        // Build the children for this opening, then open on the next frame.
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _open(d.localPosition),
        );
      },
      onLongPressStart: (d) => _open(d.localPosition),
      child: child,
    ),
    child: widget.child,
  );
}

/// Builds menu items lazily; wrap a widget's children so they're computed when the menu opens.
Widget menuItem(
  String label, {
  VoidCallback? onPressed,
  Widget? leading,
  bool checked = false,
  bool danger = false,
  MenuSerializableShortcut? shortcut,
  String? hint,
  BuildContext? context,
}) {
  return Builder(
    builder: (context) {
      final t = Tokens.of(context);
      return MenuItemButton(
        onPressed: onPressed,
        shortcut: shortcut,
        leadingIcon: SizedBox(
          width: 16,
          child:
              leading ??
              (checked ? Icon(Icons.check, size: 14, color: t.primary) : null),
        ),
        trailingIcon: hint == null
            ? null
            : Text(hint, style: TextStyles.meta(context)),
        child: Text(
          label,
          style: TextStyle(
            color: danger
                ? (onPressed == null
                      ? t.danger.withValues(alpha: 0.4)
                      : t.danger)
                : null,
          ),
        ),
      );
    },
  );
}

/// A "Label ▸" submenu row whose label lines up with [menuItem]s (same 16 px leading slot). With no children it
/// is disabled and its label tertiary.
Widget submenuItem(
  String label, {
  required List<Widget> menuChildren,
  Widget? leading,
}) => Builder(
  builder: (context) => SubmenuButton(
    menuChildren: menuChildren,
    leadingIcon: SizedBox(width: 16, child: leading),
    child: Text(
      label,
      style: TextStyle(
        color: menuChildren.isEmpty ? Tokens.of(context).tertiary : null,
      ),
    ),
  ),
);

/// A checkable menu row with a check mark on the right (status/priority/label pickers).
Widget checkItem(
  String label, {
  required bool checked,
  required VoidCallback? onPressed,
  Widget? leading,
}) => Builder(
  builder: (context) {
    final t = Tokens.of(context);
    return MenuItemButton(
      onPressed: onPressed,
      closeOnActivate: true,
      leadingIcon: SizedBox(width: 16, child: leading),
      trailingIcon: SizedBox(
        width: 16,
        child: checked ? Icon(Icons.check, size: 14, color: t.primary) : null,
      ),
      child: Text(label),
    );
  },
);

/// A single-line text field that commits on Enter/blur and cancels on Escape (SPEC §4.5 inline create/rename).
/// [onCommit] receives the trimmed text; [onCancel] runs when Escape is pressed or the text is empty/unchanged on
/// blur.
class InlineEditField extends StatefulWidget {
  const InlineEditField({
    super.key,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    this.hint = 'Name',
    this.maxLength,
    this.onChanged,
    this.style,
  });
  final String initial;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final String hint;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;

  @override
  State<InlineEditField> createState() => _InlineEditFieldState();
}

class _InlineEditFieldState extends State<InlineEditField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(commit: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _finish({required bool commit}) {
    if (_done) return;
    _done = true;
    final text = _controller.text.trim();
    if (commit && text.isNotEmpty && text != widget.initial.trim()) {
      widget.onCommit(text);
    } else {
      widget.onCancel();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          _finish(commit: false),
    },
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: (_) => _finish(commit: true),
      style: widget.style ?? TextStyles.body(context),
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    ),
  );
}

/// Asks before a destructive action (projects, labels, views; SPEC §4.5/§4.6/§4.8). Cancel is the default button
/// and Escape cancels (docs/DECISIONS.md D8). Returns true only if the user confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final t = Tokens.of(context);
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyles.section(context)),
              const SizedBox(height: 8),
              Text(message, style: TextStyles.bodySecondary(context)),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: t.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// A small muted count shown next to sidebar items and headers.
class CountText extends StatelessWidget {
  const CountText(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) =>
      Text('$count', style: TextStyles.meta(context));
}

/// A slim banner for non-blocking notices (sync conflicts, unreadable files, read-only folder).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    this.actions = const [],
    this.onDismiss,
  });
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: t.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyles.bodySecondary(context)),
          ),
          ...actions,
          if (onDismiss != null)
            IconBtn(
              icon: Icons.close,
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

/// A small filled disclosure triangle: ▾ when expanded, ▸ when collapsed. Painted rather than taken from an icon
/// font, so it is exactly centred on the label beside it.
class DisclosureTriangle extends StatelessWidget {
  const DisclosureTriangle({
    super.key,
    required this.collapsed,
    this.size = 8,
    this.color,
  });
  final bool collapsed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: collapsed ? -0.25 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.fast,
    child: CustomPaint(
      size: Size.square(size),
      painter: _TrianglePainter(color ?? Tokens.of(context).tertiary),
    ),
  );
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A downward triangle centred in the box (rotation turns it to point right).
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.28)
      ..lineTo(w * 0.9, h * 0.28)
      ..lineTo(w * 0.5, h * 0.78)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
