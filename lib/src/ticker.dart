import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'drum.dart';
import 'internal.dart';
import 'morph.dart' show MorphStyle, TextMorph;

/// Which physical edge a [TickerText] keys its character slots from.
///
/// Physical, not directional, because a figure is laid out left-to-right in
/// every script: a number anchored [right] keeps its units column still while
/// digits are added on the left, whatever the page direction.
enum TickerAnchor {
  /// Slot 0 is the rightmost character — for figures.
  right,

  /// Slot 0 is the leftmost character — for Latin labels.
  left,
}

/// Which way a [TickerText] turns when its text changes.
enum RollDirection {
  /// Up when the first number in the text grew, down when it shrank; up when
  /// there is no number. Digits always take the shorter way round the 0–9
  /// ring.
  auto,

  /// Always up (the old glyph exits over the top).
  up,

  /// Always down.
  down,
}

/// A label whose characters turn like an odometer when its text changes —
/// the SwiftUI `.contentTransition(.numericText())` model, on a real drum.
///
/// Each character sits in a slot keyed from the [anchor] edge and owns a
/// CONTINUOUS wheel that eases toward its target every frame — not a 0→1
/// timeline that restarts on each change. Retarget it mid-flight and every
/// wheel just redirects from where it is: no reset, no stutter, and a digit
/// spins through the digits in between. Digits ride the 0–9 ring the shorter
/// way round; any other character turns one step from the old glyph to the
/// new. The motion is frame-rate independent (exponential smoothing on real
/// dt). Glyphs foreshorten and dim as they curve over the drum and are gone
/// past its window — no clip, no ghost. The field's width eases as characters
/// come and go; entering slots fade in, leaving slots fade out.
///
/// Characters are laid out one per slot, so this is for figures and Latin
/// labels. For cursive scripts (Arabic, Kurdish) use [TextMorph] with
/// [MorphStyle.roll], which turns the same drum from one shaped paragraph so
/// the joins survive.
///
/// Pass a pre-formatted string (`1,250,000`). Use a tabular figure style so
/// digit slots stay equal width. Reports a text baseline, so it sits in a
/// baseline-aligned `Row` beside a unit label. Reduced motion snaps.
class TickerText extends StatefulWidget {
  /// A ticking label showing [text].
  const TickerText(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 600),
    this.anchor = TickerAnchor.right,
    this.direction = RollDirection.auto,
    this.reduceMotion,
    this.semanticsLabel,
  });

  /// The current value.
  final String text;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// The tempo of a roll. The wheels chase their target with a time constant
  /// of about a fifth of this, so a change settles within it.
  final Duration duration;

  /// The edge slots are keyed from.
  final TickerAnchor anchor;

  /// Which way non-digit characters turn.
  final RollDirection direction;

  /// Null reads the platform "disable animations" flag.
  final bool? reduceMotion;

  /// Null speaks the current [text].
  final String? semanticsLabel;

  @override
  State<TickerText> createState() => _TickerTextState();
}

/// One character slot: its ring of glyphs, a continuous wheel position along
/// that ring, and a presence alpha.
class _Slot {
  _Slot.digit(int d)
      : ring = _digitRing,
        isDigit = true,
        wheel = d.toDouble(),
        wheelTo = d.toDouble();

  _Slot.glyph(String g)
      : ring = [g],
        isDigit = false,
        wheel = 0,
        wheelTo = 0;

  static const List<String> _digitRing =
      ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

  List<String> ring;
  final bool isDigit;
  double wheel;
  double wheelTo;
  double alpha = 1;
  double alphaTo = 1;

  /// The glyph the slot shows when settled.
  String get target => ring[_mod(wheelTo.round(), ring.length)];

  /// The width of the slot: the target glyph's, or the digit column.
  static int _mod(int a, int n) => ((a % n) + n) % n;
}

class _TickerTextState extends State<TickerText>
    with SingleTickerProviderStateMixin {
  final _TickerModel _model = _TickerModel();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  String _displayed = '';
  bool _reduced = false;
  TextStyle? _resolvedStyle;
  TextScaler _scaler = TextScaler.noScaling;

  double get _tau => widget.duration.inMicroseconds / 1e6 * 0.22;

  @override
  void initState() {
    super.initState();
    // Eager: a lazy ticker that never rolls would first-construct in dispose.
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = widget.reduceMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    _resolve();
    if (_reduced) _settleNow();
  }

  @override
  void didUpdateWidget(TickerText old) {
    super.didUpdateWidget(old);
    _resolve();
    if (widget.anchor != old.anchor) {
      // A different keying: rebuild the slots from scratch, no roll.
      _model.slots.clear();
      _retarget(widget.text, animate: false);
    } else if (widget.text != _displayed) {
      _retarget(widget.text, animate: !_reduced);
    }
  }

  /// Re-read style and scale; re-measure when either changed.
  void _resolve() {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final changed = style != _resolvedStyle || scaler != _scaler;
    _resolvedStyle = style;
    _scaler = scaler;
    if (changed) {
      _model.restyle(style, scaler, widget.anchor);
      if (_displayed.isEmpty) {
        _retarget(widget.text, animate: false);
      } else {
        _model.widthTo = _model.measure(_model.slots);
        _model.width = _model.widthTo;
        _model.repaint.tick();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  bool _rollsUp(String from, String to) {
    switch (widget.direction) {
      case RollDirection.up:
        return true;
      case RollDirection.down:
        return false;
      case RollDirection.auto:
        final a = firstNumberIn(from);
        final b = firstNumberIn(to);
        return a == null || b == null || b >= a;
    }
  }

  /// Point every slot at [value]. Wheels keep their position and get a new
  /// target; new slots fade in, dropped slots fade out.
  void _retarget(String value, {required bool animate}) {
    final up = _rollsUp(_displayed, value);
    _displayed = value;
    final target = _parse(value);
    final slots = _model.slots;
    final live = {...slots.keys, ...target.keys};
    for (final q in live) {
      final ch = target[q];
      final slot = slots[q];
      if (ch == null) {
        slot!.alphaTo = 0; // dropped — finish fading, then reclaim
        continue;
      }
      final d = _digitOf(ch);
      if (slot == null) {
        final s = d != null ? _Slot.digit(d) : _Slot.glyph(ch);
        s.alpha = animate ? 0 : 1;
        slots[q] = s;
        continue;
      }
      slot.alphaTo = 1;
      if (d != null && slot.isDigit) {
        slot.wheelTo = _nearest(slot.wheel, d);
      } else if (d == null && !slot.isDigit) {
        if (slot.target != ch) {
          // Extend the ring past the current target and turn one step.
          final at = slot.wheelTo.round();
          final next = at + (up ? 1 : -1);
          if (next >= 0) {
            while (slot.ring.length <= next) {
              slot.ring.add(ch);
            }
            slot.ring[next] = ch;
          } else {
            slot.ring.insert(0, ch);
            slot.wheel += 1;
            slot.wheelTo = 0;
            continue;
          }
          slot.wheelTo = next.toDouble();
        }
      } else {
        // Digit ↔ non-digit: a fresh slot, cross-faded.
        final s = d != null ? _Slot.digit(d) : _Slot.glyph(ch);
        s.alpha = animate ? 0 : 1;
        slots[q] = s;
      }
    }
    _model.widthTo = _model.measure(target);
    if (!animate) {
      _settleNow();
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Absolute target nearest [current] whose value mod 10 == [digit].
  static double _nearest(double current, int digit) {
    final k = ((current - digit) / 10).round();
    return digit + 10.0 * k;
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final f = 1 - math.exp(-dt / _tau);
    var moving = false;
    final gone = <int>[];
    for (final entry in _model.slots.entries) {
      final s = entry.value;
      if ((s.wheelTo - s.wheel).abs() < 0.0006) {
        s.wheel = s.wheelTo;
      } else {
        s.wheel += (s.wheelTo - s.wheel) * f;
        moving = true;
      }
      if ((s.alphaTo - s.alpha).abs() < 0.004) {
        s.alpha = s.alphaTo;
        if (s.alphaTo == 0) gone.add(entry.key);
      } else {
        s.alpha += (s.alphaTo - s.alpha) * f;
        moving = true;
      }
    }
    for (final q in gone) {
      _model.slots.remove(q);
    }
    if ((_model.widthTo - _model.width).abs() < 0.05) {
      _model.width = _model.widthTo;
    } else {
      _model.width += (_model.widthTo - _model.width) * f;
      moving = true;
    }
    _model.repaint.tick();
    if (!moving) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _settleNow() {
    final gone = <int>[];
    for (final entry in _model.slots.entries) {
      final s = entry.value;
      s.wheel = s.wheelTo;
      if (s.alphaTo == 0) {
        gone.add(entry.key);
      } else {
        s.alpha = 1;
      }
    }
    for (final q in gone) {
      _model.slots.remove(q);
    }
    _model.width = _model.widthTo;
    if (_ticker.isActive) _ticker.stop();
    _model.repaint.tick();
  }

  static int? _digitOf(String ch) {
    if (ch.length != 1) return null;
    final c = ch.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) ? c - 0x30 : null;
  }

  /// Slot index → character, keyed from the anchor edge.
  Map<int, String> _parse(String s) {
    final chars = s.characters.toList();
    final n = chars.length;
    return {
      for (var i = 0; i < n; i++)
        (widget.anchor == TickerAnchor.right ? n - 1 - i : i): chars[i],
    };
  }

  @override
  Widget build(BuildContext context) {
    return _TickerRenderWidget(
      model: _model,
      label: widget.semanticsLabel ?? widget.text,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    );
  }
}

/// Per-frame repaint signal — poked each tick so the render object repaints
/// (or relays out, when the width moved) without rebuilding any widget.
class _Repaint extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// The live state a [TickerText] paints from: its slots, the eased width,
/// the metrics of the current style, and a glyph painter cache.
class _TickerModel {
  final Map<int, _Slot> slots = {};
  final _Repaint repaint = _Repaint();
  double width = 0;
  double widthTo = 0;
  double height = 0;
  double baseline = 0;
  double digitWidth = 0;
  TickerAnchor anchor = TickerAnchor.right;

  TextStyle? _style;
  TextScaler _scaler = TextScaler.noScaling;
  final Map<String, TextPainter> _glyphs = {};
  final Map<String, double> _widths = {};

  void restyle(TextStyle style, TextScaler scaler, TickerAnchor anchor) {
    this.anchor = anchor;
    if (style == _style && scaler == _scaler) return;
    _style = style;
    _scaler = scaler;
    for (final p in _glyphs.values) {
      p.dispose();
    }
    _glyphs.clear();
    _widths.clear();
    final probe = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    height = probe.height;
    baseline = probe.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    probe.dispose();
    var w = 0.0;
    for (var d = 0; d <= 9; d++) {
      w = math.max(w, widthOf('$d'));
    }
    digitWidth = w;
  }

  TextPainter glyph(String ch) => _glyphs.putIfAbsent(
        ch,
        () => TextPainter(
          text: TextSpan(text: ch, style: _style),
          textDirection: TextDirection.ltr,
          textScaler: _scaler,
        )..layout(),
      );

  double widthOf(String ch) =>
      _widths.putIfAbsent(ch, () => glyph(ch).width);

  bool _isDigit(String ch) =>
      ch.length == 1 && ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  double slotWidth(String ch) => _isDigit(ch) ? digitWidth : widthOf(ch);

  /// The settled width of [chars] (slot → glyph).
  double measure(Map<int, Object> chars) {
    var w = 0.0;
    for (final v in chars.values) {
      w += slotWidth(v is _Slot ? v.target : v as String);
    }
    return w;
  }

  void dispose() {
    for (final p in _glyphs.values) {
      p.dispose();
    }
    _glyphs.clear();
    repaint.dispose();
  }
}

class _TickerRenderWidget extends LeafRenderObjectWidget {
  const _TickerRenderWidget({
    required this.model,
    required this.label,
    required this.textDirection,
  });
  final _TickerModel model;
  final String label;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTickerText(model, label, textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderTickerText renderObject) {
    renderObject
      ..label = label
      ..textDirection = textDirection;
  }
}

class _RenderTickerText extends RenderBox {
  _RenderTickerText(this._model, this._label, this._textDirection);

  final _TickerModel _model;
  double _laidOutWidth = -1;

  String _label;
  set label(String value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  void _onTick() {
    if (_model.width != _laidOutWidth) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _model.repaint.addListener(_onTick);
  }

  @override
  void detach() {
    _model.repaint.removeListener(_onTick);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset position) => true;

  Size get _contentSize => Size(_model.width, _model.height);

  @override
  double computeMinIntrinsicWidth(double height) => _model.widthTo;

  @override
  double computeMaxIntrinsicWidth(double height) => _model.widthTo;

  @override
  double computeMinIntrinsicHeight(double width) => _model.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _model.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_contentSize);

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) =>
      _model.baseline;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _model.baseline;

  @override
  void performLayout() {
    _laidOutWidth = _model.width;
    size = constraints.constrain(_contentSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final m = _model;
    if (m.slots.isEmpty) return;
    final canvas = context.canvas;
    var maxKey = 0;
    for (final q in m.slots.keys) {
      if (q > maxKey) maxKey = q;
    }
    final n = maxKey + 1;
    // Cumulative distance from the anchor edge to each slot's near edge.
    final dist = List<double>.filled(n + 1, 0);
    for (var q = 0; q < n; q++) {
      final s = m.slots[q];
      dist[q + 1] = dist[q] + (s == null ? 0 : m.slotWidth(s.target));
    }
    for (var q = 0; q < n; q++) {
      final s = m.slots[q];
      if (s == null) continue;
      final a = s.alpha.clamp(0.0, 1.0);
      if (a <= 0.01) continue;
      final w = m.slotWidth(s.target);
      final x = m.anchor == TickerAnchor.right
          ? offset.dx + m.width - dist[q] - w
          : offset.dx + dist[q];
      _drawDrum(canvas, s, x, offset.dy, w, a);
    }
  }

  /// One slot's drum at its live wheel position: the glyphs within the front
  /// window, each foreshortened and dimmed by its angle.
  void _drawDrum(Canvas canvas, _Slot s, double x, double y, double slotW, double slotAlpha) {
    final m = _model;
    final base = s.wheel.round();
    for (var k = -1; k <= 1; k++) {
      final theta = (base + k - s.wheel) * Drum.stepAngle;
      if (theta.abs() > Drum.cullAngle) continue;
      final alpha = Drum.alpha(theta) * slotAlpha;
      if (alpha <= 0.01) continue;
      final ch = s.ring[_Slot._mod(base + k, s.ring.length)];
      final tp = m.glyph(ch);
      final dy = Drum.dy(theta, m.height);
      final scaleY = Drum.scaleY(theta);
      final gx = x + (slotW - tp.width) / 2;
      final layered = alpha < 0.999;
      if (layered) {
        canvas.saveLayer(
          Rect.fromLTWH(x, y + dy - 1, slotW, m.height + 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
        );
      }
      if (scaleY >= 0.999) {
        tp.paint(canvas, Offset(gx, y + dy));
      } else {
        final cx = x + slotW / 2;
        final cy = y + dy + m.height / 2;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.scale(1, scaleY);
        canvas.translate(-cx, -cy);
        tp.paint(canvas, Offset(gx, y + dy));
        canvas.restore();
      }
      if (layered) canvas.restore();
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _label
      ..textDirection = _textDirection;
  }
}
