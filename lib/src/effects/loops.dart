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

/// A light travels along the line in reading order; the letters under it are
/// full ink and the rest sit dimmed at [rest]. Each letter snaps up as the
/// light reaches it and drops as it passes — the lighting is per letter, not
/// a soft gradient — while the light itself glides on an in-out ease and
/// pauses at the far end before the next pass.
///
/// Costs one alpha-mask ink pass per frame and not a single layer per letter,
/// so it is fine on a whole line.
class Spotlight extends TextEffect {
  /// Dim the unlit letters to [rest]; light [radius] letters either side of
  /// the beam; one pass every [period], holding the whole line lit for the
  /// last [pause] of it. [color] tints the lit letters.
  const Spotlight({
    this.rest = 0.3,
    this.radius = 1.2,
    this.period = const Duration(milliseconds: 2600),
    this.pause = 0.2,
    this.color,
    this.bounce = false,
  });

  /// Opacity of a letter outside the light, `0..1`.
  final double rest;

  /// Half-width of the light, in letters.
  final double radius;

  /// One pass plus its pause.
  final Duration period;

  /// Fraction of each period the whole line rests fully lit, `0..0.8`.
  final double pause;

  /// A tint for the lit letters, or null for pure light.
  final Color? color;

  /// Alternate direction on every pass instead of restarting from the head.
  final bool bounce;

  @override
  bool get continuous => true;

  /// Where the beam is, in letter indices (`-radius` … `n - 1 + radius`), at
  /// pass progress [eased]; null while the line pauses fully lit.
  static double beamAt(double eased, int n, double radius, {required bool back}) {
    final from = -radius;
    final to = n - 1 + radius;
    return back ? to + (from - to) * eased : from + (to - from) * eased;
  }

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final n = slice.length;
    if (n == 0) return;
    final periodS = period.inMicroseconds / 1e6;
    if (periodS <= 0) return;
    final cycles = frame.time / periodS;
    final phase = cycles % 1.0;
    final travel = (1 - pause).clamp(0.2, 1.0);
    final raw = phase / travel;
    if (raw >= 1) return; // pause: the line rests fully lit — plain paint
    final back = bounce && cycles.floor().isOdd;
    final eased = KineticEase.sweep.transform(raw);
    final beam = beamAt(eased, n, radius, back: back);
    final shaped = frame.shaped;
    final bounds = shaped.boundsOf(slice.units);
    if (bounds.width <= 0) return;
    final dim = rest.clamp(0.0, 1.0);
    // Piecewise-constant stops: one level per letter, in physical order.
    final order = List<int>.generate(n, (k) => k)
      ..sort((a, b) => shaped.units[slice.units[a]].rect.left
          .compareTo(shaped.units[slice.units[b]].rect.left));
    final stops = <double>[];
    final mask = <Color>[];
    final tint = <Color>[];
    final c = color;
    for (final k in order) {
      final r = shaped.units[slice.units[k]].rect;
      final d = (k - beam).abs();
      // Snap: full inside the beam, a half-letter shoulder, dim outside.
      final lit = 1 - ((d - radius + 0.25) / 0.5).clamp(0.0, 1.0);
      final level = dim + (1 - dim) * lit;
      final l = ((r.left - bounds.left) / bounds.width).clamp(0.0, 1.0);
      final rr = ((r.right - bounds.left) / bounds.width).clamp(0.0, 1.0);
      stops..add(l)..add(rr);
      final m = Color.fromRGBO(255, 255, 255, level);
      mask..add(m)..add(m);
      if (c != null) {
        final t = c.withValues(alpha: c.a * lit);
        tint..add(t)..add(t);
      }
    }
    frame.ink.add(InkPass(
      units: slice.units,
      bounds: bounds,
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: mask,
        stops: stops,
      ),
      blendMode: BlendMode.dstIn,
    ));
    if (c != null) {
      frame.ink.add(InkPass(
        units: slice.units,
        bounds: bounds,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: tint,
          stops: stops,
        ),
        blendMode: BlendMode.srcATop,
      ));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Spotlight &&
      other.rest == rest &&
      other.radius == radius &&
      other.period == period &&
      other.pause == pause &&
      other.color == color &&
      other.bounce == bounce;

  @override
  int get hashCode => Object.hash(rest, radius, period, pause, color, bounce);
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
