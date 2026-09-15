import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The grain of a piece of kinetic text — what a stagger counts, what a pose
/// moves, what an ink pass paints.
enum TextUnit {
  /// One user-perceived character (a grapheme cluster): `e`, `é`, a joined
  /// Arabic letter, a flag emoji. Whitespace is never a unit — it has no ink.
  grapheme,

  /// A run of non-whitespace graphemes.
  word,

  /// One laid-out line.
  line,
}

/// One unit of a [ShapedText]: its code-unit range, its physical box, and the
/// line it sits on. Units are numbered in READING order (by text offset), so a
/// stagger over `index` reads first-to-last in every script, while `rect` is
/// physical — the leftmost box of an Arabic line is its LAST unit.
class UnitBox {
  /// A unit at [index] covering `[start, end)` of the text, laid out in [rect]
  /// on [line].
  const UnitBox({
    required this.index,
    required this.start,
    required this.end,
    required this.rect,
    required this.line,
    required this.direction,
  });

  /// Position in reading order, `0 ≤ index < units.length`.
  final int index;

  /// Code-unit range in the plain text, `[start, end)`.
  final int start;

  /// End (exclusive) of the code-unit range.
  final int end;

  /// The union of the unit's glyph boxes, in the painter's coordinate space.
  final Rect rect;

  /// Zero-based line the unit is laid out on.
  final int line;

  /// Direction of the unit's own run (a Latin word inside an Arabic sentence
  /// is LTR).
  final TextDirection direction;

  /// The centre of [rect].
  Offset get center => rect.center;

  /// The width of [rect].
  double get width => rect.width;

  @override
  String toString() => 'UnitBox#$index[$start,$end) line $line $rect';
}

/// One line of a shaped paragraph — the band a unit's glyphs are clipped to
/// while it moves, and where an underline sits.
class LineBand {
  /// Line [index] spanning [top]..[bottom] and [left]..[right], with its
  /// [baseline].
  const LineBand({
    required this.index,
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.left,
    required this.right,
  });

  /// Zero-based line number.
  final int index;

  /// Top edge of the line box.
  final double top;

  /// Bottom edge of the line box.
  final double bottom;

  /// The alphabetic baseline, in the same space as [top].
  final double baseline;

  /// Left edge of the line's ink.
  final double left;

  /// Right edge of the line's ink.
  final double right;

  /// `bottom - top`.
  double get height => bottom - top;

  /// The line box as a rect.
  Rect get rect => Rect.fromLTRB(left, top, right, bottom);
}

/// A paragraph shaped ONCE — one [TextPainter] for the whole text, so cursive
/// joins, ligatures, kerning and bidi ordering are all resolved by the engine
/// that knows how — plus the box of every unit inside it, so an effect can move,
/// fade, scale or recolour a single cluster by clipping to its cell and
/// re-drawing the same painter. That is what keeps an animated Kurdish or
/// Arabic label joined: nothing is ever laid out as a separate string.
///
/// Immutable after construction. Expensive to build (one layout plus a box
/// query per unit); cheap to paint. Re-shape only when an input changes, and
/// [dispose] it when done — it owns a native paragraph.
class ShapedText {
  /// How many times [shape] has run — a test hook for asserting that a
  /// rebuild did NOT re-lay the paragraph out.
  @visibleForTesting
  static int debugShapeCount = 0;

  ShapedText._({
    required this.painter,
    required this.text,
    required this.unit,
    required this.units,
    required this.lines,
    required this.direction,
    required this.runRanges,
    required TextPainter Function(InlineSpan span) relayout,
  }) : _relayout = relayout;

  /// Shape [span] between [minWidth] and [maxWidth] and index its units.
  ///
  /// [span] may carry children with their own styles ([KineticText.rich]);
  /// [text] must be its plain concatenation. [runRanges] are the code-unit
  /// ranges of the caller's runs, if any, so [unitsOfRun] can resolve them.
  /// [ellipsis] is applied where the painter would apply it (a [maxLines]
  /// overflow).
  factory ShapedText.shape({
    required InlineSpan span,
    required String text,
    required TextDirection direction,
    TextUnit unit = TextUnit.grapheme,
    TextScaler scaler = TextScaler.noScaling,
    TextAlign align = TextAlign.start,
    int? maxLines,
    String? ellipsis,
    double minWidth = 0,
    double maxWidth = double.infinity,
    StrutStyle? strut,
    Locale? locale,
    TextHeightBehavior? textHeightBehavior,
    List<(int, int)> runRanges = const [],
  }) {
    debugShapeCount++;
    TextPainter relayout(InlineSpan s) => TextPainter(
          text: s,
          textDirection: direction,
          textScaler: scaler,
          textAlign: align,
          maxLines: maxLines,
          ellipsis: ellipsis,
          strutStyle: strut,
          locale: locale,
          textHeightBehavior: textHeightBehavior,
        )..layout(minWidth: minWidth, maxWidth: maxWidth);
    final painter = relayout(span);

    final metrics = painter.computeLineMetrics();
    final lines = <LineBand>[];
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      final top = m.baseline - m.ascent;
      lines.add(LineBand(
        index: i,
        top: top,
        bottom: top + m.height,
        baseline: m.baseline,
        left: m.left,
        right: m.left + m.width,
      ));
    }

    final units = switch (unit) {
      TextUnit.grapheme => _graphemeUnits(painter, text, lines),
      TextUnit.word => _wordUnits(painter, text, lines),
      TextUnit.line => _lineUnits(painter, text, lines),
    };

    return ShapedText._(
      painter: painter,
      text: text,
      unit: unit,
      units: List.unmodifiable(units),
      lines: List.unmodifiable(lines),
      direction: direction,
      runRanges: List.unmodifiable(runRanges),
      relayout: relayout,
    );
  }

  /// The one laid-out painter every unit is re-drawn from.
  final TextPainter painter;

  final TextPainter Function(InlineSpan span) _relayout;
  TextPainter? _stroked;
  (double, Color)? _strokeKey;

  /// The same paragraph laid out again with every span's ink replaced by a
  /// stroke of [width] in [color] — identical metrics, identical joins, so an
  /// effect can draw a unit's OUTLINE by clipping to its cell. Built once per
  /// (width, colour) and owned by this object.
  TextPainter strokedTwin({required double width, required Color color}) {
    final key = (width, color);
    if (_strokeKey != key) {
      _stroked?.dispose();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color;
      _stroked = _relayout(_strokeSpan(painter.text!, paint));
      _strokeKey = key;
    }
    return _stroked!;
  }

  static InlineSpan _strokeSpan(InlineSpan span, Paint paint) {
    if (span is! TextSpan) return span;
    final style = span.style;
    return TextSpan(
      text: span.text,
      children: span.children?.map((c) => _strokeSpan(c, paint)).toList(),
      style: style == null ? TextStyle(foreground: paint) : _strokedStyle(style, paint),
      locale: span.locale,
    );
  }

  /// [s] with its colour swapped for [paint]. A style cannot carry both a
  /// colour and a foreground, and `copyWith` cannot clear one, so rebuild.
  static TextStyle _strokedStyle(TextStyle s, Paint paint) => TextStyle(
        inherit: s.inherit,
        foreground: paint,
        fontSize: s.fontSize,
        fontWeight: s.fontWeight,
        fontStyle: s.fontStyle,
        letterSpacing: s.letterSpacing,
        wordSpacing: s.wordSpacing,
        textBaseline: s.textBaseline,
        height: s.height,
        leadingDistribution: s.leadingDistribution,
        locale: s.locale,
        fontFeatures: s.fontFeatures,
        fontVariations: s.fontVariations,
        fontFamily: s.fontFamily,
        fontFamilyFallback: s.fontFamilyFallback,
        overflow: s.overflow,
      );

  /// The plain text.
  final String text;

  /// The grain the units were cut at.
  final TextUnit unit;

  /// Every unit, in reading order.
  final List<UnitBox> units;

  /// Every laid-out line, top to bottom.
  final List<LineBand> lines;

  /// The paragraph's ambient direction.
  final TextDirection direction;

  /// The caller's run ranges (code units), in order.
  final List<(int, int)> runRanges;

  /// The laid-out size.
  Size get size => painter.size;

  /// The laid-out width — the widest line, within the layout's max width.
  double get width => painter.width;

  /// The laid-out height.
  double get height => painter.height;

  /// The narrowest width the text could be laid out at (its longest word).
  double get minIntrinsicWidth => painter.minIntrinsicWidth;

  /// The width the text wants with no wrapping.
  double get maxIntrinsicWidth => painter.maxIntrinsicWidth;

  /// True for an RTL paragraph.
  bool get isRtl => direction == TextDirection.rtl;

  /// Distance from the top of the paragraph to its first [baseline].
  double baselineOffset(TextBaseline baseline) =>
      painter.computeDistanceToActualBaseline(baseline);

  /// The line a unit sits on.
  LineBand lineOf(UnitBox u) => lines[u.line];

  /// Indices of the units that overlap the code-unit range `[start, end)`.
  List<int> unitsInRange(int start, int end) => [
        for (final u in units)
          if (u.start < end && u.end > start) u.index,
      ];

  /// Indices of the units of the caller's [runIndex]-th run.
  List<int> unitsOfRun(int runIndex) {
    final (s, e) = runRanges[runIndex];
    return unitsInRange(s, e);
  }

  /// The tightest rect around a set of units, or [Rect.zero] when empty.
  Rect boundsOf(Iterable<int> indices) {
    Rect? r;
    for (final i in indices) {
      final b = units[i].rect;
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }

  /// The units of [indices] grouped by line, each group's tight rect — what a
  /// highlight or an underline draws, one piece per wrapped line.
  List<(LineBand, Rect)> lineRectsOf(Iterable<int> indices) {
    final byLine = <int, Rect>{};
    for (final i in indices) {
      final u = units[i];
      byLine.update(u.line, (r) => r.expandToInclude(u.rect),
          ifAbsent: () => u.rect);
    }
    final keys = byLine.keys.toList()..sort();
    return [for (final k in keys) (lines[k], byLine[k]!)];
  }

  /// The band a unit is clipped to while it moves: its own horizontal box
  /// (grown by [scale] about its centre so a popped glyph can spread into the
  /// side-bearings instead of being sliced) and its line's vertical band —
  /// open to the paragraph's outer edges on the first and last line, so a
  /// single-line label can breathe, and exact between lines so a moving glyph
  /// never paints over its neighbour above or below.
  Rect cellOf(UnitBox u, {double scale = 1}) {
    final line = lines[u.line];
    final hw = u.rect.width / 2 * math.max(scale, 1);
    final cx = u.rect.center.dx;
    final grow = line.height;
    final top = u.line == 0 ? line.top - grow : line.top;
    final bottom = u.line == lines.length - 1 ? line.bottom + grow : line.bottom;
    return Rect.fromLTRB(cx - hw, top, cx + hw, bottom);
  }

  /// Bounds generous enough for a resting paragraph and small poses: the
  /// paragraph plus a line height on every side. The compositor grows this
  /// further for whatever the current frame's poses actually reach.
  Rect get paintBounds {
    final grow = lines.isEmpty ? 0.0 : lines.first.height;
    return Rect.fromLTRB(-grow, -grow, width + grow, height + grow);
  }

  /// Free the native paragraph. The object must not be painted afterwards.
  void dispose() {
    painter.dispose();
    _stroked?.dispose();
    _stroked = null;
  }

  // --- unit indexing ---------------------------------------------------------

  static Rect? _unionBoxes(List<ui.TextBox> boxes) {
    if (boxes.isEmpty) return null;
    var r = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      r = r.expandToInclude(b.toRect());
    }
    return r;
  }

  static int _lineAt(List<LineBand> lines, Rect r) {
    final cy = r.center.dy;
    for (final l in lines) {
      if (cy >= l.top && cy < l.bottom) return l.index;
    }
    // Between bands (rounding) or past the last: nearest by centre.
    var best = 0;
    var bestD = double.infinity;
    for (final l in lines) {
      final d = ((l.top + l.bottom) / 2 - cy).abs();
      if (d < bestD) {
        bestD = d;
        best = l.index;
      }
    }
    return best;
  }

  static UnitBox? _unitFor(
    TextPainter painter,
    List<LineBand> lines,
    int index,
    int start,
    int end,
  ) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    final rect = _unionBoxes(boxes);
    if (rect == null || rect.width <= 0) return null;
    return UnitBox(
      index: index,
      start: start,
      end: end,
      rect: rect,
      line: _lineAt(lines, rect),
      direction: boxes.first.direction,
    );
  }

  static bool _isSpace(String grapheme) => grapheme.trim().isEmpty;

  static List<UnitBox> _graphemeUnits(
    TextPainter painter,
    String text,
    List<LineBand> lines,
  ) {
    final out = <UnitBox>[];
    var offset = 0;
    for (final g in text.characters) {
      final start = offset;
      final end = offset + g.length;
      offset = end;
      if (_isSpace(g)) continue;
      final u = _unitFor(painter, lines, out.length, start, end);
      if (u != null) out.add(u);
    }
    return out;
  }

  static List<UnitBox> _wordUnits(
    TextPainter painter,
    String text,
    List<LineBand> lines,
  ) {
    final out = <UnitBox>[];
    var offset = 0;
    int? wordStart;
    void close(int end) {
      if (wordStart == null) return;
      final u = _unitFor(painter, lines, out.length, wordStart!, end);
      if (u != null) out.add(u);
      wordStart = null;
    }

    for (final g in text.characters) {
      final start = offset;
      offset += g.length;
      if (_isSpace(g)) {
        close(start);
      } else {
        wordStart ??= start;
      }
    }
    close(offset);
    return out;
  }

  static List<UnitBox> _lineUnits(
    TextPainter painter,
    String text,
    List<LineBand> lines,
  ) {
    final out = <UnitBox>[];
    for (final l in lines) {
      final probe = Offset((l.left + l.right) / 2, (l.top + l.bottom) / 2);
      final pos = painter.getPositionForOffset(probe);
      final range = painter.getLineBoundary(pos);
      if (!range.isValid || range.isCollapsed) continue;
      // Trim trailing whitespace so the box hugs the ink.
      var end = range.end;
      while (end > range.start && _isSpace(text[end - 1])) {
        end--;
      }
      if (end <= range.start) continue;
      final u = _unitFor(painter, lines, out.length, range.start, end);
      if (u != null) out.add(u);
    }
    return out;
  }
}
