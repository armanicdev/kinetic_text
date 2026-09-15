import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'effect.dart';
import 'frame.dart';
import 'painter.dart';
import 'shaped_text.dart';

/// A piece of a [KineticText.rich] label: text, an optional style override,
/// and effects that apply to THIS run's units only — a rainbow on one word, a
/// highlight under another.
@immutable
class TextRun {
  /// A run of [text] with its own [style] and [effects].
  const TextRun(this.text, {this.style, this.effects = const []});

  /// The run's text.
  final String text;

  /// Merged over the label's base style.
  final TextStyle? style;

  /// Effects scoped to this run. They stagger over the run's own units, so a
  /// cascade on one word starts at that word's first letter.
  final List<TextEffect> effects;

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      other.style == style &&
      listEquals(other.effects, effects);

  @override
  int get hashCode => Object.hash(text, style, Object.hashAll(effects));
}

/// Drives a [KineticText]'s one-shot progress from outside: play, replay,
/// finish, reverse. Attach one to a widget through [KineticText.controller].
class KineticController {
  _KineticTextState? _state;

  /// The progress animation, once attached.
  Animation<double>? get progress => _state?._progress;

  /// True while a [KineticText] is mounted with this controller.
  bool get isAttached => _state != null;

  /// Play from the start.
  TickerFuture? play() => _state?._play(from: 0);

  /// Same as [play] — reads better at a call site that has already played.
  TickerFuture? replay() => play();

  /// Continue from where it stopped.
  TickerFuture? resume() => _state?._play();

  /// Run the reveal backwards from wherever it is.
  TickerFuture? reverse() => _state?._reverse();

  /// Stop where it is.
  void stop() => _state?._progress.stop();

  /// Jump to the resolved end state.
  void finish() => _state?._progress.value = 1;

  /// Jump to the unrevealed start state.
  void reset() => _state?._progress.value = 0;
}

/// Text with motion — shaped once, animated per letter, word or line.
///
/// ```dart
/// KineticText(
///   'Fresh harvest, every morning',
///   style: theme.headline,
///   unit: TextUnit.word,
///   effects: const [Rise(distance: 10)],
/// )
///
/// KineticText.rich([
///   const TextRun('Pay '),
///   TextRun('12,000', effects: [Highlight(color: tint)]),
/// ], style: theme.body)
/// ```
///
/// One-shot effects ([Rise], [Glint], [Blur], [Typewriter], the sweep of a
/// [Highlight] or [Underline]) play over [duration] once on mount (or when
/// [replayKey] changes, or from a [KineticController]). Loops ([Shimmer],
/// [Sparkle], [Float], a flowing [GradientInk]) run on their own clock while
/// the widget is on screen.
///
/// Lays out like a [Text]: it reads the ambient [DefaultTextStyle],
/// [Directionality], text scale and bold-text setting, wraps to its
/// constraints, reports intrinsic sizes and a text baseline, and speaks its
/// plain text to assistive technology.
///
/// Reduced motion (the platform flag, or [reduceMotion]) resolves every
/// one-shot to its end state, stops every loop, and keeps every fill, marker
/// and underline that is not motion.
class KineticText extends StatefulWidget {
  /// A plain label.
  const KineticText(
    String this.text, {
    super.key,
    this.style,
    this.effects = const [],
    this.unit = TextUnit.grapheme,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
    this.locale,
    this.strutStyle,
    this.pinLineHeight = false,
    this.textHeightBehavior,
    this.autoplay = true,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.controller,
    this.progress,
    this.replayKey,
    this.reduceMotion,
    this.semanticsLabel,
    this.onEnd,
  }) : runs = null;

  /// A label of several [TextRun]s, each with its own style and effects.
  const KineticText.rich(
    List<TextRun> this.runs, {
    super.key,
    this.style,
    this.effects = const [],
    this.unit = TextUnit.grapheme,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
    this.locale,
    this.strutStyle,
    this.pinLineHeight = false,
    this.textHeightBehavior,
    this.autoplay = true,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.controller,
    this.progress,
    this.replayKey,
    this.reduceMotion,
    this.semanticsLabel,
    this.onEnd,
  }) : text = null;

  /// The plain text, for the default constructor.
  final String? text;

  /// The runs, for [KineticText.rich].
  final List<TextRun>? runs;

  /// The base style, merged over the ambient [DefaultTextStyle]; a run's own
  /// style is merged over it.
  final TextStyle? style;

  /// Effects over the whole text. Run-scoped effects come from
  /// [TextRun.effects].
  final List<TextEffect> effects;

  /// What a stagger counts and a pose moves.
  final TextUnit unit;

  /// Null reads the ambient [DefaultTextStyle.textAlign], else start.
  final TextAlign? textAlign;

  /// Null reads the ambient [Directionality].
  final TextDirection? textDirection;

  /// Null reads the ambient [DefaultTextStyle.maxLines].
  final int? maxLines;

  /// How overflowing text is handled. Null reads the ambient
  /// [DefaultTextStyle.overflow]. [TextOverflow.ellipsis] ellipsizes the last
  /// line; [TextOverflow.visible] never clips; anything else clips to the box
  /// only when the text overflows it (an effect may still paint outside the
  /// box while it moves). [TextOverflow.fade] is treated as clip.
  final TextOverflow? overflow;

  /// Null reads the ambient [Localizations] locale.
  final Locale? locale;

  /// An explicit strut. Takes precedence over [pinLineHeight].
  final StrutStyle? strutStyle;

  /// Force the strut so the box height is the style's line height regardless
  /// of script — a Latin ↔ Arabic swap then never grows the box.
  final bool pinLineHeight;

  /// Null reads the ambient [DefaultTextStyle.textHeightBehavior].
  final TextHeightBehavior? textHeightBehavior;

  /// Play the one-shot effects once on mount.
  final bool autoplay;

  /// Length of the one-shot run.
  final Duration duration;

  /// Wait before the autoplay starts. Cancelled if the widget unmounts first.
  final Duration delay;

  /// External play control.
  final KineticController? controller;

  /// Drive the one-shot progress from outside instead of the internal clock —
  /// a scroll position, a parent's controller. [autoplay], [duration], [delay]
  /// and [controller] are ignored when set.
  final Animation<double>? progress;

  /// A change replays the one-shot effects.
  final Object? replayKey;

  /// Null reads the platform "disable animations" flag.
  final bool? reduceMotion;

  /// Null speaks the plain text.
  final String? semanticsLabel;

  /// Called when the one-shot run completes.
  final VoidCallback? onEnd;

  /// The plain text, whichever constructor was used.
  String get plainText => text ?? runs!.map((r) => r.text).join();

  /// True when any effect needs a running clock.
  bool get _needsClock {
    for (final e in effects) {
      if (e.continuous) return true;
    }
    final rs = runs;
    if (rs != null) {
      for (final r in rs) {
        for (final e in r.effects) {
          if (e.continuous) return true;
        }
      }
    }
    return false;
  }

  @override
  State<KineticText> createState() => _KineticTextState();
}

class _KineticTextState extends State<KineticText>
    with TickerProviderStateMixin {
  late final AnimationController _progress;
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier(0);

  /// Where the clock was when the ticker last stopped, so a restarted loop
  /// continues from the same phase instead of jumping back to zero.
  double _clockBase = 0;
  Timer? _delayTimer;
  bool _reduced = false;
  bool _autoplayed = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_onStatus);
    _ticker = createTicker((elapsed) {
      _clock.value = _clockBase + elapsed.inMicroseconds / 1e6;
    });
    widget.controller?._state = this;
    if (!widget.autoplay || widget.progress != null) _progress.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = widget.reduceMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    if (_reduced) {
      _cancelDelay();
      _progress.value = 1;
    }
    _scheduleAutoplay();
    _syncClock();
  }

  void _scheduleAutoplay() {
    if (_autoplayed || !widget.autoplay || widget.progress != null) return;
    _autoplayed = true;
    if (_reduced) return;
    if (widget.delay == Duration.zero) {
      _play(from: 0);
    } else {
      _progress.value = 0;
      _delayTimer = Timer(widget.delay, () {
        _delayTimer = null;
        if (mounted && !_reduced) _play(from: 0);
      });
    }
  }

  void _cancelDelay() {
    _delayTimer?.cancel();
    _delayTimer = null;
  }

  @override
  void didUpdateWidget(KineticText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    _progress.duration = widget.duration;
    if (widget.replayKey != old.replayKey && widget.progress == null) {
      _cancelDelay();
      if (_reduced) {
        _progress.value = 1;
      } else {
        _play(from: 0);
      }
    }
    _syncClock();
  }

  TickerFuture _play({double? from}) {
    if (_reduced) {
      _progress.value = 1;
      return TickerFuture.complete();
    }
    return _progress.forward(from: from);
  }

  TickerFuture _reverse() {
    if (_reduced) {
      _progress.value = 0;
      return TickerFuture.complete();
    }
    return _progress.reverse();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) widget.onEnd?.call();
  }

  /// Run the clock only while some effect needs it — a loop, or a cursor
  /// still blinking — and never under reduced motion.
  void _syncClock() {
    final needed = !_reduced && widget._needsClock;
    if (needed && !_ticker.isActive) {
      _ticker.start();
    } else if (!needed && _ticker.isActive) {
      _ticker.stop();
      _clockBase = _clock.value;
    }
  }

  @override
  void dispose() {
    _cancelDelay();
    widget.controller?._state = null;
    _ticker.dispose();
    _progress.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    var style = defaults.style.merge(widget.style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final direction = widget.textDirection ??
        Directionality.maybeOf(context) ??
        TextDirection.ltr;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final align = widget.textAlign ?? defaults.textAlign ?? TextAlign.start;
    final maxLines = widget.maxLines ?? defaults.maxLines;
    final overflow = widget.overflow ?? defaults.overflow;
    final locale = widget.locale ?? Localizations.maybeLocaleOf(context);
    final heightBehavior =
        widget.textHeightBehavior ?? defaults.textHeightBehavior;
    final strut = widget.strutStyle ??
        (widget.pinLineHeight
            ? StrutStyle.fromTextStyle(style, forceStrutHeight: true)
            : null);

    final runs = widget.runs;
    final InlineSpan span;
    final ranges = <(int, int)>[];
    final runEffects = <List<TextEffect>>[];
    if (runs == null) {
      span = TextSpan(text: widget.text, style: style);
    } else {
      var offset = 0;
      final children = <InlineSpan>[];
      for (final r in runs) {
        ranges.add((offset, offset + r.text.length));
        offset += r.text.length;
        children.add(TextSpan(text: r.text, style: r.style));
        runEffects.add(r.effects);
      }
      span = TextSpan(style: style, children: children);
    }

    return _KineticRenderWidget(
      spec: _ShapeSpec(
        span: span,
        text: widget.plainText,
        runRanges: ranges,
        direction: direction,
        scaler: scaler,
        align: align,
        maxLines: maxLines,
        ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
        strut: strut,
        locale: locale,
        heightBehavior: heightBehavior,
        unit: widget.unit,
      ),
      effects: widget.effects,
      runEffects: runEffects,
      progress: widget.progress ?? _progress,
      clock: _clock,
      reduced: _reduced,
      clipOverflow: overflow != TextOverflow.visible,
      label: widget.semanticsLabel ?? widget.plainText,
    );
  }
}

/// Everything a re-shape depends on — and nothing an effect changes, so a new
/// effect list never re-lays the paragraph out.
@immutable
class _ShapeSpec {
  const _ShapeSpec({
    required this.span,
    required this.text,
    required this.runRanges,
    required this.direction,
    required this.scaler,
    required this.align,
    required this.maxLines,
    required this.ellipsis,
    required this.strut,
    required this.locale,
    required this.heightBehavior,
    required this.unit,
  });

  final InlineSpan span;
  final String text;
  final List<(int, int)> runRanges;
  final TextDirection direction;
  final TextScaler scaler;
  final TextAlign align;
  final int? maxLines;
  final String? ellipsis;
  final StrutStyle? strut;
  final Locale? locale;
  final TextHeightBehavior? heightBehavior;
  final TextUnit unit;

  TextPainter painter() => TextPainter(
        text: span,
        textDirection: direction,
        textScaler: scaler,
        textAlign: align,
        maxLines: maxLines,
        ellipsis: ellipsis,
        strutStyle: strut,
        locale: locale,
        textHeightBehavior: heightBehavior,
      );

  ShapedText shape({required double minWidth, required double maxWidth}) =>
      ShapedText.shape(
        span: span,
        text: text,
        direction: direction,
        unit: unit,
        scaler: scaler,
        align: align,
        maxLines: maxLines,
        ellipsis: ellipsis,
        minWidth: minWidth,
        maxWidth: maxWidth,
        strut: strut,
        locale: locale,
        textHeightBehavior: heightBehavior,
        runRanges: runRanges,
      );

  @override
  bool operator ==(Object other) =>
      other is _ShapeSpec &&
      other.span == span &&
      other.text == text &&
      listEquals(other.runRanges, runRanges) &&
      other.direction == direction &&
      other.scaler == scaler &&
      other.align == align &&
      other.maxLines == maxLines &&
      other.ellipsis == ellipsis &&
      other.strut == strut &&
      other.locale == locale &&
      other.heightBehavior == heightBehavior &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(
        span,
        text,
        Object.hashAll(runRanges),
        direction,
        scaler,
        align,
        maxLines,
        ellipsis,
        strut,
        locale,
        heightBehavior,
        unit,
      );
}

class _KineticRenderWidget extends LeafRenderObjectWidget {
  const _KineticRenderWidget({
    required this.spec,
    required this.effects,
    required this.runEffects,
    required this.progress,
    required this.clock,
    required this.reduced,
    required this.clipOverflow,
    required this.label,
  });

  final _ShapeSpec spec;
  final List<TextEffect> effects;
  final List<List<TextEffect>> runEffects;
  final Animation<double> progress;
  final ValueListenable<double> clock;
  final bool reduced;
  final bool clipOverflow;
  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKineticText(
        spec,
        effects,
        runEffects,
        progress,
        clock,
        reduced,
        clipOverflow,
        label,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderKineticText renderObject) {
    renderObject
      ..spec = spec
      ..effects = effects
      ..runEffects = runEffects
      ..progress = progress
      ..clock = clock
      ..reduced = reduced
      ..clipOverflow = clipOverflow
      ..label = label;
  }
}

/// The render object: owns the [ShapedText], re-shapes only when a shaping
/// input or the layout width changes, reports intrinsics and a baseline like
/// a paragraph, repaints on the progress and clock, and is its own repaint
/// boundary so a moving letter never re-records the surface around it.
class _RenderKineticText extends RenderBox {
  // Positional so the private fields can be initializing formals.
  _RenderKineticText(
    this._spec,
    this._effects,
    this._runEffects,
    this._progress,
    this._clock,
    this._reduced,
    this._clipOverflow,
    this._label,
  );

  ShapedText? _shaped;
  double _shapedMinWidth = double.nan;
  double _shapedMaxWidth = double.nan;
  List<(TextEffect, UnitSlice)> _bound = const [];
  List<UnitPose> _poses = const [];

  _ShapeSpec _spec;
  set spec(_ShapeSpec value) {
    if (value == _spec) return;
    _spec = value;
    _shapedMaxWidth = double.nan; // forces a re-shape at the next layout
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  List<TextEffect> _effects;
  set effects(List<TextEffect> value) {
    if (listEquals(value, _effects)) return;
    _effects = value;
    _rebind();
    markNeedsPaint();
  }

  List<List<TextEffect>> _runEffects;
  set runEffects(List<List<TextEffect>> value) {
    var same = value.length == _runEffects.length;
    for (var i = 0; same && i < value.length; i++) {
      same = listEquals(value[i], _runEffects[i]);
    }
    if (same) return;
    _runEffects = value;
    _rebind();
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ValueListenable<double> _clock;
  set clock(ValueListenable<double> value) {
    if (identical(value, _clock)) return;
    if (attached) _clock.removeListener(markNeedsPaint);
    _clock = value;
    if (attached) _clock.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _reduced;
  set reduced(bool value) {
    if (value == _reduced) return;
    _reduced = value;
    markNeedsPaint();
  }

  bool _clipOverflow;
  set clipOverflow(bool value) {
    if (value == _clipOverflow) return;
    _clipOverflow = value;
    markNeedsPaint();
  }

  String _label;
  set label(String value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
    _clock.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    _clock.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _shaped?.dispose();
    _shaped = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => false;

  @override
  bool hitTestSelf(Offset position) => true;

  void _rebind() {
    final shaped = _shaped;
    if (shaped == null) return;
    final all = UnitSlice([for (final u in shaped.units) u.index]);
    _bound = [
      for (final e in _effects) (e, all),
      for (var i = 0; i < _runEffects.length && i < shaped.runRanges.length; i++)
        for (final e in _runEffects[i]) (e, UnitSlice(shaped.unitsOfRun(i))),
    ];
    if (_poses.length != shaped.units.length) {
      _poses = List.generate(shaped.units.length, (_) => UnitPose());
    }
  }

  void _shape(double minWidth, double maxWidth) {
    if (_shaped != null &&
        _shapedMinWidth == minWidth &&
        _shapedMaxWidth == maxWidth) {
      return;
    }
    _shaped?.dispose();
    _shaped = _spec.shape(minWidth: minWidth, maxWidth: maxWidth);
    _shapedMinWidth = minWidth;
    _shapedMaxWidth = maxWidth;
    _rebind();
  }

  /// A throwaway layout for intrinsics and dry layout — no unit boxes, no
  /// state, disposed before returning.
  T _measure<T>(double minWidth, double maxWidth, T Function(TextPainter) f) {
    final painter = _spec.painter()..layout(minWidth: minWidth, maxWidth: maxWidth);
    try {
      return f(painter);
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _measure(0, double.infinity, (p) => p.minIntrinsicWidth);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _measure(0, double.infinity, (p) => p.maxIntrinsicWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _measure(width, width, (p) => p.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _measure(width, width, (p) => p.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(
        constraints.minWidth,
        constraints.maxWidth,
        (p) => constraints.constrain(p.size),
      );

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) =>
      _measure(
        constraints.minWidth,
        constraints.maxWidth,
        (p) => p.computeDistanceToActualBaseline(baseline),
      );

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _shaped?.baselineOffset(baseline);

  @override
  void performLayout() {
    _shape(constraints.minWidth, constraints.maxWidth);
    size = constraints.constrain(_shaped!.size);
  }

  bool get _overflows {
    final s = _shaped!.size;
    return s.width > size.width || s.height > size.height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_clipOverflow && _overflows) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        _paintText,
      );
    } else {
      _paintText(context, offset);
    }
  }

  void _paintText(PaintingContext context, Offset offset) {
    final frame = composeFrame(
      shaped: _shaped!,
      effects: _bound,
      progress: _progress.value,
      time: _clock.value,
      reduced: _reduced,
      poses: _poses,
    );
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    paintFrame(canvas, frame);
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _label
      ..textDirection = _spec.direction;
  }
}
