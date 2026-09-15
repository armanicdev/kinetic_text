import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// The named easings every effect defaults to — so re-tuning the library's
/// "feel" is one edit, and nothing moves on an anonymous curve.
abstract final class KineticEase {
  /// Deceleration only — the settle of something that has arrived.
  static const Curve arrive = Curves.easeOutCubic;

  /// Acceleration only — the departure of something leaving.
  static const Curve depart = Curves.easeInCubic;

  /// Symmetric — a sweep that passes through (a shimmer band, a flow).
  static const Curve sweep = Curves.easeInOutCubic;

  /// A settle that overshoots by a hair and comes back — for a pop.
  static const Curve overshoot = Curves.easeOutBack;

  /// A cross-over: gone by half, arrived by the end — for a hand-over.
  static const Curve linear = Curves.linear;

  /// The exponential approach a follower makes toward a moving target — fast
  /// off the mark, asymptotic into place, never a hard stop. The roll's ease.
  static const Curve chase = _Chase(4.5);
}

/// `(1 - e^(-k t)) / (1 - e^(-k))` — exponential smoothing folded into a
/// 0..1 curve. [k] is how many time constants fit in the run.
class _Chase extends Curve {
  const _Chase(this.k);
  final double k;

  @override
  double transformInternal(double t) =>
      (1 - math.exp(-k * t)) / (1 - math.exp(-k));
}
