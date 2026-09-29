import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../easing.dart';
import '../effect.dart';
import '../frame.dart';
import '../internal.dart';
import '../painter.dart';

/// A soft band of light glides across the text in reading order while the
/// letters under it lift a hair and settle — then the text rests until the
/// next sweep. One clock drives both the sheen and the lift, so they never
/// drift apart.
///
/// The band starts where the text ITSELF starts reading: right to left over a
/// Kurdish or Arabic label, left to right over an English one, whatever the
/// page's direction. [origin] turns it: from the far end, from a physical
/// edge, out from the middle, or in from both edges.
///
/// Each letter under the band is lifted whole — the tail of a `ڕ` and the V
/// beneath it rise with their letter.
///
/// If you also import `package:shimmer`, hide one of the two `Shimmer`s.
class Shimmer extends TextEffect {
  /// A sweep of [color] (or the multi-stop [colors]) every [period].
  const Shimmer({
    this.color = const Color(0xFFFFFFFF),
    this.colors,
    this.period = const Duration(milliseconds: 3600),
    this.rest = 0.5,
    this.band = 0.18,
    this.pop = 0.18,
    this.intensity = 0.5,
    this.blendMode = BlendMode.srcATop,
    this.origin = SweepOrigin.reading,
  });

  /// A band that runs through every hue — [rainbowColors] from [seed] — for
  /// a celebration, a reward, a "you did it".
  factory Shimmer.rainbow({
    Color? seed,
    int steps = 7,
    Duration period = const Duration(milliseconds: 3200),
    double rest = 0.4,
    double band = 0.32,
    double pop = 0.14,
    double intensity = 0.9,
    SweepOrigin origin = SweepOrigin.reading,
  }) =>
      Shimmer(
        colors: rainbowColors(seed: seed, steps: steps),
        period: period,
        rest: rest,
        band: band,
        pop: pop,
        intensity: intensity,
        origin: origin,
      );

  /// A single feathered light. Ignored when [colors] is set.
  final Color color;

  /// A multi-stop iridescent band, its last colour leading whichever way the
  /// band runs.
  final List<Color>? colors;

  /// One glide plus its rest.
  final Duration period;

  /// Fraction of each period spent at rest after the glide, `0..0.85`.
  final double rest;

  /// Half-width of the band as a fraction of the slice, `0.02..0.49`.
  final double band;

  /// Peak per-unit scale bump under the band (0.18 = +18%), grown from the
  /// baseline so a letter lifts rather than swells.
  final double pop;

  /// Peak sheen opacity, as a fraction of the colour's own alpha.
  final double intensity;

  /// [BlendMode.srcATop] tints the ink; [BlendMode.srcIn] replaces it.
  final BlendMode blendMode;

  /// Where the band starts.
  final SweepOrigin origin;

  @override
  bool get continuous => true;

  /// Where the band centre is, as a fraction of the slice width, at eased
  /// sweep progress [eased]: off the reading-start edge at 0, off the far edge
  /// at 1.
  static double bandCenter(double eased, double band, {required bool rtl}) {
    final travel = rtl ? 1 - eased : eased;
    return -band + travel * (1 + band * 2);
  }

  /// The five stops of a feathered band centred at [p] with half-width [b]:
  /// edge, shoulder, centre, shoulder, edge. [bandProfile] is the weight at
  /// each.
  static List<double> bandStops(double p, double b) => [
        (p - b).clamp(0.0, 1.0),
        (p - b * 0.45).clamp(0.0, 1.0),
        p.clamp(0.0, 1.0),
        (p + b * 0.45).clamp(0.0, 1.0),
        (p + b).clamp(0.0, 1.0),
      ];

  /// The weight of the band at each of [bandStops].
  static const List<double> bandProfile = [0, 0.35, 1, 0.35, 0];

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final periodS = period.inMicroseconds / 1e6;
    final phase = periodS <= 0 ? 0.0 : (frame.time / periodS) % 1.0;
    final sweep = (1 - rest).clamp(0.15, 1.0);
    final raw = phase / sweep;
    if (raw >= 1) return; // resting — plain text, no layer, no shader
    final b = band.clamp(0.02, 0.49);
    final eased = KineticEase.sweep.transform(raw);
    final rtl = frame.readsRtl(slice);
    final centers = Sweep.centers(origin, eased, b, rtl: rtl);
    final shaped = frame.shaped;
    final bounds = shaped.boundsOf(slice.units);
    if (bounds.width <= 0) return;
    final appear = Sweep.appear(origin, eased);

    if (pop != 0) {
      for (final i in slice.units) {
        final c = (shaped.units[i].rect.center.dx - bounds.left) / bounds.width;
        var bump = 0.0;
        for (final p in centers) {
          final d = (p - c) / b;
          bump = math.max(bump, math.exp(-d * d));
        }
        bump *= appear;
        if (bump < 0.01) continue;
        final pose = frame.pose(i);
        pose.scale *= 1 + pop * bump;
        pose.pivot = UnitPivot.baseline;
      }
    }

    final k = intensity.clamp(0.0, 1.0) * appear;
    final multi = colors;
    for (var n = 0; n < centers.length; n++) {
      final p = centers[n];
      if (p + b <= 0 || p - b >= 1) continue; // off the slice
      final List<Color> stopsColors;
      final List<double> stops;
      if (multi != null && multi.isNotEmpty) {
        // The last colour leads: mirrored when this band runs leftwards.
        final leftward = Sweep.travelsLeft(origin, rtl: rtl) != (n == 1);
        final ordered = leftward ? multi.reversed.toList() : multi;
        stopsColors = [
          ordered.first.withValues(alpha: 0),
          for (final c in ordered) c.withValues(alpha: c.a * k),
          ordered.last.withValues(alpha: 0),
        ];
        final inner = ordered.length;
        stops = [
          (p - b).clamp(0.0, 1.0),
          for (var j = 0; j < inner; j++)
            (p - b + (j + 1) / (inner + 1) * 2 * b).clamp(0.0, 1.0),
          (p + b).clamp(0.0, 1.0),
        ];
      } else {
        stopsColors = [
          for (final w in bandProfile) color.withValues(alpha: color.a * k * w),
        ];
        stops = bandStops(p, b);
      }
      frame.ink.add(InkPass(
        units: slice.units,
        bounds: bounds,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: stopsColors,
          stops: stops,
        ),
        blendMode: blendMode,
      ));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Shimmer &&
      other.color == color &&
      listEquals(other.colors, colors) &&
      other.period == period &&
      other.rest == rest &&
      other.band == band &&
      other.pop == pop &&
      other.intensity == intensity &&
      other.blendMode == blendMode &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(
        color,
        colors == null ? null : Object.hashAll(colors!),
        period,
        rest,
        band,
        pop,
        intensity,
        blendMode,
        origin,
      );
}

/// A few small four-point glints twinkling on the glyphs — each on its own
/// phase, each resting most of its cycle, so at any moment one or two are
/// alive. Few, small and slow is what keeps it a highlight rather than a
/// firework: the defaults are tuned for a single word.
class Sparkle extends TextEffect {
  /// [count] glints of [color], each [size] pixels across at its peak.
  const Sparkle({
    required this.color,
    this.count = 4,
    this.period = const Duration(milliseconds: 1800),
    this.size = 7,
    this.spill = 0.3,
    this.seed = 1,
  });

  /// Glint colour.
  final Color color;

  /// How many glints share the slice.
  final int count;

  /// One glint's full cycle: it twinkles for the first ~55% and rests.
  final Duration period;

  /// Outer diameter at the peak, logical pixels.
  final double size;

  /// How far outside the glyph boxes a glint may sit, as a fraction of the
  /// line height.
  final double spill;

  /// Seed for the fixed placement and phases.
  final int seed;

  @override
  bool get continuous => true;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty || count <= 0) return;
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final periodS = period.inMicroseconds / 1e6;
      final paint = Paint()..style = PaintingStyle.fill;
      for (var k = 0; k < count; k++) {
        final pick = slice.units[
            (hash01(k, seed) * slice.length).floor().clamp(0, slice.length - 1)];
        final u = shaped.units[pick];
        final grow = shaped.lineOf(u).height * spill;
        final box = u.rect.inflate(grow);
        final x = box.left + hash01(k + 101, seed) * box.width;
        final y = box.top + hash01(k + 202, seed) * box.height;
        final phase = hash01(k + 303, seed);
        final t = periodS <= 0 ? 0.0 : ((f.time / periodS) + phase) % 1.0;
        const live = 0.55;
        if (t >= live) continue;
        final env = math.sin(math.pi * (t / live));
        final outer = size / 2 * env;
        if (outer < 0.3) continue;
        final inner = outer * 0.26;
        final tilt = (hash01(k + 404, seed) - 0.5) * 0.5;
        final path = Path();
        for (var i = 0; i < 8; i++) {
          final r = i.isEven ? outer : inner;
          final a = tilt + i * math.pi / 4 - math.pi / 2;
          final px = x + math.cos(a) * r;
          final py = y + math.sin(a) * r;
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        paint.color = color.withValues(alpha: color.a * env);
        canvas.drawPath(path, paint);
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Sparkle &&
      other.color == color &&
      other.count == count &&
      other.period == period &&
      other.size == size &&
      other.spill == spill &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(color, count, period, size, spill, seed);
}

/// A slow, tiny vertical drift, each unit a little behind the last — the
/// idle of a hero line that should feel alive rather than pinned. The default
/// amplitude is a pixel and a half; past three or four it becomes a wave, and
/// a wave is a different, louder thing.
class Float extends TextEffect {
  /// Drift [amplitude] pixels over [period], neighbours [phaseStep] apart.
  const Float({
    this.amplitude = 1.5,
    this.period = const Duration(milliseconds: 2600),
    this.phaseStep = 0.08,
  });

  /// Peak vertical travel, logical pixels.
  final double amplitude;

  /// One full cycle.
  final Duration period;

  /// Phase offset between neighbouring units, as a fraction of a cycle.
  final double phaseStep;

  @override
  bool get continuous => true;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0) return;
    final w = tau * frame.time / periodS;
    for (var k = 0; k < slice.length; k++) {
      frame.pose(slice.units[k]).dy +=
          amplitude * math.sin(w + k * phaseStep * tau);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Float &&
      other.amplitude == amplitude &&
      other.period == period &&
      other.phaseStep == phaseStep;

  @override
  int get hashCode => Object.hash(amplitude, period, phaseStep);
}

/// A rounded ripple runs through the line in reading order, each letter a
/// beat behind the last. Louder than [Float] — a wave is a gesture, not an
/// idle — so keep it to a word or a short hero line.
class Wave extends TextEffect {
  /// Rise and fall [amplitude] pixels; one crest every [period]; [length]
  /// letters from crest to crest.
  const Wave({
    this.amplitude = 3,
    this.period = const Duration(milliseconds: 2200),
    this.length = 8,
  });

  /// Peak vertical travel, logical pixels.
  final double amplitude;

  /// One full cycle at any one letter.
  final Duration period;

  /// Letters per wavelength.
  final double length;

  @override
  bool get continuous => true;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0 || length <= 0) return;
    final w = tau * frame.time / periodS;
    for (var k = 0; k < slice.length; k++) {
      frame.pose(slice.units[k]).dy += amplitude * math.sin(w - k / length * tau);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Wave &&
      other.amplitude == amplitude &&
      other.period == period &&
      other.length == length;

  @override
  int get hashCode => Object.hash(amplitude, period, length);
}

/// Each letter swings a few degrees on a pin at the top of its line, a beat
/// behind the one before — a hanging sign in a breeze. Playful; keep it to a
/// word or a short line.
class Sway extends TextEffect {
  /// Swing ±[angle] radians over [period]; neighbours [phaseStep] of a cycle
  /// apart.
  const Sway({
    this.angle = 0.07,
    this.period = const Duration(milliseconds: 2400),
    this.phaseStep = 0.09,
  });

  /// Peak swing, radians (0.07 ≈ 4°).
  final double angle;

  /// One full swing and back.
  final Duration period;

  /// Phase offset between neighbouring units, as a fraction of a cycle.
  final double phaseStep;

  @override
  bool get continuous => true;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0 || angle == 0) return;
    final w = tau * frame.time / periodS;
    // The swing travels in reading order.
    final lead = frame.readsRtl(slice) ? -1.0 : 1.0;
    for (var k = 0; k < slice.length; k++) {
      final pose = frame.pose(slice.units[k]);
      pose.rotation += lead * angle * math.sin(w - k * phaseStep * tau);
      pose.pivot = UnitPivot.top;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Sway &&
      other.angle == angle &&
      other.period == period &&
      other.phaseStep == phaseStep;

  @override
  int get hashCode => Object.hash(angle, period, phaseStep);
}

/// A slow glow breathes through the letters' ink — for a "live" or "waiting"
/// label that should hold attention without moving. One ink pass, no pose,
/// no layer per letter.
class Pulse extends TextEffect {
  /// Breathe [color] into the ink up to [intensity] every [period].
  const Pulse({
    required this.color,
    this.period = const Duration(milliseconds: 1800),
    this.intensity = 0.6,
    this.blendMode = BlendMode.srcATop,
  });

  /// The glow.
  final Color color;

  /// One breath in and out.
  final Duration period;

  /// Peak glow opacity as a fraction of the colour's own alpha.
  final double intensity;

  /// [BlendMode.srcATop] tints the ink; [BlendMode.srcIn] replaces it.
  final BlendMode blendMode;

  @override
  bool get continuous => true;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0) return;
    final env = 0.5 - 0.5 * math.cos(tau * frame.time / periodS);
    final a = color.a * intensity * env;
    if (a <= 0.004) return;
    frame.ink.add(InkPass(
      units: slice.units,
      color: color.withValues(alpha: a),
      blendMode: blendMode,
    ));
  }

  @override
  bool operator ==(Object other) =>
      other is Pulse &&
      other.color == color &&
      other.period == period &&
      other.intensity == intensity &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(color, period, intensity, blendMode);
}

/// The [Shimmer]'s band, turned into light: the text sits at [dim] and the
/// letters under the band are full ink — the band itself is the sweep, the
/// feather and the ease the shimmer has, so a Kurdish label is lit in its
/// own reading order. Optionally the band also draws a [focus] outline round
/// the letters it passes, so the light reads as a focus ring travelling the
/// word.
///
/// The dim level eases in as a sweep starts and out as it ends, so the line
/// is plain full ink while it rests between sweeps. One alpha-mask ink pass
/// per frame (plus one masked stroke when [focus] is set); no layer per
/// letter.
class Spotlight extends TextEffect {
  /// Hold the unlit letters at [dim]; a band [band] wide (as a fraction of
  /// the slice) sweeps every [period], resting for [rest] of it.
  const Spotlight({
    this.dim = 0.3,
    this.band = 0.22,
    this.period = const Duration(milliseconds: 3600),
    this.rest = 0.5,
    this.focus,
    this.focusWidth = 1.2,
    this.origin = SweepOrigin.reading,
  });

  /// Opacity of a letter outside the band, `0..1`.
  final double dim;

  /// Half-width of the band as a fraction of the slice, `0.02..0.49`.
  final double band;

  /// One sweep plus its rest.
  final Duration period;

  /// Fraction of each period spent at rest, fully lit, `0..0.85`.
  final double rest;

  /// Draw the letters' outline in this colour under the band. Null = light
  /// only.
  final Color? focus;

  /// The focus outline's stroke width, logical pixels.
  final double focusWidth;

  /// Where the band starts.
  final SweepOrigin origin;

  @override
  bool get continuous => true;

  /// How far the dimming is in at sweep progress [raw]: it fades in over
  /// the first tenth of a sweep and out over the last, so the rest between
  /// sweeps is reached without a jump.
  static double dimEnvelope(double raw) {
    const edge = 0.1;
    final head = (raw / edge).clamp(0.0, 1.0);
    final tail = ((1 - raw) / edge).clamp(0.0, 1.0);
    return KineticEase.sweep.transform(math.min(head, tail));
  }

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0) return;
    final phase = (frame.time / periodS) % 1.0;
    final sweep = (1 - rest).clamp(0.15, 1.0);
    final raw = phase / sweep;
    if (raw >= 1) return; // resting — plain text, no mask, no layer
    final b = band.clamp(0.02, 0.49);
    final eased = KineticEase.sweep.transform(raw);
    final centers = Sweep.centers(origin, eased, b, rtl: frame.readsRtl(slice));
    final shaped = frame.shaped;
    final bounds = shaped.boundsOf(slice.units);
    if (bounds.width <= 0) return;
    final level = lerp(1, dim.clamp(0.0, 1.0), dimEnvelope(raw));
    final appear = Sweep.appear(origin, eased);
    final (stops, weights) = Sweep.maskStops(centers, b);
    frame.ink.add(InkPass(
      units: slice.units,
      bounds: bounds,
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          for (final w in weights)
            Color.fromRGBO(255, 255, 255, lerp(level, 1, w * appear)),
        ],
        stops: stops,
      ),
      blendMode: BlendMode.dstIn,
    ));
    final f = focus;
    if (f == null) return;
    final units = slice.units;
    frame.over.add((canvas, fr) {
      final cover = shaped.cellsOf(units);
      canvas.saveLayer(cover, Paint());
      shaped.paintUnits(canvas, units, stroke: focusWidth, strokeColor: f);
      canvas.drawRect(
        cover,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              for (final w in weights)
                Color.fromRGBO(255, 255, 255, w * appear),
            ],
            stops: stops,
          ).createShader(bounds),
      );
      canvas.restore();
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Spotlight &&
      other.dim == dim &&
      other.band == band &&
      other.period == period &&
      other.rest == rest &&
      other.focus == focus &&
      other.focusWidth == focusWidth &&
      other.origin == origin;

  @override
  int get hashCode =>
      Object.hash(dim, band, period, rest, focus, focusWidth, origin);
}

/// A few letters stutter dark and recover, like a sign with a loose contact.
/// For error and offline states: short, rare, one or two letters at a time.
class Flicker extends TextEffect {
  /// [count] letters flicker, each once per [period], dropping to
  /// `1 - depth` at the darkest.
  const Flicker({
    this.count = 2,
    this.period = const Duration(milliseconds: 2400),
    this.depth = 0.85,
    this.seed = 5,
  });

  /// How many letters take part.
  final int count;

  /// One letter's full cycle; it flickers for a short window of it.
  final Duration period;

  /// How dark the darkest dip goes, `0..1`.
  final double depth;

  /// Seed for which letters and when.
  final int seed;

  @override
  bool get continuous => true;

  /// The brightness of a flickering letter at [t] ∈ 0..1 of its window: two
  /// hard dips, a half-recovery between them, then back on.
  static double envelope(double t) {
    if (t < 0.25) return 0;
    if (t < 0.4) return 1;
    if (t < 0.55) return 0.15;
    if (t < 0.7) return 0.8;
    if (t < 0.8) return 0.3;
    return 1;
  }

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty || count <= 0) return;
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0) return;
    const window = 0.14;
    for (var j = 0; j < count; j++) {
      final k = (hash01(j, seed) * slice.length).floor().clamp(0, slice.length - 1);
      final phase = hash01(j + 77, seed);
      final t = ((frame.time / periodS) + phase) % 1.0;
      if (t >= window) continue;
      final on = envelope(t / window);
      frame.pose(slice.units[k]).opacity *= 1 - depth * (1 - on);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Flicker &&
      other.count == count &&
      other.period == period &&
      other.depth == depth &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(count, period, depth, seed);
}

/// A soft halo of light round the letters — neon on a dark ground, a warm
/// bloom on a light one — drawn behind the glyphs from a blurred copy of the
/// same ink, so it follows every letter as it moves and takes on any ink
/// pass (a rainbow glows in rainbow). Still by default; with [period] it
/// breathes.
///
/// Not motion: under reduced motion the halo stays, only the breath stops.
class Glow extends TextEffect {
  /// A halo of [color] (or the letters' own ink when null), blurred by
  /// [radius] pixels, at [intensity].
  const Glow({
    this.color,
    this.radius = 8,
    this.intensity = 0.85,
    this.period,
  });

  /// The halo's colour. Null = each letter's own ink.
  final Color? color;

  /// Blur radius, logical pixels — about how far the light reaches.
  final double radius;

  /// Peak strength of the halo, `0..1`.
  final double intensity;

  /// One breath, dim to bright and back. Null = a steady glow.
  final Duration? period;

  @override
  bool get continuous => period != null;

  @override
  bool get motionOnly => false;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty || radius <= 0 || intensity <= 0) return;
    var level = intensity.clamp(0.0, 1.0);
    final p = period;
    if (p != null) {
      final periodS = p.inMicroseconds / 1e6;
      if (periodS > 0) {
        level *= 0.55 + 0.45 * (0.5 - 0.5 * math.cos(tau * frame.time / periodS));
      }
    }
    final units = slice.units;
    final c = color;
    frame.behind.add((canvas, f) {
      final sigma = radius / 2;
      final cover = f.shaped.cellsOf(units).inflate(radius * 3);
      canvas.saveLayer(
        cover,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, level)
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
      );
      paintGlyphsOf(canvas, f, units);
      if (c != null) {
        canvas.drawRect(cover, Paint()
          ..color = c
          ..blendMode = BlendMode.srcIn);
      }
      canvas.restore();
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Glow &&
      other.color == color &&
      other.radius == radius &&
      other.intensity == intensity &&
      other.period == period;

  @override
  int get hashCode => Object.hash(color, radius, intensity, period);
}
