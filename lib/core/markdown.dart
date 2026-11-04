// The Markdown a task description shows rendered (docs/DECISIONS.md D17): headings, paragraphs, bullet and numbered
// lists, `- [ ]` checkboxes, code blocks, quotes; inline bold, italic, code, links and bare URLs. The stored text
// stays plain Markdown; anything else shows as written.

sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.spans);
  final int level;
  final List<MdSpan> spans;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);
  final List<MdSpan> spans;
}

class MdQuote extends MdBlock {
  const MdQuote(this.spans);
  final List<MdSpan> spans;
}

/// A list item; [checked] is null for a plain item. [line] is its line in the source, for toggling a checkbox.
class MdListItem extends MdBlock {
  const MdListItem({
    required this.spans,
    required this.line,
    this.number,
    this.checked,
    this.indent = 0,
  });
  final List<MdSpan> spans;
  final int line;
  final int? number;
  final bool? checked;
  final int indent;
}

class MdCode extends MdBlock {
  const MdCode(this.text);
  final String text;
}

class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? link;
}

final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _item = RegExp(r'^(\s*)(?:[-*+]|(\d+)[.)])\s+(?:\[( |x|X)\]\s+)?(.*)$');
final _quote = RegExp(r'^>\s?(.*)$');

/// Blocks of [text], line by line.
List<MdBlock> parseMarkdown(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MdBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(MdParagraph(parseInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      flush();
      final code = <String>[];
      for (
        i++;
        i < lines.length && !lines[i].trimLeft().startsWith('```');
        i++
      ) {
        code.add(lines[i]);
      }
      blocks.add(MdCode(code.join('\n')));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    if (_heading.firstMatch(line) case final m?) {
      flush();
      blocks.add(MdHeading(m.group(1)!.length, parseInline(m.group(2)!)));
    } else if (_item.firstMatch(line) case final m?) {
      flush();
      final box = m.group(3);
      blocks.add(
        MdListItem(
          spans: parseInline(m.group(4)!),
          line: i,
          number: int.tryParse(m.group(2) ?? ''),
          checked: box == null ? null : box != ' ',
          indent: m.group(1)!.replaceAll('\t', '  ').length ~/ 2,
        ),
      );
    } else if (_quote.firstMatch(line) case final m?) {
      flush();
      blocks.add(MdQuote(parseInline(m.group(1)!)));
    } else {
      paragraph.add(line);
    }
  }
  flush();
  return blocks;
}

final _inline = RegExp(
  r'(`[^`]+`)'
  r'|(\*\*[^*]+\*\*|__[^_]+__)'
  r'|(\*[^*\s][^*]*\*|_[^_\s][^_]*_)'
  r'|(\[[^\]]+\]\([^)\s]+\))'
  r'|(https?://[^\s<>()]+[^\s<>().,;:!?])',
);

/// Inline spans of [text]: `code`, **bold**, *italic*, [text](url) and bare http(s) links.
List<MdSpan> parseInline(String text) {
  final spans = <MdSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) spans.add(MdSpan(text.substring(at, m.start)));
    final t = m.group(0)!;
    if (m.group(1) != null) {
      spans.add(MdSpan(t.substring(1, t.length - 1), code: true));
    } else if (m.group(2) != null) {
      spans.add(MdSpan(t.substring(2, t.length - 2), bold: true));
    } else if (m.group(3) != null) {
      spans.add(MdSpan(t.substring(1, t.length - 1), italic: true));
    } else if (m.group(4) != null) {
      final close = t.indexOf('](');
      spans.add(
        MdSpan(
          t.substring(1, close),
          link: t.substring(close + 2, t.length - 1),
        ),
      );
    } else {
      spans.add(MdSpan(t, link: t));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(MdSpan(text.substring(at)));
  return spans;
}

/// [text] with the checkbox on [line] flipped (`- [ ]` <-> `- [x]`); unchanged if that line has none.
String toggleCheckbox(String text, int line) {
  final lines = text.split('\n');
  if (line < 0 || line >= lines.length) return text;
  final l = lines[line];
  final m = RegExp(r'^(\s*(?:[-*+]|\d+[.)])\s+\[)( |x|X)(\].*)$').firstMatch(l);
  if (m == null) return text;
  lines[line] = '${m.group(1)}${m.group(2) == ' ' ? 'x' : ' '}${m.group(3)}';
  return lines.join('\n');
}

/// Whether [text] uses anything [parseMarkdown] renders differently from plain text (else it shows as written).
bool hasMarkdown(String text) => parseMarkdown(text).any(
  (b) => switch (b) {
    MdParagraph(:final spans) => spans.any(
      (s) => s.bold || s.italic || s.code || s.link != null,
    ),
    _ => true,
  },
);
