import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/colors.dart';
import 'glyphs.dart';
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
    Widget chip = Hoverable(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => Container(
        height: 24,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 5 : 8),
        decoration: BoxDecoration(
          color: hovered && onTap != null ? t.hover : Colors.transparent,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
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
                  style: TextStyle(fontSize: 11.5, color: t.secondary),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      chip = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: chip,
      );
    }
    if (tooltip != null) chip = Tooltip(message: tooltip!, child: chip);
    return chip;
  }
}

/// A compact square icon button.
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 26,
    this.iconSize = 15,
    this.color,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget button = Hoverable(
      cursor: onPressed == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active
                ? t.selected
                : (hovered && onPressed != null ? t.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: onPressed == null
                ? t.tertiary
                : (color ?? (active ? t.primary : t.secondary)),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, label: tooltip, child: button);
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
          style: TextStyle(fontSize: 12, color: danger ? t.danger : null),
        ),
      );
    },
  );
}

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
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  },
);

/// An 8-color picker grid inside a menu (projects, labels, views).
class ColorGrid extends StatelessWidget {
  const ColorGrid({
    super.key,
    required this.selected,
    required this.onPick,
    this.dots = false,
  });
  final TaskletColor selected;
  final ValueChanged<TaskletColor> onPick;
  final bool dots;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final c in TaskletColor.values)
            Tooltip(
              message: c.name[0].toUpperCase() + c.name.substring(1),
              child: Hoverable(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: () {
                    onPick(c);
                    MenuController.maybeOf(context)?.close();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c == selected
                          ? t.selected
                          : (hovered ? t.hover : Colors.transparent),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(child: ColorDot(color: t.named(c), size: 12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

/// Asks before a destructive action (projects, labels, views — SPEC §4.5/§4.6/§4.8). Cancel is the default button
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
        borderRadius: BorderRadius.circular(8),
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

/// A collapse chevron: points down when expanded, right when collapsed. Uses a glyph that is optically centred
/// in its box so it lines up with the label next to it.
class Chevron extends StatelessWidget {
  const Chevron({
    super.key,
    required this.collapsed,
    this.size = 14,
    this.color,
  });
  final bool collapsed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: collapsed ? -0.25 : 0,
    duration: const Duration(milliseconds: 120),
    child: Icon(
      Icons.keyboard_arrow_down_rounded,
      size: size,
      color: color ?? Tokens.of(context).tertiary,
    ),
  );
}

/// One option of a [SegmentedIconSwitch].
class SegmentOption<T> {
  const SegmentOption(this.value, this.icon, this.tooltip);
  final T value;
  final IconData icon;
  final String tooltip;
}

/// A compact segmented switch: one pill with a highlight that slides to the selected option (e.g. Board / List).
class SegmentedIconSwitch<T> extends StatelessWidget {
  const SegmentedIconSwitch({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  static const _segment = 30.0;
  static const _height = 26.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final index = options
        .indexWhere((o) => o.value == selected)
        .clamp(0, options.length - 1);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: _height,
      width: _segment * options.length + 4,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            left: index * _segment,
            top: 0,
            bottom: 0,
            width: _segment,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.selected,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Row(
            children: [
              for (final o in options)
                Tooltip(
                  message: o.tooltip,
                  child: Semantics(
                    button: true,
                    selected: o.value == selected,
                    label: o.tooltip,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(o.value),
                        child: SizedBox(
                          width: _segment,
                          child: Center(
                            child: Icon(
                              o.icon,
                              size: 15,
                              color: o.value == selected
                                  ? t.primary
                                  : t.tertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
