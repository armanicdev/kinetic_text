import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'effect.dart';
import 'frame.dart';
import 'shaped_text.dart';

/// Build the [TextFrame] for one paint: reset [poses], let every bound effect
/// write into it (skipping motion under [reduced]).
TextFrame composeFrame({
  required ShapedText shaped,
  required List<(TextEffect, UnitSlice)> effects,
  required double progress,
  required double time,
  required bool reduced,
  required List<UnitPose> poses,
}) {
  for (final p in poses) {
    p.reset();
  }
  final frame = TextFrame(
    shaped: shaped,
    progress: reduced ? 1.0 : progress,
    time: time,
    poses: poses,
  );
  for (final (e, slice) in effects) {
    if (reduced && e.motionOnly) continue;
    e.apply(frame, slice);
  }
  return frame;
}

/// Paint a composed [frame]: decor behind, the glyphs, decor over.
void paintFrame(Canvas canvas, TextFrame frame, {Offset origin = Offset.zero}) {
  if (origin != Offset.zero) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
  }
  for (final d in frame.behind) {
    d(canvas, frame);
  }
  paintGlyphs(canvas, frame);
  for (final d in frame.over) {
    d(canvas, frame);
  }
  if (origin != Offset.zero) canvas.restore();
}

/// The glyphs of [frame], every unit whole.
///
/// A frame at rest with no ink pass is ONE plain paint of the paragraph, so a
/// finished reveal costs no more than a [Text]. Otherwise:
///
/// * the units at rest are drawn from the class twins with the moving and
///   recoloured units' cells cut out ([ShapedText.paintExcept]), with the
///   passes that cover the whole text applied over them in one layer;
/// * units at rest under a pass of their own are drawn exactly
///   ([ShapedText.paintUnits]) into a layer per set of passes;
/// * every moving unit is drawn exactly, at rest, into its own layer whose
///   image filter carries the pose, with its passes applied inside.
///
/// Drawing a moving glyph at rest and resampling the raster through a matrix
/// filter (the trick behind `Transform.filterQuality`) keeps it smooth at any
/// fraction of a pixel; under a raw canvas transform the engine would snap it
/// to the pixel grid and re-rasterize it at every scale, so a slow drift or a
/// slight grow would step. Settled text is crisp vector text.
void paintGlyphs(Canvas canvas, TextFrame frame, {Offset origin = Offset.zero}) {
  final shaped = frame.shaped;
  if (!frame.anyPosed && frame.ink.isEmpty) {
    shaped.painter.paint(canvas, origin);
    return;
  }
  if (origin != Offset.zero) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
  }
  _paintPlan(canvas, _Plan(frame));
  if (origin != Offset.zero) canvas.restore();
}

/// The glyphs of [frame] for the units of [only] alone, posed and inked as in
/// [paintGlyphs] — what a glow blurs, what a custom decor can trace.
void paintGlyphsOf(Canvas canvas, TextFrame frame, Iterable<int> only) {
  _paintPlan(canvas, _Plan(frame), only: only.toSet());
}

/// Who draws what in one frame.
class _Plan {
  _Plan(this.frame) : shaped = frame.shaped {
    final ink = frame.ink;
    final n = shaped.units.length;
    whole = List<bool>.filled(ink.length, false);
    passes = List<List<int>?>.filled(n, null);
    for (var i = 0; i < ink.length; i++) {
      final us = ink[i].units;
      if (us == null || (us.length >= n && us.toSet().length == n)) {
        whole[i] = true;
        continue;
      }
      for (final u in us) {
        if (u >= 0 && u < n) (passes[u] ??= <int>[]).add(i);
      }
    }
    special = List<bool>.filled(n, false);
    for (var u = 0; u < n; u++) {
      if (!frame.pose(u).isIdentity) {
        posed.add(u);
        special[u] = true;
      } else if (passes[u] != null) {
        groups.putIfAbsent(passes[u]!.join(','), () => <int>[]).add(u);
        special[u] = true;
      }
    }
  }

  final TextFrame frame;
  final ShapedText shaped;

  /// Per pass: true when it covers every unit.
  late final List<bool> whole;

  /// Per unit: the passes that single it out, or null.
  late final List<List<int>?> passes;

  /// Per unit: drawn somewhere other than the resting paint.
  late final List<bool> special;

  /// Units off their resting pose, in reading order.
  final List<int> posed = [];

  /// Units at rest under passes of their own, keyed by those passes.
  final Map<String, List<int>> groups = {};

  final Map<int, Paint> _paints = {};

  /// The passes that reach unit [u], in the frame's order.
  List<int> passesOf(int u) {
    final own = passes[u];
    return [
      for (var i = 0; i < whole.length; i++)
        if (whole[i] || (own != null && own.contains(i))) i,
    ];
  }

  /// The paint of pass [i], its shader resolved once per frame.
  Paint paintOf(int i) => _paints.putIfAbsent(i, () {
        final pass = frame.ink[i];
        final paint = Paint()..blendMode = pass.blendMode;
        final g = pass.gradient;
        if (g != null) {
          final targets = pass.units ?? [for (final u in shaped.units) u.index];
          paint.shader = g.createShader(
            pass.bounds ?? shaped.boundsOf(targets),
            textDirection: pass.textDirection ?? shaped.direction,
          );
        } else {
          paint.color = pass.color!;
        }
        return paint;
      });
}

void _paintPlan(Canvas canvas, _Plan plan, {Set<int>? only}) {
  final shaped = plan.shaped;
  final frame = plan.frame;

  // 1. The text at rest, with the passes that cover all of it.
  final wholePasses = [
    for (var i = 0; i < plan.whole.length; i++)
      if (plan.whole[i]) i,
  ];
  final restCover = shaped.paintBounds;
  if (wholePasses.isNotEmpty) canvas.saveLayer(restCover, Paint());
  if (only == null) {
    shaped.paintExcept(canvas, plan.special);
  } else {
    shaped.paintUnits(canvas, [
      for (final u in only)
        if (!plan.special[u]) u,
    ]);
  }
  for (final i in wholePasses) {
    canvas.drawRect(restCover, plan.paintOf(i));
  }
  if (wholePasses.isNotEmpty) canvas.restore();

  // 2. Units at rest under passes of their own, one layer per set of passes.
  for (final group in plan.groups.values) {
    final units = only == null
        ? group
        : [
            for (final u in group)
              if (only.contains(u)) u,
          ];
    if (units.isEmpty) continue;
    final cover = shaped.cellsOf(units);
    canvas.saveLayer(cover, Paint());
    shaped.paintUnits(canvas, units);
    for (final i in plan.passesOf(units.first)) {
      canvas.drawRect(cover, plan.paintOf(i));
    }
    canvas.restore();
  }

  // 3. Moving units, each whole, in its own posed layer.
  for (final u in plan.posed) {
    if (only != null && !only.contains(u)) continue;
    final pose = frame.pose(u);
    if (pose.opacity <= 0) continue;
    _paintPosed(canvas, plan, shaped.units[u], pose);
  }
}

void _paintPosed(Canvas canvas, _Plan plan, UnitBox unit, UnitPose pose) {
  final shaped = plan.shaped;
  final cell = shaped.cellOf(unit);
  final paint = Paint()
    ..color = Color.fromRGBO(0, 0, 0, pose.opacity.clamp(0.0, 1.0));
  ui.ImageFilter? filter;
  var reach = cell;
  if (pose.blur > 0) {
    filter = ui.ImageFilter.blur(
      sigmaX: pose.blur,
      sigmaY: pose.blur,
      tileMode: TileMode.decal,
    );
    reach = reach.inflate(pose.blur * 3);
  }
  // Covers the resting glyph (what is drawn) and where the pose takes it.
  var bounds = reach;
  if (pose.moves) {
    final m = poseMatrix(shaped, unit, pose);
    final motion = ui.ImageFilter.matrix(
      m.storage,
      filterQuality: FilterQuality.medium,
    );
    filter = filter == null
        ? motion
        : ui.ImageFilter.compose(outer: motion, inner: filter);
    bounds = bounds.expandToInclude(MatrixUtils.transformRect(m, reach));
  }
  paint.imageFilter = filter;
  canvas.saveLayer(bounds, paint);
  canvas.save();
  canvas.clipRect(cell);
  shaped.classTwin(shaped.classOf(unit.index)).paint(canvas, Offset.zero);
  canvas.restore();
  for (final i in plan.passesOf(unit.index)) {
    canvas.drawRect(cell, plan.paintOf(i));
  }
  canvas.restore();
}

/// The matrix that carries [unit] from its resting place into [pose]: the
/// travel, then the turn, tilt and scale about the pose's pivot. A 3D tilt is
/// seen in perspective from three unit-heights away, so a letter flipping
/// over foreshortens like a card, not a squash.
Matrix4 poseMatrix(ShapedText shaped, UnitBox unit, UnitPose pose) {
  final line = shaped.lineOf(unit);
  final c = unit.rect.center;
  final pivot = switch (pose.pivot) {
    UnitPivot.center => c,
    UnitPivot.baseline => Offset(c.dx, line.baseline),
    UnitPivot.top => Offset(c.dx, unit.rect.top),
    UnitPivot.bottom => Offset(c.dx, unit.rect.bottom),
  };
  final m = Matrix4.translationValues(pivot.dx + pose.dx, pivot.dy + pose.dy, 0);
  if (pose.rotateX != 0 || pose.rotateY != 0) {
    final depth = 3 * math.max(unit.rect.width, line.height);
    m.multiply(Matrix4.identity()..setEntry(3, 2, -1 / depth));
  }
  if (pose.rotation != 0) m.multiply(Matrix4.rotationZ(pose.rotation));
  if (pose.rotateX != 0) m.multiply(Matrix4.rotationX(pose.rotateX));
  if (pose.rotateY != 0) m.multiply(Matrix4.rotationY(pose.rotateY));
  final sx = pose.scale;
  final sy = pose.scale * pose.scaleY;
  if (sx != 1 || sy != 1) m.multiply(Matrix4.diagonal3Values(sx, sy, 1));
  m.multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0));
  return m;
}

/// A [CustomPainter] over a [ShapedText] — the compositor as a painter, for a
/// host that owns its own layout. [KineticText] uses a render object with the
/// same pipeline (plus intrinsics and a baseline); this is for custom hosts.
class KineticPainter extends CustomPainter {
  /// Paint [shaped] under [effects], driven by [progress] and [clock].
  KineticPainter({
    required this.shaped,
    required this.effects,
    required this.progress,
    required this.clock,
    required this.reduced,
  })  : _poses = List.generate(shaped.units.length, (_) => UnitPose()),
        super(repaint: Listenable.merge([progress, clock]));

  /// The shaped paragraph.
  final ShapedText shaped;

  /// Each effect with the slice it acts on.
  final List<(TextEffect, UnitSlice)> effects;

  /// The one-shot progress, 0 → 1.
  final Animation<double> progress;

  /// Seconds since the host mounted.
  final ValueListenable<double> clock;

  /// Reduced motion: one-shots at their end state, motion-only effects skipped.
  final bool reduced;
  final List<UnitPose> _poses;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = composeFrame(
      shaped: shaped,
      effects: effects,
      progress: progress.value,
      time: clock.value,
      reduced: reduced,
      poses: _poses,
    );
    paintFrame(canvas, frame);
  }

  @override
  bool shouldRepaint(KineticPainter oldDelegate) =>
      oldDelegate.shaped != shaped ||
      oldDelegate.progress != progress ||
      oldDelegate.clock != clock ||
      oldDelegate.reduced != reduced ||
      !listEquals(oldDelegate.effects, effects);
}
