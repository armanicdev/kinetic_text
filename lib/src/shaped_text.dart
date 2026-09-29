import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The grain of a piece of kinetic text — what a stagger counts, what a pose
/// moves, what an ink pass paints.
enum TextUnit {
  /// One user-perceived character (a grapheme cluster): `e`, `é`, a joined
  /// Arabic letter, a flag emoji. Whitespace is never a unit — it has no ink.
  /// Characters the font draws as ONE glyph (a ligature) are one unit, so a
  /// moving letter never carries half a glyph.
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

/// One line of a shaped paragraph — where its units sit and where an
/// underline goes.
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
/// that knows how — plus the box of every unit inside it, so an effect can
/// move, fade, scale or recolour a single cluster. That is what keeps an
/// animated Kurdish or Arabic label joined: nothing is ever laid out as a
/// separate string.
///
/// ## Glyph-exact units
///
/// A glyph's ink does not stop at its box. The tail of a Kurdish `ڕ` and the
/// small V under it reach past the letter's advance, into the next letter's
/// box and below the line; so do an italic `f`, a swash, a stacked Arabic
/// mark. Cutting a moving letter out along its box would slice that ink off
/// the letter and leave it behind on its neighbour.
///
/// So every unit is drawn from a CLASS TWIN: the same paragraph laid out again
/// with the same metrics, in which only one class of units keeps its ink and
/// every other code unit is transparent. Units of one class are never near
/// each other ([classOf]), so clipping a class twin to a generous cell
/// ([cellOf], the unit's box plus [overhang] on every side) yields exactly
/// that unit's glyphs — their tails and marks included, none of their
/// neighbours'. The twins stack back into the original pixel for pixel, and
/// they are built lazily, the first time a unit moves.
///
/// Immutable after construction. Expensive to build (one layout plus a box
/// query per unit); cheap to paint. Re-shape only when an input changes, and
/// [dispose] it when done — it owns native paragraphs.
class ShapedText {
  /// How many times [shape] has run — a test hook for asserting that a
  /// rebuild did NOT re-lay the paragraph out.
  @visibleForTesting
  static int debugShapeCount = 0;

  /// How far a unit's ink may reach past its box and still move whole, as a
  /// fraction of its line's height — on each side, and below or above its
  /// line. Generous for tails and marks (a `ڕ` reaches ~0.2 of a line), small
  /// enough that a class needs only a handful of twins.
  static const double overhang = 0.4;

  ShapedText._({
    required this.painter,
    required this.text,
    required this.unit,
    required this.units,
    required this.lines,
    required this.direction,
    required this.runRanges,
    required List<Rect> cells,
    required List<int> classes,
    required List<TextDirection?> unitDirections,
    required bool decorated,
    required TextPainter Function(InlineSpan span) relayout,
  })  : _cells = cells,
        _classes = classes,
        _unitDirections = unitDirections,
        _decorated = decorated,
        _relayout = relayout,
        classCount = classes.isEmpty ? 0 : classes.reduce(math.max) + 1 {
    _members = List.generate(classCount, (_) => <int>[]);
    for (var i = 0; i < classes.length; i++) {
      _members[classes[i]].add(i);
    }
  }

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
      TextUnit.grapheme =>
        _mergeLigatures(painter, _graphemeUnits(painter, text, lines)),
      TextUnit.word => _wordUnits(painter, text, lines),
      TextUnit.line => _lineUnits(painter, text, lines),
    };
    final cells = [for (final u in units) _cellFor(u, lines)];

    return ShapedText._(
      painter: painter,
      text: text,
      unit: unit,
      units: List.unmodifiable(units),
      lines: List.unmodifiable(lines),
      direction: direction,
      runRanges: List.unmodifiable(runRanges),
      cells: cells,
      classes: _classify(units, cells),
      unitDirections: [
        for (final u in units) directionOf(text.substring(u.start, u.end)),
      ],
      decorated: _isDecorated(span),
      relayout: relayout,
    );
  }

  /// The one laid-out painter the resting text is drawn from.
  final TextPainter painter;

  final TextPainter Function(InlineSpan span) _relayout;
  final List<Rect> _cells;
  final List<int> _classes;
  late final List<List<int>> _members;
  final List<TextDirection?> _unitDirections;
  final bool _decorated;

  /// The plain text.
  final String text;

  /// The grain the units were cut at.
  final TextUnit unit;

  /// Every unit, in reading order.
  final List<UnitBox> units;

  /// Every laid-out line, top to bottom.
  final List<LineBand> lines;

  /// The paragraph's direction.
  final TextDirection direction;

  /// The caller's run ranges (code units), in order.
  final List<(int, int)> runRanges;

  /// How many classes the units fall into — how many twins a frame with a
  /// moving unit draws the resting text from.
  final int classCount;

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

  /// The class of unit [index]: units of one class are far enough apart that
  /// none reaches into another's [cellOf].
  int classOf(int index) => _classes[index];

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

  /// The rect around the [cellOf] every unit of [indices] — all the ink they
  /// can own — or [Rect.zero] when empty.
  Rect cellsOf(Iterable<int> indices) {
    Rect? r;
    for (final i in indices) {
      final b = _cells[i];
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

  /// The cell a unit's ink is cut from: its box plus [overhang] on each side,
  /// grown by [scale] about its centre, and its line plus [overhang] above
  /// and below — open a full line past the paragraph's top and bottom edges,
  /// where nothing else lives.
  Rect cellOf(UnitBox u, {double scale = 1}) {
    final cell = _cells[u.index];
    if (scale <= 1) return cell;
    final hw = cell.width / 2 * scale;
    final cx = cell.center.dx;
    return Rect.fromLTRB(cx - hw, cell.top, cx + hw, cell.bottom);
  }

  /// Bounds generous enough for a resting paragraph and every cell: the
  /// paragraph plus a line height on every side. The compositor grows this
  /// further for whatever the current frame's poses actually reach.
  Rect get paintBounds {
    final grow = lines.isEmpty ? 0.0 : lines.map((l) => l.height).reduce(math.max);
    return Rect.fromLTRB(-grow, -grow, width + grow, height + grow);
  }

  /// The direction the units of [indices] READ in — the direction of their
  /// first strong character (a letter), or the paragraph's direction when
  /// they hold none (figures, symbols). A Kurdish word in an English label
  /// reads right to left; a sweep over it should too.
  TextDirection readingDirectionOf(Iterable<int> indices) {
    for (final i in indices) {
      final d = _unitDirections[i];
      if (d != null) return d;
    }
    return direction;
  }

  // --- twins -----------------------------------------------------------------

  final Map<Object, TextPainter> _twins = {};
  (double, Color?)? _strokeKey;

  /// The paragraph with only class [cls]'s units inked — each in its own
  /// style — and every other code unit transparent. Same layout, same joins.
  TextPainter classTwin(int cls) => _twins.putIfAbsent(
        ('ink', cls),
        () => _relayout(_Reink(_maskOf(cls), stripDecor: _decorated)
            .span(painter.text!, _Ink.root)),
      );

  /// The same paragraph laid out again with every glyph's ink replaced by a
  /// stroke of [width] — in [color], or in each span's own ink when [color]
  /// is null — so an effect can draw a unit's OUTLINE. Built once per (width,
  /// colour) and owned by this object.
  TextPainter strokedTwin({required double width, Color? color}) =>
      _strokeTwin(null, width, color);

  TextPainter _strokeTwin(int? cls, double width, Color? color) {
    final key = (width, color);
    if (_strokeKey != key) {
      _twins.removeWhere((k, p) {
        final stale = k is (String, int?) && k.$1 == 'stroke';
        if (stale) p.dispose();
        return stale;
      });
      _strokeKey = key;
    }
    return _twins.putIfAbsent(
      ('stroke', cls),
      () => _relayout(
        _Reink(cls == null ? null : _maskOf(cls),
                stroke: width, strokeColor: color, stripDecor: true)
            .span(painter.text!, _Ink.root),
      ),
    );
  }

  /// Decorations and backgrounds only — no glyph ink — in the original's own
  /// style blocks, so an underline or a highlight colour behind moving
  /// letters is drawn once, exactly, and stays on the line.
  TextPainter? get _decorTwin => !_decorated
      ? null
      : _twins.putIfAbsent(
          'decor',
          () => _relayout(_Reink(null, decorOnly: true)
              .span(painter.text!, _Ink.root)),
        );

  List<bool> _maskOf(int cls) {
    final mask = List<bool>.filled(text.length, false);
    for (final i in _members[cls]) {
      final u = units[i];
      for (var c = u.start; c < u.end && c < mask.length; c++) {
        mask[c] = true;
      }
    }
    return mask;
  }

  /// Paint exactly the ink of the units of [indices], at rest — their tails
  /// and marks included, none of their neighbours'. With [stroke], their
  /// outline instead, in [strokeColor] or their own ink.
  void paintUnits(
    Canvas canvas,
    Iterable<int> indices, {
    double? stroke,
    Color? strokeColor,
  }) {
    final byClass = <int, List<int>>{};
    var count = 0;
    for (final i in indices) {
      byClass.putIfAbsent(_classes[i], () => <int>[]).add(i);
      count++;
    }
    if (count == 0) return;
    if (count >= units.length) {
      if (stroke != null) {
        strokedTwin(width: stroke, color: strokeColor).paint(canvas, Offset.zero);
        return;
      }
      if (!_decorated) {
        painter.paint(canvas, Offset.zero);
        return;
      }
    }
    for (final MapEntry(key: cls, value: members) in byClass.entries) {
      canvas.save();
      if (members.length == 1) {
        canvas.clipRect(_cells[members.first]);
      } else {
        final area = Path();
        for (final i in members) {
          area.addRect(_cells[i]);
        }
        canvas.clipPath(area);
      }
      final twin =
          stroke == null ? classTwin(cls) : _strokeTwin(cls, stroke, strokeColor);
      twin.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Paint the whole paragraph at rest except the units marked in [skip]
  /// (indexed by unit) — every class twin with those units' cells cut out,
  /// plus the decorations. Null or all-false [skip] is one plain paint.
  void paintExcept(Canvas canvas, List<bool>? skip) {
    if (skip == null || !skip.contains(true)) {
      painter.paint(canvas, Offset.zero);
      return;
    }
    _decorTwin?.paint(canvas, Offset.zero);
    for (var c = 0; c < classCount; c++) {
      final members = _members[c];
      var cut = 0;
      for (final i in members) {
        if (skip[i]) cut++;
      }
      if (cut == members.length) continue; // the whole class is elsewhere
      final twin = classTwin(c);
      if (cut == 0) {
        twin.paint(canvas, Offset.zero);
        continue;
      }
      canvas.save();
      for (final i in members) {
        if (skip[i]) canvas.clipRect(_cells[i], clipOp: ui.ClipOp.difference);
      }
      twin.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Free the native paragraphs. The object must not be painted afterwards.
  void dispose() {
    painter.dispose();
    for (final p in _twins.values) {
      p.dispose();
    }
    _twins.clear();
  }

  // --- direction -------------------------------------------------------------

  /// The direction [text] reads in by the Unicode paragraph rule (the HTML
  /// `dir="auto"` rule): that of its first strong character — a letter, or a
  /// left-to-right or right-to-left mark — skipping isolated runs. Null when
  /// the text holds no strong character (figures, symbols, emoji), so the
  /// caller can fall back to its surroundings.
  static TextDirection? directionOf(String text) {
    var isolated = 0;
    for (final r in text.runes) {
      switch (r) {
        case 0x2066 || 0x2067 || 0x2068: // LRI, RLI, FSI
          isolated++;
          continue;
        case 0x2069: // PDI
          if (isolated > 0) isolated--;
          continue;
        case 0x200E: // LRM
          if (isolated == 0) return TextDirection.ltr;
          continue;
        case 0x200F || 0x061C: // RLM, ALM
          if (isolated == 0) return TextDirection.rtl;
          continue;
      }
      if (isolated > 0 || !_isLetter(r)) continue;
      return _isRtlBlock(r) ? TextDirection.rtl : TextDirection.ltr;
    }
    return null;
  }

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  static bool _isLetter(int r) {
    if (r < 0x80) return (r | 0x20) >= 0x61 && (r | 0x20) <= 0x7A;
    return _letter.hasMatch(String.fromCharCode(r));
  }

  /// Blocks whose letters are all right-to-left: Hebrew through Arabic
  /// Extended-A, the Hebrew and Arabic presentation forms, and the
  /// supplementary right-to-left planes.
  static bool _isRtlBlock(int r) =>
      (r >= 0x0590 && r <= 0x08FF) ||
      (r >= 0xFB1D && r <= 0xFDFF) ||
      (r >= 0xFE70 && r <= 0xFEFF) ||
      (r >= 0x10800 && r <= 0x10FFF) ||
      (r >= 0x1E800 && r <= 0x1EFFF);

  // --- unit indexing ---------------------------------------------------------

  static Rect _cellFor(UnitBox u, List<LineBand> lines) {
    final line = lines[u.line];
    final m = line.height * overhang;
    final top = u.line == 0 ? line.top - line.height : line.top - m;
    final bottom =
        u.line == lines.length - 1 ? line.bottom + line.height : line.bottom + m;
    return Rect.fromLTRB(u.rect.left - m, top, u.rect.right + m, bottom);
  }

  /// Greedy colouring: a unit takes the lowest class no earlier unit whose
  /// cell overlaps its own already holds. On one line that is optimal (an
  /// interval graph); across lines it stays small.
  static List<int> _classify(List<UnitBox> units, List<Rect> cells) {
    final classes = List<int>.filled(units.length, 0);
    final byLine = <int, List<int>>{};
    for (final u in units) {
      final cell = cells[u.index];
      final taken = <int>{};
      for (var l = u.line - 2; l <= u.line + 2; l++) {
        for (final j in byLine[l] ?? const <int>[]) {
          if (cells[j].overlaps(cell)) taken.add(classes[j]);
        }
      }
      var k = 0;
      while (taken.contains(k)) {
        k++;
      }
      classes[u.index] = k;
      byLine.putIfAbsent(u.line, () => <int>[]).add(u.index);
    }
    return classes;
  }

  static bool _isDecorated(InlineSpan span) {
    var found = false;
    span.visitChildren((s) {
      final st = s.style;
      if (st != null &&
          ((st.decoration != null && st.decoration != TextDecoration.none) ||
              st.background != null ||
              st.backgroundColor != null)) {
        found = true;
      }
      return !found;
    });
    return found;
  }

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

  /// Graphemes the font set as ONE glyph (a ligature: `fi`, a lam-alef) are
  /// one unit — split, each half would carry a sliver of the other.
  static List<UnitBox> _mergeLigatures(TextPainter painter, List<UnitBox> units) {
    if (units.length < 2) return units;
    final out = <UnitBox>[];
    var i = 0;
    while (i < units.length) {
      var u = units[i];
      var j = i + 1;
      final range =
          painter.getClosestGlyphForOffset(u.rect.center)?.graphemeClusterCodeUnitRange;
      if (range != null && range.start <= u.start && range.end > u.end) {
        while (j < units.length &&
            units[j].start < range.end &&
            units[j].line == u.line) {
          u = UnitBox(
            index: u.index,
            start: u.start,
            end: units[j].end,
            rect: u.rect.expandToInclude(units[j].rect),
            line: u.line,
            direction: u.direction,
          );
          j++;
        }
      }
      out.add(u.index == out.length
          ? u
          : UnitBox(
              index: out.length,
              start: u.start,
              end: u.end,
              rect: u.rect,
              line: u.line,
              direction: u.direction,
            ));
      i = j;
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

/// The ink a span resolves to, carried down the tree so a stroked twin can
/// outline each span in its own colour and a decoration twin can keep an
/// underline in the colour it had.
@immutable
class _Ink {
  const _Ink(this.color, this.shader, this.decorationColor);

  static const _Ink root = _Ink(Color(0xFF000000), null, null);

  final Color color;
  final Shader? shader;
  final Color? decorationColor;

  _Ink merge(TextStyle? s) {
    if (s == null) return this;
    final fg = s.foreground;
    return _Ink(
      fg?.color ?? s.color ?? color,
      fg != null ? fg.shader : (s.color != null ? null : shader),
      s.decorationColor ?? decorationColor,
    );
  }
}

/// Rebuilds a span tree with its ink re-assigned, keeping every metric: the
/// code units [on] marks keep their ink (or trade it for a [stroke]); the
/// rest turn transparent. Only paint attributes change, so the engine shapes
/// the twin exactly as it shaped the original — same glyphs, same joins, same
/// positions.
class _Reink {
  _Reink(
    this.on, {
    this.stroke,
    this.strokeColor,
    this.stripDecor = false,
    this.decorOnly = false,
  });

  /// Per code unit, whether it keeps its ink. Null = every code unit does.
  final List<bool>? on;
  final double? stroke;
  final Color? strokeColor;

  /// Drop decorations and backgrounds from the inked code units (the decor
  /// twin draws them).
  final bool stripDecor;

  /// Keep decorations and backgrounds only; every glyph transparent.
  final bool decorOnly;

  int _offset = 0;

  static final Paint _clearPaint = Paint()..color = const Color(0x00000000);
  static final TextStyle _clear = TextStyle(
    foreground: _clearPaint,
    background: _clearPaint,
    decoration: TextDecoration.none,
    shadows: const [],
  );
  static final TextStyle _undecorated = TextStyle(
    background: _clearPaint,
    decoration: TextDecoration.none,
  );

  TextStyle? _inked(_Ink ink) {
    final w = stroke;
    if (w == null) return stripDecor ? _undecorated : null;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = strokeColor ?? ink.color;
    if (strokeColor == null && ink.shader != null) paint.shader = ink.shader;
    return TextStyle(
      foreground: paint,
      background: _clearPaint,
      decoration: TextDecoration.none,
      shadows: const [],
    );
  }

  InlineSpan span(InlineSpan s, _Ink inherited) {
    if (s is! TextSpan) {
      _offset += 1; // a placeholder is one object-replacement character
      return s;
    }
    final ink = inherited.merge(s.style);
    final children = <InlineSpan>[];
    final t = s.text;
    if (t != null && t.isNotEmpty) {
      final start = _offset;
      _offset += t.length;
      if (decorOnly) {
        children.add(TextSpan(
          text: t,
          style: TextStyle(
            foreground: _clearPaint,
            shadows: const [],
            decorationColor: ink.decorationColor ?? ink.color,
          ),
        ));
      } else {
        final mask = on;
        bool isOn(int i) => mask == null || (i < mask.length && mask[i]);
        var a = 0;
        for (var i = 1; i <= t.length; i++) {
          if (i == t.length || isOn(start + i) != isOn(start + a)) {
            children.add(TextSpan(
              text: t.substring(a, i),
              style: isOn(start + a) ? _inked(ink) : _clear,
            ));
            a = i;
          }
        }
      }
    }
    for (final c in s.children ?? const <InlineSpan>[]) {
      children.add(span(c, ink));
    }
    return TextSpan(style: s.style, children: children, locale: s.locale);
  }
}
