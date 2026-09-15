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

/// The first number in [s], reading Western and Arabic-Indic digits (with
/// thousands commas and a decimal point), or null. Decides which way a roll
/// or a ticker turns.
double? firstNumberIn(String s) {
  final m = _digits.firstMatch(s);
  if (m == null) return null;
  final buf = StringBuffer();
  for (final r in m.group(0)!.runes) {
    if (r == 0x2C) continue; // thousands comma
    if (r == 0x2E) {
      buf.write('.');
    } else if (r >= 0x30 && r <= 0x39) {
      buf.writeCharCode(r);
    } else if (r >= 0x660 && r <= 0x669) {
      buf.writeCharCode(r - 0x660 + 0x30);
    } else if (r >= 0x6F0 && r <= 0x6F9) {
      buf.writeCharCode(r - 0x6F0 + 0x30);
    }
  }
  return double.tryParse(buf.toString());
}

final RegExp _digits = RegExp(r'[0-9٠-٩۰-۹]+(?:[.,][0-9٠-٩۰-۹]+)*');
