import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';

/// A task's checklist in the task panel: tick steps, edit them in place, remove them, add one with Enter.
/// [onChanged] receives the whole new list; [newId] makes ids for added steps.
class ChecklistEditor extends StatefulWidget {
  const ChecklistEditor({
    super.key,
    required this.items,
    required this.onChanged,
    required this.newId,
    this.enabled = true,
  });
  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;
  final String Function() newId;
  final bool enabled;

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _replace(ChecklistItem item, ChecklistItem? by) => widget.onChanged([
    for (final i in widget.items)
      if (i.id != item.id) i else ?by,
  ]);

  void _addStep() {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    widget.onChanged([
      ...widget.items,
      ChecklistItem(id: widget.newId(), text: text),
    ]);
    _add.clear();
    _addFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final items = widget.items;
    final done = items.where((i) => i.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Checklist', style: TextStyles.sectionLabel(context)),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('$done/${items.length}', style: TextStyles.meta(context)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        for (final item in items)
          _Step(
            key: ValueKey(item.id),
            item: item,
            enabled: widget.enabled,
            onToggle: () => _replace(item, item.copyWith(done: !item.done)),
            onRename: (text) => _replace(item, item.copyWith(text: text)),
            onRemove: () => _replace(item, null),
          ),
        if (widget.enabled)
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(Icons.add, size: 14, color: t.tertiary),
              ),
              Expanded(
                child: TextField(
                  controller: _add,
                  focusNode: _addFocus,
                  style: TextStyles.body(context),
                  decoration: const InputDecoration(
                    hintText: 'Add a step',
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _addStep(),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Step extends StatefulWidget {
  const _Step({
    super.key,
    required this.item,
    required this.enabled,
    required this.onToggle,
    required this.onRename,
    required this.onRemove,
  });
  final ChecklistItem item;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;

  @override
  State<_Step> createState() => _StepState();
}

class _StepState extends State<_Step> {
  late final _text = TextEditingController(text: widget.item.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Step old) {
    super.didUpdateWidget(old);
    // Changed elsewhere (another computer, Undo) while not being edited here.
    if (!_focus.hasFocus && _text.text != widget.item.text) {
      _text.text = widget.item.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Saves an edited step; an emptied one goes back to its text (remove it with ×).
  void _commit() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _text.text = widget.item.text;
    } else if (text != widget.item.text) {
      widget.onRename(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final item = widget.item;
    return Hoverable(
      builder: (context, hovered) => Row(
        children: [
          SizedBox(
            width: 28,
            child: Checkbox(
              value: item.done,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: widget.enabled ? (_) => widget.onToggle() : null,
            ),
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  _text.text = item.text;
                  _focus.unfocus();
                },
              },
              child: TextField(
                controller: _text,
                focusNode: _focus,
                enabled: widget.enabled,
                style: TextStyles.body(context).copyWith(
                  color: item.done ? t.tertiary : t.primary,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => _focus.unfocus(),
              ),
            ),
          ),
          if (widget.enabled)
            Opacity(
              opacity: hovered || _focus.hasFocus ? 1 : 0,
              child: IconBtn(
                icon: Icons.close,
                size: 22,
                iconSize: 13,
                tooltip: 'Remove step',
                onPressed: widget.onRemove,
              ),
            ),
        ],
      ),
    );
  }
}
