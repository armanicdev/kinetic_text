// Helpers shared by the effects. Deliberately NOT exported from the package
// barrel: `lerpDouble` would collide with the one `package:flutter/painting`
// re-exports from dart:ui, and the rest are implementation detail.
import 'dart:math' as math;

/// 2π.
const double tau = 2 * math.pi;

/// Linear interpolation without dart:ui's nullable signature.
double lerp(double a, double b, double t) => a + (b - a) * t;

/// A cheap deterministic hash → 0..1, for seeded scatter.
double hash01(int a, int b) {
  var h = (a * 374761393 + b * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return ((h ^ (h >> 16)) & 0xffffff) / 0xffffff;
}
