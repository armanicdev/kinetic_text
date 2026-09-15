import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

const style = TextStyle(fontSize: 20);

ShapedText shape(String text,
        {TextUnit unit = TextUnit.grapheme,
        TextDirection dir = TextDirection.ltr,
        double maxWidth = double.infinity}) =>
    ShapedText.shape(
      span: TextSpan(text: text, style: style),
      text: text,
      direction: dir,
      unit: unit,
      maxWidth: maxWidth,
    );

void main() {
  test('graphemes: whitespace is never a unit, units read left to right', () {
    final s = shape('Hello world');
    expect(s.units.length, 10);
    expect(s.units.first.start, 0);
    expect(s.units[5].start, 6, reason: 'the space at 5 is skipped');
    for (var i = 1; i < s.units.length; i++) {
      expect(s.units[i].rect.left, greaterThan(s.units[i - 1].rect.left));
      expect(s.units[i].index, i);
    }
    s.dispose();
  });

  test('words: one unit per run of ink', () {
    final s = shape('Hello  brave world', unit: TextUnit.word);
    expect(s.units.length, 3);
    expect((s.units[1].start, s.units[1].end), (7, 12));
    expect(s.text.substring(s.units[2].start, s.units[2].end), 'world');
    s.dispose();
  });

  test('lines: a wrapped paragraph yields one unit per line', () {
    final s = shape('one two three four five six', unit: TextUnit.line, maxWidth: 90);
    expect(s.lines.length, greaterThan(1));
    expect(s.units.length, s.lines.length);
    for (final u in s.units) {
      expect(u.line, u.index);
    }
    s.dispose();
  });

  test('RTL: reading order is right to left physically', () {
    final s = shape('سڵاو دنیا', dir: TextDirection.rtl);
    expect(s.units.length, greaterThan(2));
    expect(s.units.first.rect.left, greaterThan(s.units.last.rect.left));
    s.dispose();
  });

  test('a run resolves to its units and a cell is open past a single line', () {
    final s = shape('Pay 12,000 IQD');
    final amount = s.unitsInRange(4, 10);
    expect(amount.length, 6);
    expect(s.text.substring(s.units[amount.first].start, s.units[amount.last].end), '12,000');
    final cell = s.cellOf(s.units.first);
    expect(cell.top, lessThan(0));
    expect(cell.bottom, greaterThan(s.height));
    final grown = s.cellOf(s.units.first, scale: 1.5);
    expect(grown.width, closeTo(cell.width * 1.5, 0.01));
    s.dispose();
  });

  test('lineRectsOf groups a slice per wrapped line', () {
    final s = shape('one two three four five six', unit: TextUnit.word, maxWidth: 120);
    final all = [for (final u in s.units) u.index];
    final pieces = s.lineRectsOf(all);
    expect(pieces.length, s.lines.length);
    s.dispose();
  });
}
