import 'dart:math' as math;

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
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final rtl = f.isRtl;
      final LineBand band;
      final double x;
      if (lastUnit == null) {
        band = shaped.lines.first;
        x = rtl ? band.right : band.left;
      } else {
        final u = shaped.units[lastUnit];
        band = shaped.lineOf(u);
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

/// A stroke sweeps around each letter's outline like a clock hand, then the
/// fill rises inside it and the stroke lets go. The outline is the SAME
/// paragraph laid out again with a stroked ink, so every join and ligature
/// is traced exactly as it is set.
class Outline extends StaggeredEffect {
  /// Trace in [color] with a stroke [width] pixels wide.
  const Outline({
    required this.color,
    this.width = 1.2,
    super.stagger = 0.5,
    super.order,
    super.curve = KineticEase.sweep,
  });

  /// Stroke colour.
  final Color color;

  /// Stroke width, logical pixels.
  final double width;

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
      if (local >= 1) continue;
      final fill = ((local - _fillStart) / (1 - _fillStart)).clamp(0.0, 1.0);
      frame.pose(unit).opacity *= KineticEase.arrive.transform(fill);
      final sweep = curve.transform((local / _sweepEnd).clamp(0.0, 1.0));
      final alpha = local < _strokeFade
          ? 1.0
          : 1 - (local - _strokeFade) / (1 - _strokeFade);
      if (sweep > 0 && alpha > 0.01) traced.add((unit, sweep, alpha));
    }
    if (traced.isEmpty) return;
    frame.over.add((canvas, f) {
      final shaped = f.shaped;
      final twin = shaped.strokedTwin(width: width, color: color);
      for (final (i, sweep, alpha) in traced) {
        final u = shaped.units[i];
        final cell = shaped.cellOf(u);
        canvas.save();
        canvas.clipRect(cell);
        if (sweep < 1) {
          final c = u.rect.center;
          final r = cell.longestSide;
          final wedge = Path()
            ..moveTo(c.dx, c.dy)
            ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
                math.pi * 2 * sweep, false)
            ..close();
          canvas.clipPath(wedge);
        }
        if (alpha < 1) {
          canvas.saveLayer(cell, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
        }
        twin.paint(canvas, Offset.zero);
        if (alpha < 1) canvas.restore();
        canvas.restore();
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Outline &&
      other.color == color &&
      other.width == width &&
      sameStagger(other);

  @override
  int get hashCode => Object.hash(color, width, staggerHash);
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
