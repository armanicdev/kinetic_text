// Glyph-exact rendering, checked on real Kurdish shaped with Leraw (OFL,
// test/fonts): a moving letter carries all of its ink — the tail of ڕ and the
// V under it — and leaves none of it behind on its neighbours.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

const _font = 'test/fonts/Leraw.ttf';
const leraw = 'Leraw';
const kurdish = 'پشتڕاستکراوەتەوە';
const pad = 40.0;

final bool _haveFont = File(_font).existsSync();

ShapedText shapeKurdish({
  String text = kurdish,
  InlineSpan? span,
  double size = 40,
  Color color = const Color(0xFF000000),
  TextUnit unit = TextUnit.grapheme,
  int? maxLines,
  String? ellipsis,
  double maxWidth = double.infinity,
}) =>
    ShapedText.shape(
      span: span ??
          TextSpan(
            text: text,
            style: TextStyle(fontFamily: leraw, fontSize: size, color: color),
          ),
      text: text,
      direction: TextDirection.rtl,
      unit: unit,
      maxLines: maxLines,
      ellipsis: ellipsis,
      maxWidth: maxWidth,
    );

/// RGBA bytes of [draw] on a transparent canvas the size of [s] plus [pad].
Future<Uint8List> render(ShapedText s, void Function(Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.translate(pad, pad);
  draw(canvas);
  final w = (s.width + pad * 2).ceil();
  final h = (s.height + pad * 2).ceil();
  final image = await rec.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

int alphaSum(Uint8List px) {
  var sum = 0;
  for (var i = 3; i < px.length; i += 4) {
    sum += px[i];
  }
  return sum;
}

/// The largest per-pixel alpha difference between `over(top, bottom)` and
/// [want].
int compositeError(Uint8List bottom, Uint8List top, Uint8List want) {
  var worst = 0;
  for (var i = 3; i < want.length; i += 4) {
    final a = top[i] / 255;
    final b = bottom[i] / 255;
    final got = ((a + b * (1 - a)) * 255).round();
    final d = (got - want[i]).abs();
    if (d > worst) worst = d;
  }
  return worst;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_haveFont) return;
    final bytes = File(_font).readAsBytesSync();
    await (FontLoader(leraw)..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });

  test('ڕ moves whole: its tail and mark come with it and nothing stays behind',
      () async {
    final s = shapeKurdish();
    final reh = s.units.indexWhere((u) => s.text.substring(u.start, u.end) == 'ڕ');
    expect(reh, isNot(-1));
    final all = await render(s, (c) => s.painter.paint(c, Offset.zero));
    final alone = await render(s, (c) => s.paintUnits(c, [reh]));
    final rest = await render(s, (c) {
      s.paintExcept(c, [for (final u in s.units) u.index == reh]);
    });
    // The two halves stack back into the whole, pixel for pixel.
    expect(compositeError(rest, alone, all), lessThanOrEqualTo(3));

    // And the old cut — the letter's box — would have sliced it: ڕ owns ink
    // outside its own box, which the box would have left behind.
    final box = await render(s, (c) {
      c.save();
      c.clipRect(s.units[reh].rect);
      s.painter.paint(c, Offset.zero);
      c.restore();
    });
    expect(alphaSum(alone), greaterThan(alphaSum(box) + 255 * 20),
        reason: 'the tail and the V reach past the letter\'s box');
    s.dispose();
  }, skip: !_haveFont);

  test('a unit posed far away leaves exactly the rest of the word', () async {
    final s = shapeKurdish();
    final reh = s.units.indexWhere((u) => s.text.substring(u.start, u.end) == 'ڕ');
    final poses = List.generate(s.units.length, (_) => UnitPose());
    poses[reh].dy = 4000; // off the canvas
    final frame = TextFrame(shaped: s, progress: 1, time: 0, poses: poses);
    final moved = await render(s, (c) => paintGlyphs(c, frame));
    final rest = await render(s, (c) {
      s.paintExcept(c, [for (final u in s.units) u.index == reh]);
    });
    var worst = 0;
    for (var i = 3; i < rest.length; i += 4) {
      final d = (moved[i] - rest[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, lessThanOrEqualTo(2));
    s.dispose();
  }, skip: !_haveFont);

  test('class twins stack back into the original, nested styles included',
      () async {
    final span = TextSpan(
      style: const TextStyle(
          fontFamily: leraw, fontSize: 30, color: Color(0xFF123456)),
      children: [
        const TextSpan(text: 'ناسنامەکەت '),
        TextSpan(
          text: kurdish,
          style: TextStyle(foreground: Paint()..color = const Color(0xFFAA0033)),
        ),
        const TextSpan(text: ' Pay 12,000', style: TextStyle(fontSize: 26)),
      ],
    );
    final s = shapeKurdish(span: span, text: span.toPlainText());
    expect(s.classCount, greaterThan(1));
    final all = await render(s, (c) => s.painter.paint(c, Offset.zero));
    final stacked = await render(s, (c) {
      for (var k = 0; k < s.classCount; k++) {
        s.classTwin(k).paint(c, Offset.zero);
      }
    });
    var worst = 0;
    for (var i = 0; i < all.length; i++) {
      final d = (all[i] - stacked[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, lessThanOrEqualTo(3));
    s.dispose();
  }, skip: !_haveFont);

  test('an underline and a background stay whole under a moving letter',
      () async {
    final span = TextSpan(
      style: const TextStyle(
        fontFamily: leraw,
        fontSize: 30,
        color: Color(0xFF000000),
        decoration: TextDecoration.underline,
      ),
      children: [
        const TextSpan(text: 'ناسنامەکەت '),
        const TextSpan(
            text: kurdish, style: TextStyle(backgroundColor: Color(0x3300AA00))),
      ],
    );
    final s = shapeKurdish(span: span, text: span.toPlainText());
    final pick = s.units.length ~/ 2;
    final all = await render(s, (c) => s.painter.paint(c, Offset.zero));
    final alone = await render(s, (c) => s.paintUnits(c, [pick]));
    final rest = await render(s, (c) {
      s.paintExcept(c, [for (final u in s.units) u.index == pick]);
    });
    expect(compositeError(rest, alone, all), lessThanOrEqualTo(6));
    s.dispose();
  }, skip: !_haveFont);

  test('an ellipsis survives while a letter moves', () async {
    final s = shapeKurdish(
      text: 'پسووڵەکەت ئامادەیە. لێرە پارەکەی بدە و پسووڵەکەت هەڵبگرە.',
      maxLines: 1,
      ellipsis: '…',
      maxWidth: 260,
    );
    final all = await render(s, (c) => s.painter.paint(c, Offset.zero));
    final rest = await render(s, (c) {
      s.paintExcept(c, [for (final u in s.units) u.index == 0]);
    });
    final alone = await render(s, (c) => s.paintUnits(c, [0]));
    expect(compositeError(rest, alone, all), lessThanOrEqualTo(3));
    s.dispose();
  }, skip: !_haveFont);

  test('units of one class never reach into each other', () {
    final s = shapeKurdish(
      text: 'پسووڵەکەت ئامادەیە. لێرە پارەکەی بدە و پسووڵەکەت هەڵبگرە.',
      maxWidth: 300,
    );
    expect(s.lines.length, greaterThan(1));
    for (final a in s.units) {
      for (final b in s.units) {
        if (a.index >= b.index || s.classOf(a.index) != s.classOf(b.index)) {
          continue;
        }
        expect(s.cellOf(a).overlaps(s.cellOf(b)), isFalse,
            reason: '${a.index} and ${b.index} share class ${s.classOf(a.index)}');
      }
    }
    expect(s.classCount, lessThanOrEqualTo(12), reason: 'a handful of twins');
    s.dispose();
  }, skip: !_haveFont);

  test('Outline traces in the text\'s own colour by default', () async {
    Future<(double, double, double)> ringColour(Outline effect) async {
      final s = shapeKurdish(color: const Color(0xFFE01010));
      final poses = List.generate(s.units.length, (_) => UnitPose());
      // Early in the reveal: the rings are drawn, no fill has risen yet.
      final frame = TextFrame(shaped: s, progress: 0.3, time: 0, poses: poses);
      effect.apply(frame, UnitSlice([for (final u in s.units) u.index]));
      final px = await render(s, (c) => paintFrame(c, frame));
      var r = 0.0, g = 0.0, b = 0.0, n = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i + 3] < 200) continue;
        r += px[i];
        g += px[i + 1];
        b += px[i + 2];
        n++;
      }
      s.dispose();
      expect(n, greaterThan(20), reason: 'the rings are drawn');
      return (r / n, g / n, b / n);
    }

    final own = await ringColour(const Outline(stagger: 0));
    expect(own.$1, greaterThan(180));
    expect(own.$2, lessThan(60));
    final blue = await ringColour(const Outline(color: Color(0xFF1030E0), stagger: 0));
    expect(blue.$3, greaterThan(180));
    expect(blue.$1, lessThan(60));
  }, skip: !_haveFont);
}
