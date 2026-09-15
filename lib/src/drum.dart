import 'dart:math' as math;

/// The lock-wheel drum every roll in this package shares — [RollMorph] and
/// [TickerText] read the same numbers, so a rolling letter and a ticking
/// digit are the same motion.
///
/// A glyph sits on a vertical cylinder at angle θ (0 = at the front window).
/// Its vertical offset is `R·sinθ`, it foreshortens by `cosθ`, and its
/// opacity rides a steep window that is fully OFF past ~60° — so a glyph that
/// has rolled away is gone, not a ghost, and nothing is ever hard-clipped.
abstract final class Drum {
  /// Drum radius as a fraction of the line height. Bounds the whole vertical
  /// excursion to ±radius, so glyphs curve over a fixed-height drum.
  static const double radiusFraction = 0.60;

  /// Angular step between consecutive positions on the drum, radians. Wide on
  /// purpose: one step away sits at ~66°, already off the front face.
  static const double stepAngle = 1.15;

  /// Front-window cutoff as cosθ — below this a glyph is fully off.
  static const double windowCos = 0.5;

  /// Opacity falloff across the window — higher pops in/out crisper.
  static const double falloff = 1.8;

  /// Past this angle a glyph is on the drum's back and is not visited.
  static const double cullAngle = 1.45;

  /// Vertical offset of a glyph at [theta] on a drum sized to [lineHeight].
  static double dy(double theta, double lineHeight) =>
      lineHeight * radiusFraction * math.sin(theta);

  /// Vertical foreshortening at [theta].
  static double scaleY(double theta) => math.cos(theta).clamp(0.05, 1.0);

  /// Window opacity at [theta], 0 once past the window.
  static double alpha(double theta) {
    final win = (math.cos(theta) - windowCos) / (1 - windowCos);
    if (win <= 0) return 0;
    return math.pow(win, falloff).toDouble();
  }
}
