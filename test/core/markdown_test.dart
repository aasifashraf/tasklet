import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/core/markdown.dart';

void main() {
  test('blocks', () {
    final blocks = parseMarkdown(
      '# Plan\n'
      'Some text\non two lines\n'
      '\n'
      '- [ ] write it\n'
      '- [x] ship it\n'
      '  - nested\n'
      '1. first\n'
      '> quoted\n'
      '```\ncode **not bold**\n```\n',
    );
    expect(blocks[0], isA<MdHeading>());
    expect(
      (blocks[1] as MdParagraph).spans.single.text,
      'Some text\non two lines',
    );
    final todo = blocks[2] as MdListItem;
    expect((todo.checked, todo.line), (false, 4));
    expect((blocks[3] as MdListItem).checked, isTrue);
    expect((blocks[4] as MdListItem).indent, 1);
    expect((blocks[5] as MdListItem).number, 1);
    expect(blocks[6], isA<MdQuote>());
    expect((blocks[7] as MdCode).text, 'code **not bold**');
  });

  test('inline', () {
    final spans = parseInline(
      'Use **bold**, *it*, `x = 1`, [docs](https://a.dev/x) and https://b.dev/y.',
    );
    expect(spans.where((s) => s.bold).single.text, 'bold');
    expect(spans.where((s) => s.italic).single.text, 'it');
    expect(spans.where((s) => s.code).single.text, 'x = 1');
    final links = spans.where((s) => s.link != null).toList();
    expect(links.map((s) => (s.text, s.link)), [
      ('docs', 'https://a.dev/x'),
      ('https://b.dev/y', 'https://b.dev/y'), // the full stop isn't part of it
    ]);
  });

  test('toggle a checkbox in place', () {
    const text = 'Steps:\n- [ ] one\n- [x] two';
    expect(toggleCheckbox(text, 1), 'Steps:\n- [x] one\n- [x] two');
    expect(toggleCheckbox(text, 2), 'Steps:\n- [ ] one\n- [ ] two');
    expect(toggleCheckbox(text, 0), text);
  });

  test('plain text is left alone', () {
    expect(hasMarkdown('Just a note.\nAnother line.'), isFalse);
    expect(hasMarkdown('See https://x.dev'), isTrue);
    expect(hasMarkdown('- item'), isTrue);
  });
}
