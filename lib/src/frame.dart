import 'package:flutter/painting.dart';

import 'shaped_text.dart';

/// Where one unit is on this frame, relative to its resting layout. Effects
/// COMPOSE by accumulating into the same pose: a cascade adds a rise, a
/// shimmer adds a scale bump, a float adds a drift.
class UnitPose {
  double dx = 0;
  double dy = 0;
  double scale = 1;
  double opacity = 1;

  /// Gaussian blur sigma in logical pixels. Costs a layer per unit while
  /// non-zero — spend it on word or line units, not on every letter of a
  /// paragraph.
  double blur = 0;

  bool get isIdentity =>
      dx == 0 && dy == 0 && scale == 1 && opacity == 1 && blur == 0;

  void reset() {
    dx = 0;
    dy = 0;
    scale = 1;
    opacity = 1;
    blur = 0;
  }
}

/// A recolouring of glyph INK — painted inside the text's own layer with a
/// blend mode that only touches pixels the glyphs already own. [BlendMode.srcIn]
/// replaces the ink (a gradient fill); [BlendMode.srcATop] tints it (a sheen
/// that keeps the base colour showing through).
class InkPass {
  const InkPass({
    required this.units,
    this.color,
    this.gradient,
    this.bounds,
    this.blendMode = BlendMode.srcIn,
  }) : assert(color != null || gradient != null, 'an ink pass needs a colour or a gradient');

  /// Which units the pass recolours. Null = the whole text in one draw, the
  /// cheapest path.
  final List<int>? units;

  final Color? color;

  /// A gradient resolved over [bounds] (or the units' own bounds when null).
  final Gradient? gradient;

  /// The rect the gradient is stretched over. Null = the tight bounds of
  /// [units], so `Alignment.centerLeft → centerRight` spans exactly the
  /// recoloured word.
  final Rect? bounds;

  final BlendMode blendMode;
}

/// Something drawn on the canvas outside the glyph layer — a marker behind
/// the ink, an underline, a sparkle over it.
typedef DecorPainter = void Function(Canvas canvas, TextFrame frame);

/// Everything the effects have decided for one painted frame: a pose per
/// unit, the ink passes, and the decor to draw behind and over the glyphs.
/// Built fresh by the compositor every frame and handed to each effect in
/// order.
class TextFrame {
  TextFrame({
    required this.shaped,
    required this.progress,
    required this.time,
    required List<UnitPose> poses,
  }) : _poses = poses; // ignore: prefer_initializing_formals

  final ShapedText shaped;

  /// The one-shot progress, 0 → 1, of the reveal the host is playing.
  final double progress;

  /// Seconds since the host mounted — the clock of every loop.
  final double time;

  final List<UnitPose> _poses;
  final List<InkPass> ink = [];
  final List<DecorPainter> behind = [];
  final List<DecorPainter> over = [];

  UnitPose pose(int unit) => _poses[unit];
  int get unitCount => shaped.units.length;
  TextDirection get direction => shaped.direction;
  bool get isRtl => shaped.isRtl;

  /// True when any unit has left its resting pose.
  bool get anyPosed {
    for (final p in _poses) {
      if (!p.isIdentity) return true;
    }
    return false;
  }
}
