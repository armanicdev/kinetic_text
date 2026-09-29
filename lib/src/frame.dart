import 'package:flutter/painting.dart';

import 'effect.dart' show UnitSlice;
import 'shaped_text.dart';

/// The point a unit scales and turns about.
enum UnitPivot {
  /// The centre of the unit's box.
  center,

  /// The middle of the unit, on its line's baseline — a letter that grows or
  /// squashes about it keeps its feet on the line.
  baseline,

  /// The middle of the top of the unit's line box — a letter hangs from it.
  top,

  /// The middle of the bottom of the unit's line box.
  bottom,
}

/// Where one unit is on this frame, relative to its resting layout. Effects
/// COMPOSE by accumulating into the same pose: a cascade adds a rise, a
/// shimmer adds a scale bump, a float adds a drift.
class UnitPose {
  /// Horizontal travel, logical pixels.
  double dx = 0;

  /// Vertical travel, logical pixels (down is positive).
  double dy = 0;

  /// Uniform scale about the [pivot].
  double scale = 1;

  /// A vertical-only squash on top of [scale] — a glyph turning over a drum
  /// foreshortens without getting narrower.
  double scaleY = 1;

  /// Opacity, `0..1`.
  double opacity = 1;

  /// Gaussian blur sigma in logical pixels. Costs a layer per unit while
  /// non-zero — spend it on word or line units, not on every letter of a
  /// paragraph.
  double blur = 0;

  /// A turn in the plane of the text about the [pivot], radians, clockwise.
  double rotation = 0;

  /// A 3D tilt about the horizontal axis through the [pivot], radians, seen
  /// in perspective: positive leans the top of the glyph away.
  double rotateX = 0;

  /// A 3D turn about the vertical axis through the [pivot], radians, seen in
  /// perspective: positive turns the right edge away.
  double rotateY = 0;

  /// What the unit scales and turns about. The last effect to set it wins.
  UnitPivot pivot = UnitPivot.center;

  /// True when the unit is exactly at rest.
  bool get isIdentity => !moves && opacity == 1 && blur == 0;

  /// True when the unit has left its resting place or shape.
  bool get moves =>
      dx != 0 ||
      dy != 0 ||
      scale != 1 ||
      scaleY != 1 ||
      rotation != 0 ||
      rotateX != 0 ||
      rotateY != 0;

  /// Back to rest.
  void reset() {
    dx = 0;
    dy = 0;
    scale = 1;
    scaleY = 1;
    opacity = 1;
    blur = 0;
    rotation = 0;
    rotateX = 0;
    rotateY = 0;
    pivot = UnitPivot.center;
  }
}

/// A recolouring of glyph INK — painted over exactly the glyphs of its units
/// with a blend mode that only touches pixels they own. [BlendMode.srcIn]
/// replaces the ink (a gradient fill); [BlendMode.srcATop] tints it (a sheen
/// that keeps the base colour showing through); [BlendMode.dstIn] masks it
/// (a spotlight, a wipe).
class InkPass {
  /// A pass of [color] or [gradient] over [units].
  const InkPass({
    required this.units,
    this.color,
    this.gradient,
    this.bounds,
    this.blendMode = BlendMode.srcIn,
    this.textDirection,
  }) : assert(color != null || gradient != null, 'an ink pass needs a colour or a gradient');

  /// Which units the pass recolours. Null = the whole text in one draw, the
  /// cheapest path.
  final List<int>? units;

  /// A flat colour.
  final Color? color;

  /// A gradient resolved over [bounds] (or the units' own bounds when null).
  final Gradient? gradient;

  /// The rect the gradient is stretched over. Null = the tight bounds of
  /// [units], so `Alignment.centerLeft → centerRight` spans exactly the
  /// recoloured word.
  final Rect? bounds;

  /// How the pass meets the ink.
  final BlendMode blendMode;

  /// The direction a directional gradient resolves in. Null = the
  /// paragraph's.
  final TextDirection? textDirection;
}

/// Something drawn on the canvas outside the glyph layer — a marker behind
/// the ink, an underline, a sparkle over it.
typedef DecorPainter = void Function(Canvas canvas, TextFrame frame);

/// Everything the effects have decided for one painted frame: a pose per
/// unit, the ink passes, and the decor to draw behind and over the glyphs.
/// Built fresh by the compositor every frame and handed to each effect in
/// order.
class TextFrame {
  /// A frame of [shaped] at one-shot [progress] and loop [time], writing into
  /// [poses].
  TextFrame({
    required this.shaped,
    required this.progress,
    required this.time,
    required List<UnitPose> poses,
  }) : _poses = poses; // ignore: prefer_initializing_formals

  /// The shaped paragraph.
  final ShapedText shaped;

  /// The one-shot progress, 0 → 1, of the reveal the host is playing.
  final double progress;

  /// Seconds since the host mounted — the clock of every loop.
  final double time;

  final List<UnitPose> _poses;

  /// The ink passes, in order.
  final List<InkPass> ink = [];

  /// Decor drawn behind the glyphs.
  final List<DecorPainter> behind = [];

  /// Decor drawn over the glyphs.
  final List<DecorPainter> over = [];

  /// The pose of unit [unit].
  UnitPose pose(int unit) => _poses[unit];

  /// How many units the text has.
  int get unitCount => shaped.units.length;

  /// The paragraph's direction.
  TextDirection get direction => shaped.direction;

  /// True for an RTL paragraph.
  bool get isRtl => shaped.isRtl;

  /// The direction [slice] READS in — from its own letters, so a Latin word
  /// in a Kurdish sentence reads left to right and a Kurdish label in an
  /// English app right to left. A sweep, a flow, a marker or a cursor over
  /// the slice should follow this, not the page.
  TextDirection directionOf(UnitSlice slice) =>
      shaped.readingDirectionOf(slice.units);

  /// True when [slice] reads right to left.
  bool readsRtl(UnitSlice slice) => directionOf(slice) == TextDirection.rtl;

  /// True when any unit has left its resting pose.
  bool get anyPosed {
    for (final p in _poses) {
      if (!p.isIdentity) return true;
    }
    return false;
  }
}
