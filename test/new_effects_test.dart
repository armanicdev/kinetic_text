import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

Widget host(Widget child, {bool reduce = false, TextDirection dir = TextDirection.ltr}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: dir,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
          child: Center(child: child),
        ),
      ),
    );

void main() {
  test('direction comes from the first strong letter', () {
    expect(ShapedText.directionOf('Hello!'), TextDirection.ltr);
    expect(ShapedText.directionOf('سڵاو دنیا'), TextDirection.rtl);
    expect(ShapedText.directionOf('12,000 د.ع'), TextDirection.rtl,
        reason: 'figures are weak; the first letter decides');
    expect(ShapedText.directionOf('12,000'), isNull, reason: 'no letter at all');
    expect(ShapedText.directionOf('🙂 ✓'), isNull);
    expect(ShapedText.directionOf('\u2067abc\u2069 سڵاو'), TextDirection.rtl,
        reason: 'an isolated run does not count');
    expect(ShapedText.directionOf('\u200Fabc'), TextDirection.rtl, reason: 'a mark is strong');
    expect(ShapedText.directionOf('Éclair'), TextDirection.ltr);
    expect(ShapedText.directionOf('שלום'), TextDirection.rtl);
  });

  test('a slice reads in its own direction, inside a paragraph of another', () {
    const text = 'Pay پارە now';
    final s = ShapedText.shape(
      span: const TextSpan(text: text, style: TextStyle(fontSize: 20)),
      text: text,
      direction: TextDirection.ltr,
      unit: TextUnit.word,
    );
    expect(s.readingDirectionOf([0]), TextDirection.ltr);
    expect(s.readingDirectionOf([1]), TextDirection.rtl);
    expect(s.readingDirectionOf([0, 1, 2]), TextDirection.ltr);
    s.dispose();
  });

  test('sweeps start at the reading start and cross the whole slice', () {
    const b = 0.2;
    expect(Sweep.centers(SweepOrigin.reading, 0, b, rtl: false).single, closeTo(-b, 1e-9));
    expect(Sweep.centers(SweepOrigin.reading, 0, b, rtl: true).single, closeTo(1 + b, 1e-9));
    expect(Sweep.centers(SweepOrigin.left, 0, b, rtl: true).single, closeTo(-b, 1e-9));
    expect(Sweep.centers(SweepOrigin.end, 0, b, rtl: false).single, closeTo(1 + b, 1e-9));
    final mid = Sweep.centers(SweepOrigin.center, 0, b, rtl: false);
    expect(mid, [0.5, 0.5]);
    final out = Sweep.centers(SweepOrigin.center, 1, b, rtl: false);
    expect(out.first, closeTo(-b, 1e-9));
    expect(out.last, closeTo(1 + b, 1e-9));
    final (stops, weights) = Sweep.maskStops([0.3, 0.7], b);
    for (var i = 1; i < stops.length; i++) {
      expect(stops[i], greaterThanOrEqualTo(stops[i - 1]));
    }
    expect(weights[stops.indexOf(0.3)], 1);
  });

  test('a wipe is hidden at the start, whole at the end, and reads its way', () {
    for (final o in SweepOrigin.values) {
      for (final x in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(Wipe.maskAt(o, x, 0, 0.3, rtl: false), 0, reason: '$o at $x');
        expect(Wipe.maskAt(o, x, 1, 0.3, rtl: false), 1, reason: '$o at $x');
      }
    }
    // Half-way, a Kurdish slice is uncovered on the right, an English one on
    // the left.
    expect(Wipe.maskAt(SweepOrigin.reading, 0.9, 0.5, 0.2, rtl: true), 1);
    expect(Wipe.maskAt(SweepOrigin.reading, 0.1, 0.5, 0.2, rtl: true), 0);
    expect(Wipe.maskAt(SweepOrigin.reading, 0.1, 0.5, 0.2, rtl: false), 1);
    expect(Wipe.maskAt(SweepOrigin.center, 0.5, 0.5, 0.2, rtl: false), 1);
    expect(Wipe.maskAt(SweepOrigin.center, 0.0, 0.5, 0.2, rtl: false), 0);
  });

  test('rainbow colours turn through every hue from a seed', () {
    final ring = rainbowColors(seed: const Color(0xFF006DFD), steps: 6);
    expect(ring.length, 6);
    expect(ring.toSet().length, 6);
    expect(colorAround(ring, 0), ring.first);
    expect(colorAround(ring, 1), ring.first, reason: 'a ring wraps');
    expect(Shimmer.rainbow().colors!.length, 7);
    expect(Outline.rainbow().colors!.length, 7);
    expect(Glint.rainbow().sheen.length, 7);
  });

  test('the new effects compare by value', () {
    expect(const Prism(), const Prism());
    expect(const Prism(turn: 0.5), isNot(const Prism()));
    expect(const Wipe(), const Wipe());
    expect(const Wipe(origin: SweepOrigin.center), isNot(const Wipe()));
    expect(const Flip(), const Flip());
    expect(const Flip(axis: Axis.vertical), isNot(const Flip()));
    expect(const Tumble(), const Tumble());
    expect(const Glow(), const Glow());
    expect(const Glow(period: Duration(seconds: 2)), isNot(const Glow()));
    expect(const Sway(), const Sway());
    expect(const Outline(), const Outline());
    expect(const Outline(fill: false), isNot(const Outline()));
    expect(const Shimmer(origin: SweepOrigin.center), isNot(const Shimmer()));
    expect(const Spotlight(origin: SweepOrigin.edges), isNot(const Spotlight()));
    expect(const Glow().continuous, isFalse);
    expect(const Glow(period: Duration(seconds: 2)).continuous, isTrue);
    expect(const Glow().motionOnly, isFalse);
    expect(const Sway().continuous, isTrue);
  });

  test('a prism leaves every letter in its own ink at the end', () {
    const text = 'Rainbow';
    final s = ShapedText.shape(
      span: const TextSpan(text: text, style: TextStyle(fontSize: 20)),
      text: text,
      direction: TextDirection.ltr,
    );
    final poses = List.generate(s.units.length, (_) => UnitPose());
    final all = UnitSlice([for (final u in s.units) u.index]);
    final mid = TextFrame(shaped: s, progress: 0.4, time: 0, poses: poses);
    const Prism().apply(mid, all);
    expect(mid.ink, isNotEmpty, reason: 'washed in hues on the way in');
    for (final p in poses) {
      p.reset();
    }
    final end = TextFrame(shaped: s, progress: 1, time: 0, poses: poses);
    const Prism().apply(end, all);
    expect(end.ink, isEmpty);
    expect(end.anyPosed, isFalse);
    s.dispose();
  });

  test('a pose turns and tilts about its pivot', () {
    const text = 'Flip';
    final s = ShapedText.shape(
      span: const TextSpan(text: text, style: TextStyle(fontSize: 20)),
      text: text,
      direction: TextDirection.ltr,
    );
    final u = s.units.first;
    final pose = UnitPose()
      ..rotation = 0.3
      ..pivot = UnitPivot.baseline;
    final m = poseMatrix(s, u, pose);
    final pivot = Offset(u.rect.center.dx, s.lineOf(u).baseline);
    expect(MatrixUtils.transformPoint(m, pivot), offsetMoreOrLessEquals(pivot));
    final flipped = poseMatrix(s, u, UnitPose()..rotateX = 1.2);
    final r = MatrixUtils.transformRect(flipped, u.rect);
    expect(r.height, lessThan(u.rect.height), reason: 'tilted away, it foreshortens');
    expect(UnitPose().isIdentity, isTrue);
    expect((UnitPose()..rotateY = 0.1).isIdentity, isFalse);
    s.dispose();
  });

  testWidgets('every new effect plays or loops, in both directions', (tester) async {
    const accent = Color(0xFF3366FF);
    for (final dir in TextDirection.values) {
      final text = dir == TextDirection.rtl ? 'پشتڕاستکراوەتەوە' : 'Autumn Sale 2026';
      for (final effect in <TextEffect>[
        const Prism(),
        Prism(colors: rainbowColors(seed: accent)),
        const Wipe(),
        const Wipe(origin: SweepOrigin.center),
        const Wipe(origin: SweepOrigin.edges),
        const Flip(),
        const Flip(axis: Axis.vertical),
        const Tumble(),
        const Outline(),
        Outline.rainbow(),
        const Outline(fill: false),
        Glint.rainbow(),
      ]) {
        await tester.pumpWidget(host(
          KineticText(text, effects: [effect], duration: const Duration(milliseconds: 300)),
          dir: dir,
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.takeException(), isNull, reason: '$effect $dir');
        }
        expect(tester.binding.transientCallbackCount, 0, reason: '$effect is a one-shot');
      }
      for (final effect in <TextEffect>[
        Shimmer.rainbow(),
        const Shimmer(origin: SweepOrigin.center),
        const Shimmer(origin: SweepOrigin.edges, colors: [accent, Color(0xFFFF00FF)]),
        const Spotlight(origin: SweepOrigin.center, focus: accent),
        const Glow(color: accent, period: Duration(milliseconds: 900)),
        const Sway(),
      ]) {
        await tester.pumpWidget(host(KineticText(text, effects: [effect]), dir: dir));
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.binding.transientCallbackCount, greaterThan(0), reason: '$effect loops');
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 330));
          expect(tester.takeException(), isNull, reason: '$effect $dir');
        }
        await tester.pumpWidget(host(const SizedBox()));
      }
    }
    // A steady glow needs no clock.
    await tester.pumpWidget(host(const KineticText('Neon', effects: [Glow()])));
    await tester.pump(const Duration(seconds: 1)); // past the autoplay run
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a label reads in its own direction unless told', (tester) async {
    SemanticsNode node() => tester.getSemantics(find.byType(KineticText));
    await tester.pumpWidget(host(const KineticText('Hello!'), dir: TextDirection.rtl));
    expect(node().textDirection, TextDirection.ltr);
    await tester.pumpWidget(host(const KineticText('سڵاو!')));
    expect(node().textDirection, TextDirection.rtl);
    await tester.pumpWidget(host(const KineticText('12,000'), dir: TextDirection.rtl));
    expect(node().textDirection, TextDirection.rtl, reason: 'no letter: the page decides');
    await tester.pumpWidget(host(const KineticText('Hello!', textDirection: TextDirection.rtl)));
    expect(node().textDirection, TextDirection.rtl, reason: 'told');
  });

  testWidgets('a ticker turns Arabic-Indic digits on their own ring', (tester) async {
    await tester.pumpWidget(host(const TickerText('١٢٣')));
    await tester.pump();
    await tester.pumpWidget(host(const TickerText('١٢٩')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'rolling');
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byType(TickerText)).label, '١٢٩');
    // Switching scripts cross-fades instead of rolling through the wrong ring.
    await tester.pumpWidget(host(const TickerText('130')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
