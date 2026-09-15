import 'package:flutter/widgets.dart';

import '../easing.dart';
import '../effect.dart';
import '../frame.dart';

/// A rounded marker behind a slice — a highlighter stroke — that sweeps in
/// from the reading start as the host's progress plays. A wrapped slice gets
/// one stroke per line, the second starting a beat after the first.
///
/// Not motion: under reduced motion the stroke is simply there.
class Highlight extends TextEffect {
  /// A marker of [color] with [radius] corners, [inflate]d past the glyphs.
  const Highlight({
    required this.color,
    this.radius = 6,
    this.inflate = const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    this.sweep = true,
    this.curve = KineticEase.arrive,
    this.stagger = 0.3,
  });

  /// Marker colour.
  final Color color;

  /// Corner radius, logical pixels.
  final double radius;

  /// How far the stroke extends past the glyph boxes.
  final EdgeInsets inflate;

  /// Draw in from the reading start; false paints it whole from the first
  /// frame.
  final bool sweep;

  /// The ease of the sweep.
  final Curve curve;

  /// Stagger between wrapped lines.
  final double stagger;

  @override
  bool get motionOnly => false;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final pieces = frame.shaped.lineRectsOf(slice.units);
    final p = frame.progress;
    frame.behind.add((canvas, f) {
      final paint = Paint()..color = color;
      for (var i = 0; i < pieces.length; i++) {
        final (_, rect) = pieces[i];
        final full = Rect.fromLTRB(
          rect.left - inflate.left,
          rect.top - inflate.top,
          rect.right + inflate.right,
          rect.bottom + inflate.bottom,
        );
        final e = sweep ? curve.transform(staggered(p, i, pieces.length, stagger)) : 1.0;
        if (e <= 0) continue;
        final w = full.width * e;
        final drawn = f.isRtl
            ? Rect.fromLTRB(full.right - w, full.top, full.right, full.bottom)
            : Rect.fromLTRB(full.left, full.top, full.left + w, full.bottom);
        canvas.drawRRect(
          RRect.fromRectAndRadius(drawn, Radius.circular(radius)),
          paint,
        );
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.color == color &&
      other.radius == radius &&
      other.inflate == inflate &&
      other.sweep == sweep &&
      other.curve == curve &&
      other.stagger == stagger;

  @override
  int get hashCode => Object.hash(color, radius, inflate, sweep, curve, stagger);
}

/// Where an [Underline] sits.
enum UnderlinePosition {
  /// Just under the baseline — a true underline.
  baseline,

  /// Through the middle of the x-height — a strike.
  middle,
}

/// A stroke drawn on along the reading direction under (or through) a slice.
/// Behind the ink for an underline, so descenders stay clean; over it for a
/// strike, so it reads as crossing the letters out.
class Underline extends TextEffect {
  /// A [thickness] stroke of [color], [gap] under the baseline.
  const Underline({
    required this.color,
    this.thickness = 2,
    this.gap = 2,
    this.position = UnderlinePosition.baseline,
    this.draw = true,
    this.curve = KineticEase.arrive,
    this.stagger = 0.3,
    this.cap = StrokeCap.round,
  });

  /// A strike-through.
  const Underline.strike({
    required this.color,
    this.thickness = 2,
    this.draw = true,
    this.curve = KineticEase.arrive,
    this.stagger = 0.3,
    this.cap = StrokeCap.round,
  })  : gap = 0,
        position = UnderlinePosition.middle;

  /// Stroke colour.
  final Color color;

  /// Stroke thickness, logical pixels.
  final double thickness;

  /// Distance below the baseline, for [UnderlinePosition.baseline].
  final double gap;

  /// Under the baseline, or through the middle.
  final UnderlinePosition position;

  /// Draw on from the reading start with progress; false paints it whole.
  final bool draw;

  /// The ease of the draw.
  final Curve curve;

  /// Stagger between wrapped lines.
  final double stagger;

  /// Stroke cap.
  final StrokeCap cap;

  @override
  bool get motionOnly => false;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final pieces = frame.shaped.lineRectsOf(slice.units);
    final p = frame.progress;
    void painter(Canvas canvas, TextFrame f) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = thickness
        ..strokeCap = cap
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < pieces.length; i++) {
        final (band, rect) = pieces[i];
        final e = draw ? curve.transform(staggered(p, i, pieces.length, stagger)) : 1.0;
        if (e <= 0) continue;
        final y = switch (position) {
          UnderlinePosition.baseline => band.baseline + gap + thickness / 2,
          UnderlinePosition.middle => rect.center.dy,
        };
        final inset = cap == StrokeCap.butt ? 0.0 : thickness / 2;
        final x0 = rect.left + inset;
        final x1 = rect.right - inset;
        if (x1 <= x0) continue;
        final w = (x1 - x0) * e;
        final a = f.isRtl ? Offset(x1 - w, y) : Offset(x0, y);
        final b = f.isRtl ? Offset(x1, y) : Offset(x0 + w, y);
        canvas.drawLine(a, b, paint);
      }
    }

    if (position == UnderlinePosition.middle) {
      frame.over.add(painter);
    } else {
      frame.behind.add(painter);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Underline &&
      other.color == color &&
      other.thickness == thickness &&
      other.gap == gap &&
      other.position == position &&
      other.draw == draw &&
      other.curve == curve &&
      other.stagger == stagger &&
      other.cap == cap;

  @override
  int get hashCode =>
      Object.hash(color, thickness, gap, position, draw, curve, stagger, cap);
}
