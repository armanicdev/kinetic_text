import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../easing.dart';
import '../effect.dart';
import '../frame.dart';
import '../internal.dart';

/// A soft band of light glides across the text in reading order while the
/// letters under it lift a hair and settle — then the text rests until the
/// next sweep. One clock drives both the sheen and the pop, so they never
/// drift apart.
///
/// The band moves physically left→right for LTR text and right→left for RTL,
/// so a Kurdish or Arabic label shimmers in its own reading order.
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
  });

  /// A single feathered light. Ignored when [colors] is set.
  final Color color;

  /// A multi-stop iridescent band flowed across the text.
  final List<Color>? colors;

  /// One glide plus its rest.
  final Duration period;

  /// Fraction of each period spent at rest after the glide, `0..0.85`.
  final double rest;

  /// Half-width of the band as a fraction of the slice, `0.02..0.49`.
  final double band;

  /// Peak per-unit scale bump under the band (0.18 = +18%).
  final double pop;

  /// Peak sheen opacity, as a fraction of the colour's own alpha.
  final double intensity;

  /// [BlendMode.srcATop] tints the ink; [BlendMode.srcIn] replaces it.
  final BlendMode blendMode;

  @override
  bool get continuous => true;

  /// Where the band centre is, as a fraction of the slice width, at eased
  /// sweep progress [eased]: off the reading-start edge at 0, off the far edge
  /// at 1.
  static double bandCenter(double eased, double band, {required bool rtl}) {
    final travel = rtl ? 1 - eased : eased;
    return -band + travel * (1 + band * 2);
  }

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
    final p = bandCenter(eased, b, rtl: frame.isRtl);
    final bounds = frame.shaped.boundsOf(slice.units);
    if (bounds.width <= 0) return;

    for (final i in slice.units) {
      final u = frame.shaped.units[i];
      final c = (u.rect.center.dx - bounds.left) / bounds.width;
      final d = (p - c) / b;
      final bump = math.exp(-d * d);
      if (bump < 0.01) continue;
      frame.pose(i).scale *= 1 + pop * bump;
    }

    final k = intensity.clamp(0.0, 1.0);
    final List<Color> stopsColors;
    final List<double> stops;
    final multi = colors;
    if (multi != null && multi.isNotEmpty) {
      stopsColors = [
        multi.first.withValues(alpha: 0),
        for (final c in multi) c.withValues(alpha: c.a * k),
        multi.last.withValues(alpha: 0),
      ];
      final inner = multi.length;
      stops = [
        (p - b).clamp(0.0, 1.0),
        for (var j = 0; j < inner; j++)
          (p - b + (j + 1) / (inner + 1) * 2 * b).clamp(0.0, 1.0),
        (p + b).clamp(0.0, 1.0),
      ];
    } else {
      stopsColors = [
        color.withValues(alpha: 0),
        color.withValues(alpha: color.a * k * 0.35),
        color.withValues(alpha: color.a * k),
        color.withValues(alpha: color.a * k * 0.35),
        color.withValues(alpha: 0),
      ];
      stops = [
        (p - b).clamp(0.0, 1.0),
        (p - b * 0.45).clamp(0.0, 1.0),
        p.clamp(0.0, 1.0),
        (p + b * 0.45).clamp(0.0, 1.0),
        (p + b).clamp(0.0, 1.0),
      ];
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
      other.blendMode == blendMode;

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
