import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

void main() {
  _rollTests();
  test('staggered: first starts at once, last starts at the stagger', () {
    expect(staggered(0, 0, 5, 0.5), 0);
    expect(staggered(0.5, 0, 5, 0.5), 1);
    expect(staggered(0.5, 4, 5, 0.5), 0);
    expect(staggered(1, 4, 5, 0.5), 1);
    expect(staggered(0.75, 4, 5, 0.5), closeTo(0.5, 1e-9));
    expect(staggered(0.3, 0, 1, 0.5), closeTo(0.3, 1e-9), reason: 'a lone unit has no stagger');
  });

  test('rank orders are permutations', () {
    const slice = UnitSlice([0, 1, 2, 3, 4, 5, 6]);
    for (final order in StaggerOrder.values) {
      final ranks = [for (var k = 0; k < 7; k++) slice.rank(k, order)];
      expect(ranks.every((r) => r >= 0 && r < 7), isTrue, reason: '$order');
      if (order == StaggerOrder.center || order == StaggerOrder.edges) {
        // Mirror pairs move together: symmetric, not a permutation.
        expect(ranks, ranks.reversed.toList(), reason: '$order');
      } else {
        expect(ranks.toSet().length, 7, reason: '$order');
      }
    }
    expect([for (var k = 0; k < 7; k++) slice.rank(k, StaggerOrder.reverse)], [6, 5, 4, 3, 2, 1, 0]);
    expect(slice.rank(3, StaggerOrder.center), 0, reason: 'the middle goes first');
  });

  test('shimmer band mirrors under RTL', () {
    expect(Shimmer.bandCenter(0, 0.2, rtl: false), closeTo(-0.2, 1e-9));
    expect(Shimmer.bandCenter(1, 0.2, rtl: false), closeTo(1.2, 1e-9));
    expect(Shimmer.bandCenter(0, 0.2, rtl: true), closeTo(1.2, 1e-9));
    expect(Shimmer.bandCenter(0.5, 0.2, rtl: true), closeTo(0.5, 1e-9));
  });

  test('rainbow spins every hue from the seed', () {
    final ink = GradientInk.rainbow(seed: const Color(0xFF006DFD), steps: 6);
    expect(ink.colors.length, 6);
    expect(ink.colors.toSet().length, 6);
    expect(ink.continuous, isFalse);
    expect(GradientInk.rainbow(flow: const Duration(seconds: 3)).continuous, isTrue);
    expect(ink.motionOnly, isFalse);
  });

  ShapedText shape(String t) => ShapedText.shape(
        span: TextSpan(text: t, style: const TextStyle(fontSize: 16)),
        text: t,
        direction: TextDirection.ltr,
      );

  test('morph diff keeps a shared suffix and prefix', () {
    final a = shape('Autumn Sale');
    final b = shape('Winter Sale');
    final d = MorphDiff.between(a, b);
    expect((d.prefix, d.suffix), (0, 4));
    final c = shape('12,000');
    final e = shape('12,500');
    final d2 = MorphDiff.between(c, e);
    expect((d2.prefix, d2.suffix), (3, 2));
    final same = MorphDiff.between(c, shape('12,000'));
    expect(same.prefix + same.suffix, 6);
    for (final s in [a, b, c, e]) {
      s.dispose();
    }
  });

  test('a frame composes poses from several effects', () {
    final s = shape('abc');
    final poses = List.generate(3, (_) => UnitPose());
    final frame = TextFrame(shaped: s, progress: 0.0, time: 0, poses: poses);
    const all = UnitSlice([0, 1, 2]);
    const Rise(distance: 10, stagger: 0).apply(frame, all);
    expect(frame.pose(0).dy, 10);
    expect(frame.pose(0).opacity, 0);
    const Float(amplitude: 0).apply(frame, all);
    expect(frame.anyPosed, isTrue);
    const Tint(Color(0xFFFF0000)).apply(frame, all);
    expect(frame.ink.length, 1);
    s.dispose();
  });

  test('effects compare by value, so a fresh instance is the same effect', () {
    final accent = const Color(0xFF006DFD);
    expect(Rise(distance: 10), const Rise(distance: 10));
    expect(const Rise(distance: 10), isNot(const Rise(distance: 11)));
    expect(Glint(sheen: [accent, const Color(0xFF00FF00)]),
        Glint(sheen: [accent, const Color(0xFF00FF00)]));
    expect(GradientInk.rainbow(seed: accent), GradientInk.rainbow(seed: accent));
    expect(GradientInk.rainbow(seed: accent, flow: const Duration(seconds: 1)),
        isNot(GradientInk.rainbow(seed: accent)));
    expect(Shimmer(colors: [accent]), Shimmer(colors: [accent]));
    expect(const Shimmer(), isNot(const Shimmer(pop: 0)));
    expect(Highlight(color: accent), Highlight(color: accent));
    expect(Underline(color: accent), isNot(Underline.strike(color: accent)));
    expect(Typewriter(cursor: accent), Typewriter(cursor: accent));
    expect(const Sparkle(color: Color(0xFFFFFFFF)), const Sparkle(color: Color(0xFFFFFFFF)));
    expect(const Float(), const Float());
    expect(const Blur(), const Blur());
    expect(Tint(accent), Tint(accent));
    expect(TextRun('a', effects: [Tint(accent)]), TextRun('a', effects: [Tint(accent)]));
    expect(MorphStyle.sheen(sheen: [accent]), MorphStyle.sheen(sheen: [accent]));
    expect(const MorphStyle.roll(), isNot(const MorphStyle.roll(stagger: 0.3)));
    expect(const MorphStyle.crossfade(), const MorphStyle.crossfade());
    expect(const MorphStyle.slide(), const MorphStyle.slide());
    expect({Rise(distance: 10), const Rise(distance: 10)}.length, 1, reason: 'hashCode agrees');
  });

  test('the odometer reads Western and Arabic-Indic digits', () {
    expect(TextMorph.numberIn('12,000'), 12000);
    expect(TextMorph.numberIn('12.5'), 12.5);
    expect(TextMorph.numberIn('٤٥٠ د.ع'), 450);
    expect(TextMorph.numberIn('۱۲,۵۰۰'), 12500);
    expect(TextMorph.numberIn('no digits'), isNull);
  });
}

void _rollTests() {
  test('a rolling glyph is fully off the drum at the end of its exit', () {
    const roll = MorphStyle.roll() as RollMorph;
    final pose = UnitPose();
    roll.exit(pose, 1, 20, true);
    expect(pose.opacity, 0, reason: 'past the drum window: no ghost');
    expect(pose.dy, lessThan(0), reason: 'up = exits over the top');
    expect(pose.scaleY, lessThan(1), reason: 'foreshortened on the curve');
    final arriving = UnitPose();
    roll.enter(arriving, 0, 20, true);
    expect(arriving.opacity, 0, reason: 'the newcomer starts off the drum');
    expect(arriving.dy, greaterThan(0), reason: 'up = arrives from below');
    final landed = UnitPose();
    roll.enter(landed, 1, 20, true);
    expect(landed.isIdentity, isTrue, reason: 'settles exactly in place');
  });

  test('chase eases hard out of the gate and lands at 1', () {
    expect(KineticEase.chase.transform(0), 0);
    expect(KineticEase.chase.transform(1), 1);
    expect(KineticEase.chase.transform(0.25), greaterThan(0.6));
    expect(KineticEase.chase.transform(0.5), lessThan(KineticEase.chase.transform(0.75)));
  });
}
