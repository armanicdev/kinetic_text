import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../effect.dart';
import '../frame.dart';

/// A gradient in place of the ink on a slice — a rainbow on one word, a
/// two-tone across a headline — optionally flowing along the reading
/// direction. The gradient is stretched over the slice's own bounds, so
/// `centerStart → centerEnd` spans exactly the recoloured word.
///
/// Not motion: the fill stays under reduced motion; only the flow stops.
class GradientInk extends TextEffect {
  /// Fill with [colors] from [begin] to [end]; [flow] slides it along.
  const GradientInk({
    required this.colors,
    this.stops,
    this.begin = AlignmentDirectional.centerStart,
    this.end = AlignmentDirectional.centerEnd,
    this.flow,
    this.blendMode = BlendMode.srcIn,
  });

  /// A full spectrum spun from [seed]'s saturation and lightness — so a
  /// rainbow in an app reads as that app's colours turned through every hue,
  /// not a crayon box. [seed] null gives a clean 85% / 55% spectrum.
  factory GradientInk.rainbow({
    Color? seed,
    int steps = 7,
    double? saturation,
    double? lightness,
    Duration? flow,
  }) {
    final base = seed == null
        ? const HSLColor.fromAHSL(1, 0, 0.85, 0.55)
        : HSLColor.fromColor(seed);
    final s = saturation ?? base.saturation;
    final l = lightness ?? base.lightness;
    final colors = [
      for (var i = 0; i < steps; i++)
        HSLColor.fromAHSL(1, (base.hue + i * 360 / steps) % 360, s, l).toColor(),
    ];
    return GradientInk(colors: colors, flow: flow);
  }

  /// Gradient colours.
  final List<Color> colors;

  /// Gradient stops, or evenly spaced when null.
  final List<double>? stops;

  /// Where the gradient starts, relative to the slice's bounds.
  final AlignmentGeometry begin;

  /// Where the gradient ends, relative to the slice's bounds.
  final AlignmentGeometry end;

  /// One full travel of the gradient along the slice. Null = static.
  final Duration? flow;

  /// [BlendMode.srcIn] replaces the ink; [BlendMode.srcATop] tints it.
  final BlendMode blendMode;

  @override
  bool get continuous => flow != null;

  @override
  bool get motionOnly => false;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    final f = flow;
    final Gradient g;
    if (f == null) {
      g = LinearGradient(begin: begin, end: end, colors: colors, stops: stops);
    } else {
      final periodS = f.inMicroseconds / 1e6;
      final shift = periodS <= 0 ? 0.0 : (frame.time / periodS) % 1.0;
      // Cyclic colours + a repeating tile, slid by [shift] of one width, so
      // the flow never shows a seam.
      g = LinearGradient(
        begin: begin,
        end: end,
        colors: [...colors, colors.first],
        tileMode: TileMode.repeated,
        transform: _Slide(frame.isRtl ? shift : -shift),
      );
    }
    frame.ink.add(InkPass(
      units: slice.units,
      bounds: frame.shaped.boundsOf(slice.units),
      gradient: g,
      blendMode: blendMode,
    ));
  }

  @override
  bool operator ==(Object other) =>
      other is GradientInk &&
      listEquals(other.colors, colors) &&
      listEquals(other.stops, stops) &&
      other.begin == begin &&
      other.end == end &&
      other.flow == flow &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(colors),
        stops == null ? null : Object.hashAll(stops!),
        begin,
        end,
        flow,
        blendMode,
      );
}

class _Slide extends GradientTransform {
  const _Slide(this.fraction);
  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(fraction * bounds.width, 0, 0);
}

/// A flat recolour of a slice's ink — cheaper than a second [TextStyle] and
/// animatable from the outside (rebuild with a lerped colour). Not motion.
class Tint extends TextEffect {
  /// Recolour to [color].
  const Tint(this.color, {this.blendMode = BlendMode.srcIn});

  /// The new ink colour.
  final Color color;

  /// [BlendMode.srcIn] replaces the ink; [BlendMode.srcATop] tints it.
  final BlendMode blendMode;

  @override
  bool get motionOnly => false;

  @override
  void apply(TextFrame frame, UnitSlice slice) {
    if (slice.isEmpty) return;
    frame.ink.add(InkPass(units: slice.units, color: color, blendMode: blendMode));
  }

  @override
  bool operator ==(Object other) =>
      other is Tint && other.color == color && other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(color, blendMode);
}
