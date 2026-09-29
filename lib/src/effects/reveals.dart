import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../easing.dart';
import '../effect.dart';
import '../frame.dart';
import '../internal.dart';
import '../shaped_text.dart';

/// The cascade: each unit rises into place from a little below (or any
/// side), fading in, one after another along the reading order. The motion
/// most list rows and labels want — short travel, a clean settle, no bounce.
///
/// `distance` is in logical pixels; keep it near the type size or smaller so
/// the letters read as settling, not flying in. A horizontal `from` slides
/// units sideways, which works on [TextUnit.word] (the spaces give a word room
/// to move) and is not recommended per letter, where a sliding glyph would
/// cross its neighbour's cell.
class Rise extends StaggeredEffect {
  /// Rise [distance] pixels in from [from], scaling from [scaleFrom] and fading
  /// from [fadeFrom].
  const Rise({
    this.distance = 12,
    this.from = AxisDirection.down,
    this.scaleFrom = 1,
    this.fadeFrom = 0,
    super.stagger = 0.55,
    super.order,
    super.curve = KineticEase.arrive,
  });

  /// A pure fade — no travel.
  const Rise.fade({
    super.stagger = 0.55,
    super.order,
    super.curve = KineticEase.arrive,
  })  : distance = 0,
        from = AxisDirection.down,
        scaleFrom = 1,
        fadeFrom = 0;

  /// A pop: scales up from [scaleFrom] with a hair of overshoot, no travel.
  const Rise.pop({
    this.scaleFrom = 0.6,
    super.stagger = 0.55,
    super.order,
    super.curve = KineticEase.overshoot,
  })  : distance = 0,
        from = AxisDirection.down,
        fadeFrom = 0;

  /// Travel, in logical pixels.
  final double distance;

  /// The side a unit arrives FROM. [AxisDirection.down] = from below,
  /// travelling up.
  final AxisDirection from;

  /// Starting scale.
  final double scaleFrom;

  /// Starting opacity.
  final double fadeFrom;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    final t = 1 - eased;
    switch (from) {
      case AxisDirection.down:
        pose.dy += distance * t;
      case AxisDirection.up:
        pose.dy -= distance * t;
      case AxisDirection.left:
        pose.dx -= distance * t;
      case AxisDirection.right:
        pose.dx += distance * t;
    }
    pose.opacity *= lerp(fadeFrom, 1, eased.clamp(0.0, 1.0));
    pose.scale *= lerp(scaleFrom, 1, eased);
  }

  @override
  bool operator ==(Object other) =>
      other is Rise &&
      other.distance == distance &&
      other.from == from &&
      other.scaleFrom == scaleFrom &&
      other.fadeFrom == fadeFrom &&
      sameStagger(other);

  @override
  int get hashCode =>
      Object.hash(distance, from, scaleFrom, fadeFrom, staggerHash);
}

/// A sheen reveal: each unit grows from [scaleFrom] and fades in while a glint
/// of [sheen] rides its wavefront — a soft light that draws the word on. The
/// title idiom: one steady sweep, start to end.
class Glint extends StaggeredEffect {
  /// Draw on under a glint of [sheen], at [intensity] of the colour's alpha.
  const Glint({
    this.sheen = const [Color(0xFFFFFFFF)],
    this.scaleFrom = 0.8,
    this.intensity = 1,
    super.stagger = 0.55,
    super.order,
    super.curve = KineticEase.arrive,
  });

  /// A glint that runs through every hue along the reading order —
  /// [rainbowColors] from [seed].
  factory Glint.rainbow({
    Color? seed,
    double scaleFrom = 0.8,
    double intensity = 1,
    double stagger = 0.55,
    StaggerOrder order = StaggerOrder.reading,
  }) =>
      Glint(
        sheen: rainbowColors(seed: seed),
        scaleFrom: scaleFrom,
        intensity: intensity,
        stagger: stagger,
        order: order,
      );

  /// One colour, or a list flowed along the reading order (an iridescent
  /// sweep: the first unit glints in the first colour, the last in the last).
  final List<Color> sheen;

  /// Starting scale.
  final double scaleFrom;

  /// Peak glint opacity, as a fraction of the sheen colour's own alpha.
  final double intensity;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    super.apply(frame, slice);
    final n = slice.length;
    for (var k = 0; k < n; k++) {
      final unit = slice.units[k];
      final local = staggered(frame.progress, slice.rank(k, order), n, stagger);
      if (local <= 0 || local >= 1) continue;
      final glint = math.sin(math.pi * local) * intensity;
      final base = colorAlong(sheen, n <= 1 ? 0 : k / (n - 1));
      frame.ink.add(InkPass(
        units: [unit],
        color: base.withValues(alpha: (base.a * glint).clamp(0.0, 1.0)),
        blendMode: BlendMode.srcATop,
      ));
    }
  }

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    pose.opacity *= eased.clamp(0.0, 1.0);
    pose.scale *= lerp(scaleFrom, 1, eased);
  }

  @override
  bool operator ==(Object other) =>
      other is Glint &&
      listEquals(other.sheen, sheen) &&
      other.scaleFrom == scaleFrom &&
      other.intensity == intensity &&
      sameStagger(other);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(sheen), scaleFrom, intensity, staggerHash);
}

/// Units resolve out of a blur, fading in. Each blurred unit costs a layer
/// while its sigma is non-zero, so this is a word- or line-unit effect; on a
/// paragraph of letters it would be a layer per glyph per frame.
class Blur extends StaggeredEffect {
  /// Resolve from a blur of [sigma] pixels, fading from [fadeFrom].
  const Blur({
    this.sigma = 10,
    this.fadeFrom = 0,
    super.stagger = 0.4,
    super.order,
    super.curve = KineticEase.arrive,
  });

  /// Starting Gaussian sigma, logical pixels.
  final double sigma;

  /// Starting opacity.
  final double fadeFrom;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    pose.blur += sigma * (1 - eased);
    pose.opacity *= lerp(fadeFrom, 1, eased.clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is Blur &&
      other.sigma == sigma &&
      other.fadeFrom == fadeFrom &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(sigma, fadeFrom, staggerHash);
}

/// Units appear one at a time, hard-cut, with an optional cursor bar sitting
/// after the last one — solid while typing, blinking once the line is done.
class Typewriter extends TextEffect {
  /// Type on, with an optional [cursor] bar.
  const Typewriter({
    this.cursor,
    this.cursorWidth = 2,
    this.blink = const Duration(milliseconds: 530),
    this.holdCursor = true,
    this.order = StaggerOrder.reading,
  });

  /// Cursor colour. Null draws no cursor.
  final Color? cursor;

  /// Cursor bar width, logical pixels.
  final double cursorWidth;

  /// Full blink cycle once typing has finished.
  final Duration blink;

  /// Keep the cursor blinking after the line completes. False removes it on
  /// the last letter.
  final bool holdCursor;

  /// The order units appear in.
  final StaggerOrder order;

  @override
  bool get continuous => cursor != null && holdCursor;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final n = slice.length;
    if (n == 0) return;
    final p = frame.progress.clamp(0.0, 1.0);
    // Unit with rank r is on once p has passed r / n: the line starts empty
    // and the last unit lands as the run completes.
    final shown = (p * n + 1e-6).floor().clamp(0, n);
    int? lastUnit;
    var lastRank = -1;
    for (var k = 0; k < n; k++) {
      final r = slice.rank(k, order);
      final on = r < shown;
      if (!on) frame.pose(slice.units[k]).opacity *= 0;
      if (on && r > lastRank) {
        lastRank = r;
        lastUnit = slice.units[k];
      }
    }
    final c = cursor;
    if (c == null) return;
    final done = shown >= n;
    if (done && !holdCursor) return;
    final blinkOn = !done ||
        ((frame.time * 1000 / blink.inMilliseconds) % 1.0) < 0.5;
    if (!blinkOn) return;
    final reading = frame.directionOf(slice);
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final LineBand band;
      final double x;
      final bool rtl;
      if (lastUnit == null) {
        // Nothing typed yet: the cursor waits where the text starts reading.
        band = shaped.lines.first;
        rtl = reading == TextDirection.rtl;
        x = rtl ? band.right : band.left;
      } else {
        // After the last letter typed, on the side its own run reads towards
        // — past a Latin word inside a Kurdish line, it sits on the right.
        final u = shaped.units[lastUnit];
        band = shaped.lineOf(u);
        rtl = u.direction == TextDirection.rtl;
        x = rtl ? u.rect.left - 2 : u.rect.right + 2;
      }
      final h = band.height * 0.78;
      final top = band.top + (band.height - h) / 2;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(rtl ? x - cursorWidth : x, top, cursorWidth, h),
        Radius.circular(cursorWidth / 2),
      );
      canvas.drawRRect(r, Paint()..color = c);
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Typewriter &&
      other.cursor == cursor &&
      other.cursorWidth == cursorWidth &&
      other.blink == blink &&
      other.holdCursor == holdCursor &&
      other.order == order;

  @override
  int get hashCode => Object.hash(cursor, cursorWidth, blink, holdCursor, order);
}

/// Letters drop in from above and land with one soft overshoot — the settle
/// dips a hair below the line and squashes, then stands. Playful where [Rise]
/// is quiet; keep it for a headline, not a list.
class Bounce extends StaggeredEffect {
  /// Fall [distance] pixels; squash by [squash] at the landing.
  const Bounce({
    this.distance = 18,
    this.squash = 0.1,
    super.stagger = 0.5,
    super.order,
    super.curve = KineticEase.overshoot,
  });

  /// Drop height, logical pixels.
  final double distance;

  /// Vertical squash at the deepest point of the landing (0.1 = 10%).
  final double squash;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    if (local >= 1) return;
    // The overshooting ease carries the letter a little past its line (dy >
    // 0) before it comes to rest — that dip is the landing.
    pose.dy += -distance * (1 - eased);
    final over = (eased - 1).clamp(0.0, 0.1) / 0.1;
    pose.scaleY *= 1 - squash * over;
    // Squashed about the baseline: the letter lands on its feet.
    pose.pivot = UnitPivot.baseline;
    pose.opacity *= (local * 3).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is Bounce &&
      other.distance == distance &&
      other.squash == squash &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(distance, squash, staggerHash);
}

/// Letters start wide and flat and stretch upright as they land — a stamp
/// pressed into the line. Uses the vertical squash, so the glyph's width is
/// barely disturbed and neighbours are never crossed.
class Squeeze extends StaggeredEffect {
  /// Start at [width] × [height] of the resting glyph.
  const Squeeze({
    this.width = 1.12,
    this.height = 0.35,
    super.stagger = 0.5,
    super.order,
    super.curve = KineticEase.arrive,
  });

  /// Starting horizontal scale.
  final double width;

  /// Starting vertical scale.
  final double height;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    if (local >= 1) return;
    final sx = lerp(width, 1, eased);
    final sy = lerp(height, 1, eased);
    pose.scale *= sx;
    pose.scaleY *= sy / sx;
    // Pressed down onto the line, not squeezed about the middle of it.
    pose.pivot = UnitPivot.baseline;
    pose.opacity *= (local * 2.5).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is Squeeze &&
      other.width == width &&
      other.height == height &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(width, height, staggerHash);
}

/// A stroke sweeps around each letter like a clock hand — clockwise from
/// twelve for a left-to-right letter, anticlockwise for a right-to-left one —
/// then the fill rises inside it and the stroke lets go. The stroke is the
/// letter's OWN outline from a stroked twin of the same paragraph, so every
/// join, tail and mark is traced exactly as it is set, and by default it is
/// drawn in the letter's own ink: a black word traces in black, a blue link
/// in blue.
///
/// Give [color] for one colour, [colors] for a ring that runs through them
/// along the reading order ([Outline.rainbow] for every hue). With [fill]
/// false the letters stay outlined when the reveal ends.
class Outline extends StaggeredEffect {
  /// Trace each letter in its own ink (or [color], or [colors]) with a stroke
  /// [width] pixels wide.
  const Outline({
    this.color,
    this.colors,
    this.width = 1.2,
    this.fill = true,
    super.stagger = 0.5,
    super.order,
    super.curve = KineticEase.sweep,
  });

  /// A ring that runs through every hue along the reading order —
  /// [rainbowColors] from [seed].
  factory Outline.rainbow({
    Color? seed,
    double width = 1.4,
    bool fill = true,
    double stagger = 0.5,
    StaggerOrder order = StaggerOrder.reading,
  }) =>
      Outline(
        colors: rainbowColors(seed: seed),
        width: width,
        fill: fill,
        stagger: stagger,
        order: order,
      );

  /// Stroke colour. Null = each letter's own ink.
  final Color? color;

  /// A gradient the rings run through along the reading order. Overrides
  /// [color].
  final List<Color>? colors;

  /// Stroke width, logical pixels.
  final double width;

  /// Let the fill rise inside the ring and the ring go. False leaves the text
  /// outlined.
  final bool fill;

  static const double _sweepEnd = 0.6;
  static const double _fillStart = 0.5;
  static const double _strokeFade = 0.7;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {}

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final n = slice.length;
    if (n == 0) return;
    final traced = <(int, double, double)>[]; // unit, sweep 0..1, stroke alpha
    for (var k = 0; k < n; k++) {
      final unit = slice.units[k];
      final local = staggered(frame.progress, slice.rank(k, order), n, stagger);
      final double alpha;
      if (fill) {
        if (local >= 1) continue;
        final rise = ((local - _fillStart) / (1 - _fillStart)).clamp(0.0, 1.0);
        frame.pose(unit).opacity *= KineticEase.arrive.transform(rise);
        alpha = local < _strokeFade
            ? 1.0
            : 1 - (local - _strokeFade) / (1 - _strokeFade);
      } else {
        frame.pose(unit).opacity *= 0; // the outline is the letter now
        alpha = 1;
      }
      final sweep = curve.transform((local / _sweepEnd).clamp(0.0, 1.0));
      if (sweep > 0 && alpha > 0.01) traced.add((unit, sweep, alpha));
    }
    if (traced.isEmpty) return;
    final ring = colors;
    final recolour = ring != null && ring.isNotEmpty;
    final rtl = frame.readsRtl(slice);
    final units = slice.units;
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final cover = shaped.cellsOf([for (final (i, _, _) in traced) i]);
      if (recolour) canvas.saveLayer(cover, Paint());
      for (final (i, sweep, alpha) in traced) {
        final u = shaped.units[i];
        final cell = shaped.cellOf(u);
        canvas.save();
        if (sweep < 1) {
          final c = u.rect.center;
          final r = (cell.center - c).distance + cell.longestSide;
          final turn = u.direction == TextDirection.rtl ? -1.0 : 1.0;
          final wedge = Path()
            ..moveTo(c.dx, c.dy)
            ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
                turn * math.pi * 2 * sweep, false)
            ..close();
          canvas.clipPath(wedge);
        }
        if (alpha < 1) {
          canvas.saveLayer(cell, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
        }
        shaped.paintUnits(canvas, [i],
            stroke: width, strokeColor: recolour ? null : color);
        if (alpha < 1) canvas.restore();
        canvas.restore();
      }
      if (recolour) {
        final along = rtl ? ring.reversed.toList() : ring;
        canvas.drawRect(
          cover,
          Paint()
            ..blendMode = BlendMode.srcIn
            ..shader = LinearGradient(colors: along.length == 1 ? [along.first, along.first] : along)
                .createShader(shaped.boundsOf(units)),
        );
        canvas.restore();
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Outline &&
      other.color == color &&
      listEquals(other.colors, colors) &&
      other.width == width &&
      other.fill == fill &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(
        color,
        colors == null ? null : Object.hashAll(colors!),
        width,
        fill,
        staggerHash,
      );
}

/// Every letter shows a run of random glyphs, then locks onto the real one,
/// in order — the terminal reveal. A stand-in glyph is set in the unit's own
/// style and sits on its baseline, centred in its cell.
///
/// Stand-ins are laid out one glyph at a time, so this is for Latin text and
/// figures; a cursive script would lose its joins while scrambling.
class Scramble extends TextEffect {
  /// Cycle through [glyphs], changing [steps] times over the run, locking in
  /// [order] across the first [stagger] of it.
  const Scramble({
    this.glyphs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
    this.steps = 24,
    this.stagger = 0.7,
    this.order = StaggerOrder.reading,
    this.seed = 3,
  });

  /// The pool of stand-in glyphs.
  final String glyphs;

  /// How many times a scrambling letter changes across the whole run.
  final int steps;

  /// How much of the run is spent locking letters, `0..0.95`.
  final double stagger;

  /// The order letters lock in.
  final StaggerOrder order;

  /// Seed for the glyph picks.
  final int seed;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    final n = slice.length;
    if (n == 0 || glyphs.isEmpty) return;
    final tick = (frame.progress.clamp(0.0, 1.0) * steps).floor();
    final pool = glyphs.characters.toList();
    final live = <(int, String)>[];
    for (var k = 0; k < n; k++) {
      final unit = slice.units[k];
      final local = staggered(frame.progress, slice.rank(k, order), n, stagger);
      if (local >= 1) continue;
      frame.pose(unit).opacity *= 0;
      final pick = (hash01(k * 31 + tick, seed) * pool.length).floor();
      live.add((unit, pool[pick.clamp(0, pool.length - 1)]));
    }
    if (live.isEmpty) return;
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final root = shaped.painter.text!;
      for (final (i, glyph) in live) {
        final u = shaped.units[i];
        final style = _styleAt(root, u.start);
        final tp = _standIn(style, shaped.painter.textScaler, glyph);
        final line = shaped.lineOf(u);
        final x = u.rect.center.dx - tp.width / 2;
        final y = line.baseline -
            tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        canvas.save();
        canvas.clipRect(shaped.cellOf(u));
        tp.paint(canvas, Offset(x, y));
        canvas.restore();
      }
    });
  }

  static TextStyle? _styleAt(InlineSpan root, int offset) {
    final base = root.style;
    final span = root.getSpanForPosition(TextPosition(offset: offset));
    if (span == null || identical(span, root)) return base;
    return base == null ? span.style : base.merge(span.style);
  }

  // Stand-in painters, one per (style, scale, glyph). Bounded: the whole
  // cache is dropped when it grows past a few hundred entries.
  static final Map<(TextStyle?, TextScaler, String), TextPainter> _standIns = {};

  static TextPainter _standIn(TextStyle? style, TextScaler scaler, String glyph) {
    if (_standIns.length > 384) {
      for (final p in _standIns.values) {
        p.dispose();
      }
      _standIns.clear();
    }
    return _standIns.putIfAbsent(
      (style, scaler, glyph),
      () => TextPainter(
        text: TextSpan(text: glyph, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Scramble &&
      other.glyphs == glyphs &&
      other.steps == steps &&
      other.stagger == stagger &&
      other.order == order &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(glyphs, steps, stagger, order, seed);
}

/// The rainbow intro: each letter rises into place washed in a colour of the
/// spectrum — the first letter in the first hue, the last in the last — its
/// hue still turning as it lands, then the colour drains away and the
/// letter settles into its own ink. A celebration that ends as plain text.
///
/// [colors] is the ring the letters take their hues from; null is a clean
/// spectrum ([rainbowColors]). Pass `rainbowColors(seed: brand)` to spin an
/// app's own colour through every hue.
class Prism extends StaggeredEffect {
  /// Rise [distance] pixels and grow from [scaleFrom] while washed in a hue
  /// that turns [turn] of the way round [colors].
  const Prism({
    this.colors,
    this.distance = 10,
    this.scaleFrom = 0.9,
    this.turn = 0.35,
    super.stagger = 0.6,
    super.order,
    super.curve = KineticEase.arrive,
  });

  /// The ring of hues. Null = [rainbowColors].
  final List<Color>? colors;

  /// Travel, logical pixels, from below.
  final double distance;

  /// Starting scale.
  final double scaleFrom;

  /// How far round the ring a letter's hue turns while it lands, `0..1`.
  final double turn;

  static final List<Color> _spectrum = rainbowColors();

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    super.apply(frame, slice);
    final ring = colors == null || colors!.isEmpty ? _spectrum : colors!;
    final n = slice.length;
    for (var k = 0; k < n; k++) {
      final unit = slice.units[k];
      final local = staggered(frame.progress, slice.rank(k, order), n, stagger);
      if (local <= 0 || local >= 1) continue;
      // Full colour on arrival, the letter's own ink by the time it lands.
      final wash =
          1 - KineticEase.sweep.transform(((local - 0.45) / 0.55).clamp(0.0, 1.0));
      if (wash <= 0.01) continue;
      final hue = colorAround(ring, (n <= 1 ? 0 : k / n) + local * turn);
      frame.ink.add(InkPass(
        units: [unit],
        color: hue.withValues(alpha: hue.a * wash),
        blendMode: BlendMode.srcATop,
      ));
    }
  }

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    if (local >= 1) return;
    pose.dy += distance * (1 - eased);
    pose.scale *= lerp(scaleFrom, 1, eased);
    pose.pivot = UnitPivot.baseline;
    pose.opacity *= KineticEase.arrive.transform((local * 2).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is Prism &&
      listEquals(other.colors, colors) &&
      other.distance == distance &&
      other.scaleFrom == scaleFrom &&
      other.turn == turn &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(
        colors == null ? null : Object.hashAll(colors!),
        distance,
        scaleFrom,
        turn,
        staggerHash,
      );
}

/// A soft edge draws the text on — one continuous feathered mask, not a
/// letter at a time, so a word appears the way ink would be uncovered. From
/// the text's reading start by default; [origin] turns it (from the middle
/// out makes a quiet title reveal). No layer per letter.
class Wipe extends TextEffect {
  /// Uncover from [origin] behind an edge [feather] of the slice wide.
  const Wipe({
    this.origin = SweepOrigin.reading,
    this.feather = 0.3,
    this.curve = KineticEase.sweep,
  });

  /// Where the edge starts.
  final SweepOrigin origin;

  /// Width of the soft edge as a fraction of the slice, `0.01..1`.
  final double feather;

  /// The ease of the edge.
  final Curve curve;

  /// The mask's opacity at [x] (a fraction of the slice from its left edge)
  /// when the wipe is [p] of the way on, for an edge [f] wide.
  @visibleForTesting
  static double maskAt(SweepOrigin origin, double x, double p, double f,
      {required bool rtl}) {
    double ramp(double d) => (d / f).clamp(0.0, 1.0);
    switch (origin) {
      case SweepOrigin.center:
        final r = -f + p * (0.5 + f);
        return ramp(r + f - (x - 0.5).abs());
      case SweepOrigin.edges:
        final r = -f + p * (0.5 + f);
        return ramp(r + f - math.min(x, 1 - x));
      case SweepOrigin.reading ||
            SweepOrigin.end ||
            SweepOrigin.left ||
            SweepOrigin.right:
        final fromLeft = Sweep.travelsLeft(origin, rtl: rtl) == false;
        final e = -f + p * (1 + f);
        return ramp(e + f - (fromLeft ? x : 1 - x));
    }
  }

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final p = curve.transform(frame.progress.clamp(0.0, 1.0));
    if (p >= 1) return;
    final bounds = frame.shaped.boundsOf(slice.units);
    if (bounds.width <= 0) return;
    final f = feather.clamp(0.01, 1.0);
    final rtl = frame.readsRtl(slice);
    // Exact breakpoints of the piecewise-linear mask, then the mask at each.
    final e = -f + p * (1 + f);
    final r = -f + p * (0.5 + f);
    final xs = <double>{0, 1, 0.5, e, e + f, 1 - e, 1 - e - f, r, r + f, 1 - r, 1 - r - f,
      0.5 - r, 0.5 - r - f, 0.5 + r, 0.5 + r + f}
        .where((x) => x >= 0 && x <= 1)
        .toList()
      ..sort();
    frame.ink.add(InkPass(
      units: slice.units,
      bounds: bounds,
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          for (final x in xs)
            Color.fromRGBO(255, 255, 255, maskAt(origin, x, p, f, rtl: rtl)),
        ],
        stops: xs,
      ),
      blendMode: BlendMode.dstIn,
    ));
  }

  @override
  bool operator ==(Object other) =>
      other is Wipe &&
      other.origin == origin &&
      other.feather == feather &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(origin, feather, curve);
}

/// Each letter flips up into place like a card on a table — seen in
/// perspective, so it foreshortens as it turns — and settles with a hair of
/// overshoot. [Axis.horizontal] tips it up about the baseline (a flap);
/// [Axis.vertical] turns it about its middle, the way the text reads (a
/// card turned over).
class Flip extends StaggeredEffect {
  /// Turn in from [angle] radians about [axis].
  const Flip({
    this.axis = Axis.horizontal,
    this.angle = 1.3,
    super.stagger = 0.45,
    super.order,
    super.curve = KineticEase.overshoot,
  });

  /// The axis a letter turns about.
  final Axis axis;

  /// Starting angle, radians (1.3 ≈ 75°: nearly edge-on).
  final double angle;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    if (local >= 1) return;
    final a = angle * (1 - eased);
    if (axis == Axis.horizontal) {
      pose.rotateX += a;
      pose.pivot = UnitPivot.baseline;
    } else {
      pose.rotateY += unit.direction == TextDirection.rtl ? -a : a;
    }
    pose.opacity *= KineticEase.arrive.transform((local * 2).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is Flip &&
      other.axis == axis &&
      other.angle == angle &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(axis, angle, staggerHash);
}

/// Letters tumble in from above, each turned a little one way or the other,
/// and land upright with a soft overshoot — a handful of tiles dropped onto
/// the line. Playful; for a headline or a reward, not a list.
class Tumble extends StaggeredEffect {
  /// Fall [distance] pixels, turned up to [angle] radians.
  const Tumble({
    this.angle = 0.5,
    this.distance = 18,
    this.seed = 11,
    super.stagger = 0.55,
    super.order,
    super.curve = KineticEase.overshoot,
  });

  /// The most a letter is turned at the start, radians.
  final double angle;

  /// Drop height, logical pixels.
  final double distance;

  /// Seed for each letter's turn.
  final int seed;

  @override
  void poseUnit(TextFrame frame, UnitBox unit, UnitPose pose, double local,
      double eased, int k, int n) {
    if (local >= 1) return;
    final t = 1 - eased;
    final side = hash01(k, seed) < 0.5 ? -1.0 : 1.0;
    final spin = side * angle * (0.55 + 0.45 * hash01(k + 50, seed));
    pose.rotation += spin * t;
    pose.dy -= distance * t;
    pose.opacity *= KineticEase.arrive.transform((local * 2.5).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is Tumble &&
      other.angle == angle &&
      other.distance == distance &&
      other.seed == seed &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(angle, distance, seed, staggerHash);
}
