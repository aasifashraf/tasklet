import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/markdown.dart';
import '../theme.dart';

/// A task description rendered from its Markdown (D17). Checkboxes call [onToggle] with their source line; links
/// open in the browser (http and https only); a click anywhere else calls [onEdit].
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    required this.onToggle,
    required this.onEdit,
    this.enabled = true,
  });
  final String text;
  final ValueChanged<int> onToggle;
  final VoidCallback onEdit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = TextStyles.bodyLarge(context).copyWith(height: 1.5);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.text : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onEdit : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in parseMarkdown(text))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: switch (block) {
                  MdHeading(:final level, :final spans) => _rich(
                    context,
                    spans,
                    TextStyles.section(
                      context,
                    ).copyWith(fontWeight: level == 1 ? FontWeight.w700 : null),
                  ),
                  MdParagraph(:final spans) => _rich(context, spans, base),
                  MdQuote(:final spans) => Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: t.border, width: 3),
                      ),
                    ),
                    child: _rich(
                      context,
                      spans,
                      base.copyWith(color: t.secondary),
                    ),
                  ),
                  MdCode(:final text) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(Radii.small),
                    ),
                    child: SelectableText(
                      text,
                      style: TextStyles.code(context),
                    ),
                  ),
                  MdListItem() => _item(context, block, base),
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, MdListItem item, TextStyle base) {
    final t = Tokens.of(context);
    final checked = item.checked;
    return Padding(
      padding: EdgeInsets.only(left: 18.0 * item.indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: checked == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      item.number == null ? '•' : '${item.number}.',
                      style: base.copyWith(color: t.secondary),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: SizedBox.square(
                      dimension: 16,
                      child: Checkbox(
                        value: checked,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onChanged: enabled ? (_) => onToggle(item.line) : null,
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: _rich(
              context,
              item.spans,
              checked == true
                  ? base.copyWith(
                      color: t.tertiary,
                      decoration: TextDecoration.lineThrough,
                    )
                  : base,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rich(BuildContext context, List<MdSpan> spans, TextStyle style) {
    final t = Tokens.of(context);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final s in spans)
            TextSpan(
              text: s.text,
              style: TextStyle(
                fontWeight: s.bold ? FontWeight.w600 : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                fontFamily: s.code ? TextStyles.code(context).fontFamily : null,
                fontFamilyFallback: s.code
                    ? TextStyles.code(context).fontFamilyFallback
                    : null,
                backgroundColor: s.code ? t.hover : null,
                color: s.link != null ? t.accent : null,
                decoration: s.link != null ? TextDecoration.underline : null,
              ),
              recognizer: s.link == null ? null : _open(s.link!),
              mouseCursor: s.link == null ? null : SystemMouseCursors.click,
            ),
        ],
      ),
    );
  }

  /// Opens web links only: a description is user text, so `file:` or other schemes are never launched.
  TapGestureRecognizer? _open(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return TapGestureRecognizer()
      ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
