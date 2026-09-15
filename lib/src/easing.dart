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
}
