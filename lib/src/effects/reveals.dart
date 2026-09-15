import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
