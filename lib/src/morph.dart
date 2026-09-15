import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'drum.dart';
import 'easing.dart';
import 'effect.dart';
import 'frame.dart';
import 'internal.dart';
import 'painter.dart';
import 'shaped_text.dart';

/// How a [TextMorph] exchanges the letters that differ. The letters both
/// texts share stay put (or glide to their new position); only the changed
/// span leaves and arrives, in reading order.
///
/// Styles are compared by value, like effects.
@immutable
abstract class MorphStyle {
  /// Configure the stagger and eases every style shares.
  const MorphStyle({
    this.stagger = 0.55,
    this.order = StaggerOrder.reading,
    this.exitCurve = KineticEase.arrive,
    this.enterCurve = KineticEase.arrive,
    this.exitEnd = 0.5,
    this.enterStart = 0.45,
  });

  /// Dissolve out under a glint, draw in under a glint — the title morph.
  const factory MorphStyle.sheen({
    List<Color> sheen,
    double scaleFrom,
    double stagger,
  }) = SheenMorph;

  /// Old letters lift away and fade, new ones rise into place from below —
  /// the cascade, letter by letter.
  const factory MorphStyle.slide({
    double distance,
    AxisDirection from,
    double stagger,
  }) = SlideMorph;

  /// Letters turn over a drum like an odometer — up when the number grew,
  /// down when it shrank. The same drum as [TickerText]: a glyph curves away,
  /// foreshortens and is gone past the window; nothing is clipped.
  const factory MorphStyle.roll({double stagger}) = RollMorph;

  /// A plain per-letter cross-fade.
  const factory MorphStyle.crossfade() = CrossfadeMorph;

  /// Split-flap: the old letter folds down from its top edge, the new one
  /// unfolds up from its bottom edge — the departure board.
  const factory MorphStyle.fold({double stagger}) = FoldMorph;

  /// A soft edge wipes the old text out and the new text in behind it, in
  /// reading order — the quiet swap for a title when a roll is too much.
  const factory MorphStyle.wipe({double stagger}) = WipeMorph;

  /// How much of each leg is spent starting units.
  final double stagger;

  /// The order the changed units leave and arrive in.
  final StaggerOrder order;

  /// The ease of a leaving unit.
  final Curve exitCurve;

  /// The ease of an arriving unit.
  final Curve enterCurve;

  /// Where in the run (0..1) the exit leg ends. With [enterStart] a little
  /// before it the hand-over reads as one motion; 1.0 with [enterStart] 0
  /// runs both legs on one clock (a roll).
  final double exitEnd;

  /// Where in the run (0..1) the entrance leg starts.
  final double enterStart;

  /// Read the travel direction from the numbers in the two texts.
  bool get numeric => false;

  /// Pose a leaving unit. [e] runs 0 (in place) → 1 (gone); [up] is the
  /// numeric direction for [numeric] styles.
  void exit(UnitPose pose, double e, double lineHeight, bool up);

  /// Pose an arriving unit. [e] runs 0 (not yet) → 1 (arrived).
  void enter(UnitPose pose, double e, double lineHeight, bool up);

  /// A sheen to tint a unit at raw local progress [local] (0..1 within its own
  /// leg), or null.
  Color? glint(double local, int k, int n) => null;

  /// True when [other] shares this style's stagger and eases — for `==`.
  @protected
  bool sameBase(MorphStyle other) =>
      other.stagger == stagger &&
      other.order == order &&
      other.exitCurve == exitCurve &&
      other.enterCurve == enterCurve &&
      other.exitEnd == exitEnd &&
      other.enterStart == enterStart;

  /// The base fields' contribution to `hashCode`.
  @protected
  int get baseHash =>
      Object.hash(stagger, order, exitCurve, enterCurve, exitEnd, enterStart);
}

/// Dissolve out and draw in under a travelling glint. See [MorphStyle.sheen].
class SheenMorph extends MorphStyle {
  /// A glint of [sheen]; letters scale from [scaleFrom].
  const SheenMorph({
    this.sheen = const [Color(0xFFFFFFFF)],
    this.scaleFrom = 0.8,
    super.stagger,
  });

  /// One colour, or a list flowed along the reading order.
  final List<Color> sheen;

  /// Starting (and ending) scale of an exchanged letter.
  final double scaleFrom;

  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= 1 - e;
    pose.scale *= lerp(1, scaleFrom, e);
  }

  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= e;
    pose.scale *= lerp(scaleFrom, 1, e);
  }

  @override
  Color? glint(double local, int k, int n) {
    if (local <= 0 || local >= 1) return null;
    final g = math.sin(math.pi * local);
    final c = colorAlong(sheen, n <= 1 ? 0 : k / (n - 1));
    return c.withValues(alpha: (c.a * g).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is SheenMorph &&
      listEquals(other.sheen, sheen) &&
      other.scaleFrom == scaleFrom &&
      sameBase(other);

  @override
  int get hashCode => Object.hash(Object.hashAll(sheen), scaleFrom, baseHash);
}

/// Leave one way, arrive from the other. See [MorphStyle.slide].
class SlideMorph extends MorphStyle {
  /// Travel [distance] pixels; new letters arrive from [from].
  const SlideMorph({
    this.distance = 12,
    this.from = AxisDirection.down,
    super.stagger = 0.4,
  }) : super(
          exitCurve: KineticEase.depart,
          enterCurve: KineticEase.arrive,
        );

  /// Travel, logical pixels.
  final double distance;

  /// The side new letters arrive FROM; old letters leave out the opposite
  /// side, so the whole exchange moves one way.
  final AxisDirection from;

  Offset get _unit => switch (from) {
        AxisDirection.down => const Offset(0, 1),
        AxisDirection.up => const Offset(0, -1),
        AxisDirection.left => const Offset(-1, 0),
        AxisDirection.right => const Offset(1, 0),
      };

  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    final v = _unit * (-distance * e);
    pose.dx += v.dx;
    pose.dy += v.dy;
    pose.opacity *= 1 - e;
  }

  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    final v = _unit * (distance * (1 - e));
    pose.dx += v.dx;
    pose.dy += v.dy;
    pose.opacity *= e;
  }

  @override
  bool operator ==(Object other) =>
      other is SlideMorph &&
      other.distance == distance &&
      other.from == from &&
      sameBase(other);

  @override
  int get hashCode => Object.hash(distance, from, baseHash);
}

/// The odometer. See [MorphStyle.roll].
class RollMorph extends MorphStyle {
  /// Every changed letter turns at once (stagger 0), on the exponential
  /// chase a ticker digit makes; exit and entrance share one clock, so the
  /// old glyph rolls off exactly as the new one rolls in.
  const RollMorph({super.stagger = 0})
      : super(
          order: StaggerOrder.reverse,
          exitCurve: KineticEase.chase,
          enterCurve: KineticEase.chase,
          exitEnd: 1,
          enterStart: 0,
        );

  @override
  bool get numeric => true;

  /// The leaving glyph turns from the window to one drum step away — up when
  /// the value grew (it exits over the top), down when it shrank.
  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    final theta = (up ? -1 : 1) * Drum.stepAngle * e;
    pose.dy += Drum.dy(theta, lineHeight);
    pose.scaleY *= Drum.scaleY(theta);
    pose.opacity *= Drum.alpha(theta);
  }

  /// The arriving glyph turns in from the opposite step into the window.
  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    final theta = (up ? 1 : -1) * Drum.stepAngle * (1 - e);
    pose.dy += Drum.dy(theta, lineHeight);
    pose.scaleY *= Drum.scaleY(theta);
    pose.opacity *= Drum.alpha(theta);
  }

  @override
  bool operator ==(Object other) => other is RollMorph && sameBase(other);

  @override
  int get hashCode => baseHash;
}

/// The departure board. See [MorphStyle.fold].
class FoldMorph extends MorphStyle {
  /// Flaps turn in reading order, each a beat after the last.
  const FoldMorph({super.stagger = 0.3})
      : super(
          exitCurve: KineticEase.depart,
          enterCurve: KineticEase.arrive,
          exitEnd: 0.5,
          enterStart: 0.5,
        );

  /// Hinged at the top: the glyph foreshortens to a line while its centre
  /// rises to the hinge.
  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    final s = math.cos(e * math.pi / 2).clamp(0.02, 1.0);
    pose.scaleY *= s;
    pose.dy += -(1 - s) * lineHeight / 2;
    pose.opacity *= 0.55 + 0.45 * s;
  }

  /// Hinged at the bottom: unfolds up into place.
  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    final s = math.sin(e * math.pi / 2).clamp(0.02, 1.0);
    pose.scaleY *= s;
    pose.dy += (1 - s) * lineHeight / 2;
    pose.opacity *= 0.55 + 0.45 * s;
  }

  @override
  bool operator ==(Object other) => other is FoldMorph && sameBase(other);

  @override
  int get hashCode => baseHash;
}

/// The quiet swap. See [MorphStyle.wipe].
class WipeMorph extends MorphStyle {
  /// A long stagger makes the edge; each letter's own fade is quick.
  const WipeMorph({super.stagger = 0.8})
      : super(
          exitCurve: KineticEase.depart,
          enterCurve: KineticEase.arrive,
          exitEnd: 0.7,
          enterStart: 0.3,
        );

  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= 1 - e;
    pose.dy += -lineHeight * 0.06 * e;
  }

  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= e;
    pose.dy += lineHeight * 0.06 * (1 - e);
  }

  @override
  bool operator ==(Object other) => other is WipeMorph && sameBase(other);

  @override
  int get hashCode => baseHash;
}

/// A plain cross-fade. See [MorphStyle.crossfade].
class CrossfadeMorph extends MorphStyle {
  /// Every changed letter fades at once.
  const CrossfadeMorph()
      : super(
          stagger: 0,
          exitCurve: KineticEase.linear,
          enterCurve: KineticEase.linear,
        );

  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= 1 - e;
  }

  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    pose.opacity *= e;
  }

  @override
  bool operator ==(Object other) => other is CrossfadeMorph && sameBase(other);

  @override
  int get hashCode => baseHash;
}

/// Which units of two texts are shared (a common prefix and suffix, by unit
/// text) and which differ.
class MorphDiff {
  /// [prefix] leading and [suffix] trailing units are shared.
  const MorphDiff({required this.prefix, required this.suffix});

  /// Shared leading units.
  final int prefix;

  /// Shared trailing units.
  final int suffix;

  /// Diff [from] and [to] by unit text.
  static MorphDiff between(ShapedText from, ShapedText to) {
    String unitText(ShapedText s, UnitBox u) => s.text.substring(u.start, u.end);
    final a = from.units;
    final b = to.units;
    final max = math.min(a.length, b.length);
    var prefix = 0;
    while (prefix < max && unitText(from, a[prefix]) == unitText(to, b[prefix])) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < max - prefix &&
        unitText(from, a[a.length - 1 - suffix]) ==
            unitText(to, b[b.length - 1 - suffix])) {
      suffix++;
    }
    return MorphDiff(prefix: prefix, suffix: suffix);
  }
}

/// A label that rewrites itself in place: when [text] changes, the letters the
/// two values share stay (gliding to their new position if the width moved),
/// and the letters that differ leave and arrive in the chosen [morph] style.
/// The box's width eases between the two widths underneath.
///
/// Single-line. Interrupt-safe — a new [text] mid-flight re-points the morph
/// at the latest value. Reduced motion sets the new text instantly.
class TextMorph extends StatefulWidget {
  /// A morphing label showing [text].
  const TextMorph(
    this.text, {
    super.key,
    this.style,
    this.morph = const SheenMorph(),
    this.unit = TextUnit.grapheme,
    this.duration = const Duration(milliseconds: 360),
    this.widthCurve = KineticEase.arrive,
    this.alignment = Alignment.center,
    this.textDirection,
    this.pinLineHeight = true,
    this.intro = false,
    this.reduceMotion,
    this.semanticsLabel,
  });

  /// The current value.
  final String text;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// How changed letters are exchanged.
  final MorphStyle morph;

  /// The grain of the diff and the motion.
  final TextUnit unit;

  /// Length of one exchange.
  final Duration duration;

  /// The ease the box width follows between the two texts.
  final Curve widthCurve;

  /// Where each text sits inside the box while the width moves.
  final AlignmentGeometry alignment;

  /// Null reads the ambient [Directionality].
  final TextDirection? textDirection;

  /// Force the strut so the box height is the style's line height regardless
  /// of script — a value that morphs between Latin and Arabic never changes
  /// height. On by default; a morph must not shift the layout around it.
  final bool pinLineHeight;

  /// Draw the first value in on mount (from nothing).
  final bool intro;

  /// Null reads the platform "disable animations" flag.
  final bool? reduceMotion;

  /// Null speaks the current [text].
  final String? semanticsLabel;

  /// The first number in [s], reading Western and Arabic-Indic digits, or
  /// null. Decides which way a [MorphStyle.roll] turns.
  @visibleForTesting
  static double? numberIn(String s) => firstNumberIn(s);

  @override
  State<TextMorph> createState() => _TextMorphState();
}

class _TextMorphState extends State<TextMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  String _from = '';
  late String _to = widget.text;
  TextStyle? _fromStyle;

  ShapedText? _fromShaped;
  ShapedText? _toShaped;
  MorphDiff _diff = const MorphDiff(prefix: 0, suffix: 0);
  bool _up = true;
  _MorphKey? _key;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)..value = 1;
    if (widget.intro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_reduced) _c.forward(from: 0);
      });
    } else {
      _from = _to;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = widget.reduceMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    if (_reduced) _c.value = 1;
  }

  @override
  void didUpdateWidget(TextMorph old) {
    super.didUpdateWidget(old);
    _c.duration = widget.duration;
    if (widget.text == _to) return;
    _from = _to;
    _fromStyle = old.style;
    _to = widget.text;
    if (_reduced) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _fromShaped?.dispose();
    _toShaped?.dispose();
    super.dispose();
  }

  void _shape(_MorphKey key) {
    _fromShaped?.dispose();
    _toShaped?.dispose();
    ShapedText shape(String text, TextStyle style) => ShapedText.shape(
          span: TextSpan(text: text, style: style),
          text: text,
          direction: key.direction,
          unit: widget.unit,
          scaler: key.scaler,
          maxLines: 1,
          strut: key.pin
              ? StrutStyle.fromTextStyle(style, forceStrutHeight: true)
              : null,
        );
    _fromShaped = shape(_from, key.fromStyle);
    _toShaped = shape(_to, key.style);
    _diff = MorphDiff.between(_fromShaped!, _toShaped!);
    final a = TextMorph.numberIn(_from);
    final b = TextMorph.numberIn(_to);
    _up = a == null || b == null ? true : b >= a;
    _key = key;
  }

  @override
  Widget build(BuildContext context) {
    final direction =
        widget.textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
    final defaults = DefaultTextStyle.of(context).style;
    final style = defaults.merge(widget.style);
    final label = widget.semanticsLabel ?? _to;
    if (_reduced) {
      return Text(
        _to,
        style: style,
        maxLines: 1,
        textDirection: direction,
        semanticsLabel: label,
      );
    }
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final fromStyle = defaults.merge(_fromStyle ?? widget.style);
    final key = _MorphKey(
      from: _from,
      to: _to,
      style: style,
      fromStyle: fromStyle,
      direction: direction,
      scaler: scaler,
      unit: widget.unit,
      pin: widget.pinLineHeight,
    );
    if (_toShaped == null || _key != key) _shape(key);
    final from = _fromShaped!;
    final to = _toShaped!;
    final align = widget.alignment.resolve(direction);
    final height = math.max(from.height, to.height);

    return Semantics(
      label: label,
      textDirection: direction,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final p = _c.value;
            final w = lerp(from.width, to.width, widget.widthCurve.transform(p));
            return SizedBox(
              width: w,
              height: height,
              child: CustomPaint(
                size: Size(w, height),
                painter: _MorphPainter(
                  from: from,
                  to: to,
                  diff: _diff,
                  style: widget.morph,
                  progress: _c,
                  align: align,
                  up: _up,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

@immutable
class _MorphKey {
  const _MorphKey({
    required this.from,
    required this.to,
    required this.style,
    required this.fromStyle,
    required this.direction,
    required this.scaler,
    required this.unit,
    required this.pin,
  });
  final String from, to;
  final TextStyle style, fromStyle;
  final TextDirection direction;
  final TextScaler scaler;
  final TextUnit unit;
  final bool pin;

  @override
  bool operator ==(Object other) =>
      other is _MorphKey &&
      other.from == from &&
      other.to == to &&
      other.style == style &&
      other.fromStyle == fromStyle &&
      other.direction == direction &&
      other.scaler == scaler &&
      other.unit == unit &&
      other.pin == pin;

  @override
  int get hashCode =>
      Object.hash(from, to, style, fromStyle, direction, scaler, unit, pin);
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.from,
    required this.to,
    required this.diff,
    required this.style,
    required this.progress,
    required this.align,
    required this.up,
  })  : _fromPoses = List.generate(from.units.length, (_) => UnitPose()),
        _toPoses = List.generate(to.units.length, (_) => UnitPose()),
        _fromMid = [
          for (final u in from.units)
            if (u.index >= diff.prefix &&
                u.index < from.units.length - diff.suffix)
              u.index,
        ],
        _toMid = [
          for (final u in to.units)
            if (u.index >= diff.prefix && u.index < to.units.length - diff.suffix)
              u.index,
        ],
        super(repaint: progress);

  final ShapedText from;
  final ShapedText to;
  final MorphDiff diff;
  final MorphStyle style;
  final Animation<double> progress;
  final Alignment align;
  final bool up;

  // Allocated once per painter (per build), reused every frame.
  final List<UnitPose> _fromPoses;
  final List<UnitPose> _toPoses;
  final List<int> _fromMid;
  final List<int> _toMid;

  Offset _origin(ShapedText s, Size box) => Offset(
        (box.width - s.width) * (align.x + 1) / 2,
        (box.height - s.height) * (align.y + 1) / 2,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    final toOrigin = _origin(to, size);
    if (p >= 1) {
      to.painter.paint(canvas, toOrigin);
      return;
    }
    final fromOrigin = _origin(from, size);
    final outP = (p / style.exitEnd).clamp(0.0, 1.0);
    final inP = ((p - style.enterStart) / (1 - style.enterStart)).clamp(0.0, 1.0);
    final settle = KineticEase.arrive.transform(p);
    final lineH = to.lines.isEmpty ? to.height : to.lines.first.height;

    // FROM — only its changed middle is drawn, leaving.
    for (final pose in _fromPoses) {
      pose.reset();
    }
    final fromFrame =
        TextFrame(shaped: from, progress: p, time: 0, poses: _fromPoses);
    for (final u in from.units) {
      final i = u.index;
      if (i < diff.prefix || i >= from.units.length - diff.suffix) {
        _fromPoses[i].opacity = 0; // the TO painter draws the shared letters
      }
    }
    final outSlice = UnitSlice(_fromMid);
    final nOut = _fromMid.length;
    for (var k = 0; k < nOut; k++) {
      final i = _fromMid[k];
      final local = staggered(outP, outSlice.rank(k, style.order), nOut, style.stagger);
      final e = style.exitCurve.transform(local);
      style.exit(_fromPoses[i], e, lineH, up);
      final g = style.glint(local, k, nOut);
      if (g != null) {
        fromFrame.ink.add(InkPass(units: [i], color: g, blendMode: BlendMode.srcATop));
      }
    }

    // TO — shared letters glide from where they were; the middle arrives.
    for (final pose in _toPoses) {
      pose.reset();
    }
    final toFrame = TextFrame(shaped: to, progress: p, time: 0, poses: _toPoses);
    for (final u in to.units) {
      final i = u.index;
      final inPrefix = i < diff.prefix;
      final inSuffix = i >= to.units.length - diff.suffix;
      if (!inPrefix && !inSuffix) continue;
      final fromU = inPrefix
          ? from.units[i]
          : from.units[from.units.length - (to.units.length - i)];
      final fromX = fromOrigin.dx + fromU.rect.left;
      final toX = toOrigin.dx + u.rect.left;
      _toPoses[i].dx = (fromX - toX) * (1 - settle);
    }
    final inSlice = UnitSlice(_toMid);
    final nIn = _toMid.length;
    for (var k = 0; k < nIn; k++) {
      final i = _toMid[k];
      final local = staggered(inP, inSlice.rank(k, style.order), nIn, style.stagger);
      final e = style.enterCurve.transform(local);
      style.enter(_toPoses[i], e, lineH, up);
      final g = style.glint(local, k, nIn);
      if (g != null) {
        toFrame.ink.add(InkPass(units: [i], color: g, blendMode: BlendMode.srcATop));
      }
    }

    if (nOut > 0) paintGlyphs(canvas, fromFrame, origin: fromOrigin);
    paintGlyphs(canvas, toFrame, origin: toOrigin);
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.progress != progress ||
      oldDelegate.style != style ||
      oldDelegate.align != align ||
      oldDelegate.up != up;
}
