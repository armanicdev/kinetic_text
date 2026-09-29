import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'frame.dart';
import 'shaped_text.dart';

/// The order a stagger walks the units of a slice.
enum StaggerOrder {
  /// First unit first — the reading order in every script.
  reading,

  /// Last unit first.
  reverse,

  /// From the middle outwards.
  center,

  /// From both ends inwards.
  edges,

  /// A fixed shuffle (seeded, so it is the same every play).
  scatter,
}

/// The units one effect acts on — the whole text, or one run of a rich label.
/// Staggers count within the slice, so a cascade on one word starts at that
/// word's first letter.
class UnitSlice {
  /// A slice over [units], which are unit indices in reading order.
  const UnitSlice(this.units);

  /// Unit indices, in reading order.
  final List<int> units;

  /// How many units the slice holds.
  int get length => units.length;

  /// True when the slice holds no unit.
  bool get isEmpty => units.isEmpty;

  /// The rank of the [k]-th unit of the slice under [order], `0..length-1`.
  int rank(int k, StaggerOrder order, {int seed = 7}) {
    final n = units.length;
    if (n <= 1) return 0;
    switch (order) {
      case StaggerOrder.reading:
        return k;
      case StaggerOrder.reverse:
        return n - 1 - k;
      case StaggerOrder.center:
        return ((k - (n - 1) / 2).abs() * 2).round().clamp(0, n - 1);
      case StaggerOrder.edges:
        final d = ((k - (n - 1) / 2).abs() * 2).round().clamp(0, n - 1);
        return n - 1 - d;
      case StaggerOrder.scatter:
        // A small linear congruential permutation — deterministic per seed,
        // full-cycle for these constants when n is coprime with the stride.
        var stride = 7 + seed % 11;
        while (_gcd(stride, n) != 1) {
          stride++;
        }
        return (k * stride + seed) % n;
    }
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}

/// Where unit [rank] of [n] is in its own local timeline when the whole slice
/// is at [progress]: units start one after another across the first [stagger]
/// fraction of the run and each moves over the remaining `1 - stagger`.
///
/// `stagger` 0 = everything at once; 0.55 = the last unit starts when the run
/// is a bit past half — the sweep that reads as one gesture rather than a
/// queue.
double staggered(double progress, int rank, int n, double stagger) {
  if (n <= 1 || stagger <= 0) return progress.clamp(0.0, 1.0);
  final s = stagger.clamp(0.0, 0.95);
  final start = rank / (n - 1) * s;
  final span = 1 - s;
  return ((progress - start) / span).clamp(0.0, 1.0);
}

/// One text effect. Effects are plain, immutable descriptions; the compositor
/// hands each one the current [TextFrame] and the [UnitSlice] it is bound to,
/// and the effect writes poses, ink passes and decor into the frame.
///
/// A one-shot effect reads [TextFrame.progress]; a loop reads
/// [TextFrame.time] and reports [continuous] so the host keeps a clock
/// running for it.
///
/// Effects are compared by VALUE: the host rebinds and repaints only when an
/// effect actually changed, so a parent rebuild that constructs a fresh
/// `Rise()` costs nothing. Override `==` and `hashCode` in your own effects
/// (every bundled effect does).
@immutable
abstract class TextEffect {
  /// Const so a list of effects can be a compile-time constant.
  const TextEffect();

  /// True for effects that move on their own clock (shimmer, sparkle, float)
  /// and need the host ticking while mounted.
  bool get continuous => false;

  /// True for effects that are only motion — under reduced motion they are
  /// skipped entirely. A gradient fill is not motion; a sparkle is.
  bool get motionOnly => true;

  /// Write this frame's poses, ink passes and decor for [slice] into [frame].
  void apply(TextFrame frame, UnitSlice slice);
}

/// A one-shot, staggered effect: the shared skeleton of every reveal. Subclasses
/// implement [poseUnit] for one unit at its local eased progress.
abstract class StaggeredEffect extends TextEffect {
  /// Configure the stagger every reveal shares.
  const StaggeredEffect({
    this.stagger = 0.55,
    this.order = StaggerOrder.reading,
    this.curve = Curves.easeOutCubic,
  });

  /// How much of the run is spent starting units, `0..0.95`.
  final double stagger;

  /// The order units start in.
  final StaggerOrder order;

  /// The ease each unit's own timeline runs through.
  final Curve curve;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final n = slice.length;
    for (var k = 0; k < n; k++) {
      final unit = slice.units[k];
      final local = staggered(frame.progress, slice.rank(k, order), n, stagger);
      final eased = curve.transform(local);
      poseUnit(frame, frame.shaped.units[unit], frame.pose(unit), local, eased, k, n);
    }
  }

  /// Pose one unit. [local] is the unit's raw 0..1 timeline, [eased] the same
  /// through [curve]; [k] is its position in the slice of [n].
  void poseUnit(
    TextFrame frame,
    UnitBox unit,
    UnitPose pose,
    double local,
    double eased,
    int k,
    int n,
  );

  /// True when [other] staggers the same way — for subclasses' `==`.
  @protected
  bool sameStagger(StaggeredEffect other) =>
      other.stagger == stagger && other.order == order && other.curve == curve;

  /// The stagger's contribution to a subclass's `hashCode`.
  @protected
  int get staggerHash => Object.hash(stagger, order, curve);
}

/// Interpolate along a colour list at [t] ∈ 0..1.
Color colorAlong(List<Color> colors, double t) {
  if (colors.length == 1) return colors.first;
  final pos = t.clamp(0.0, 1.0) * (colors.length - 1);
  final i = pos.floor().clamp(0, colors.length - 2);
  return Color.lerp(colors[i], colors[i + 1], pos - i)!;
}

/// Interpolate around a colour RING at [t] (any real; wraps every 1.0): the
/// last colour blends back into the first, so a hue can keep turning.
Color colorAround(List<Color> colors, double t) {
  if (colors.length == 1) return colors.first;
  final n = colors.length;
  final pos = (t % 1.0) * n;
  final i = pos.floor() % n;
  return Color.lerp(colors[i], colors[(i + 1) % n], pos - pos.floor())!;
}

/// A full spectrum of [steps] hues spun from [seed]'s saturation and
/// lightness — so a rainbow in an app reads as that app's colours turned
/// through every hue, not a crayon box. [seed] null gives a clean 85% / 55%
/// spectrum starting at red.
List<Color> rainbowColors({
  Color? seed,
  int steps = 7,
  double? saturation,
  double? lightness,
}) {
  final base = seed == null
      ? const HSLColor.fromAHSL(1, 0, 0.85, 0.55)
      : HSLColor.fromColor(seed);
  final s = (saturation ?? base.saturation).clamp(0.0, 1.0);
  final l = (lightness ?? base.lightness).clamp(0.0, 1.0);
  return [
    for (var i = 0; i < steps; i++)
      HSLColor.fromAHSL(1, (base.hue + i * 360 / steps) % 360, s, l).toColor(),
  ];
}

/// Where a sweep — a shimmer band, a spotlight, a wipe — starts.
enum SweepOrigin {
  /// From where the text itself starts reading: the right edge of a Kurdish
  /// or Arabic line, the left of an English one, whatever the page's own
  /// direction. The default everywhere.
  reading,

  /// From where the text ends reading — the reverse of [reading].
  end,

  /// From the left edge.
  left,

  /// From the right edge.
  right,

  /// From the middle outwards, both ways at once.
  center,

  /// From both edges inwards, crossing in the middle.
  edges,
}

/// The geometry every sweep shares — [Shimmer], [Spotlight] and [Wipe] read
/// the same numbers, so a band feels the same wherever it runs.
abstract final class Sweep {
  /// The centres of the band(s), as fractions of the slice's width from its
  /// LEFT edge, at eased sweep progress [eased] ∈ 0..1, for a band of
  /// half-width [band] over a slice that reads right to left when [rtl]. A
  /// band starts fully off one edge and ends fully off the other.
  static List<double> centers(
    SweepOrigin origin,
    double eased,
    double band, {
    required bool rtl,
  }) {
    double travel(bool leftToRight) =>
        -band + (leftToRight ? eased : 1 - eased) * (1 + band * 2);
    return switch (origin) {
      SweepOrigin.reading => [travel(!rtl)],
      SweepOrigin.end => [travel(rtl)],
      SweepOrigin.left => [travel(true)],
      SweepOrigin.right => [travel(false)],
      SweepOrigin.center => [
          0.5 - eased * (0.5 + band),
          0.5 + eased * (0.5 + band),
        ],
      SweepOrigin.edges => [travel(true), travel(false)],
    };
  }

  /// True when the band travels right to left (for mirroring a multi-colour
  /// band so the same colour leads). For two-band origins, the first band.
  static bool travelsLeft(SweepOrigin origin, {required bool rtl}) =>
      switch (origin) {
        SweepOrigin.reading => rtl,
        SweepOrigin.end => !rtl,
        SweepOrigin.left => false,
        SweepOrigin.right => true,
        SweepOrigin.center => true,
        SweepOrigin.edges => false,
      };

  /// How strongly a band that starts on screen ([SweepOrigin.center]) is in
  /// at [eased]: it grows in over the first eighth of the sweep instead of
  /// appearing at full strength.
  static double appear(SweepOrigin origin, double eased) =>
      origin == SweepOrigin.center ? (eased / 0.12).clamp(0.0, 1.0) : 1.0;

  /// The weight of a band centred at [p] with half-width [b] at [x]: the
  /// feathered profile of [Shimmer.bandStops] — 0 at the edges, 0.35 at the
  /// shoulders, 1 at the centre, linear between.
  static double weight(double x, double p, double b) {
    if (b <= 0) return 0;
    final d = (x - p).abs() / b;
    if (d >= 1) return 0;
    if (d <= 0.45) return 1 - 0.65 * d / 0.45;
    return 0.35 * (1 - (d - 0.45) / 0.55);
  }

  /// Gradient stops (left → right, 0..1) and the band weight at each for the
  /// bands at [centers] with half-width [b] — exact breakpoints of every band,
  /// plus the points where two bands cross, so linear interpolation between
  /// stops is the true profile.
  static (List<double>, List<double>) maskStops(List<double> centers, double b) {
    final xs = <double>{0, 1};
    for (final p in centers) {
      for (final o in const [-1.0, -0.45, 0.0, 0.45, 1.0]) {
        xs.add((p + o * b).clamp(0.0, 1.0));
      }
    }
    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        xs.add(((centers[i] + centers[j]) / 2).clamp(0.0, 1.0));
      }
    }
    final stops = xs.toList()..sort();
    final weights = [
      for (final x in stops)
        centers.fold<double>(0, (w, p) => w > weight(x, p, b) ? w : weight(x, p, b)),
    ];
    return (stops, weights);
  }
}
