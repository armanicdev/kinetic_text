import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'effect.dart';
import 'frame.dart';
import 'shaped_text.dart';

/// How far a pose can push ink outside its resting cell — what a layer must
/// cover so nothing is hard-cut.
double _reachOf(UnitPose pose, Rect cell) =>
    (pose.scale - 1).abs() * cell.longestSide + pose.blur * 3;

/// Paints one unit of a [ShapedText] in a [UnitPose]: the whole painter is
/// drawn under a transform about the unit's centre and clipped to the unit's
/// cell — so a scaled letter grows into its side-bearings, a risen letter
/// carries its clip with it, and the rest of the text is never touched.
///
/// [clipToBand] keeps the clip at the RESTING cell instead (the odometer
/// look: a rolling digit slides out through the line's edge).
void paintUnit(
  Canvas canvas,
  ShapedText shaped,
  UnitBox unit,
  UnitPose pose, {
  bool clipToBand = false,
  Offset origin = Offset.zero,
}) {
  final cell = shaped.cellOf(unit);
  final needsLayer = pose.opacity < 1 || pose.blur > 0;
  final cx = unit.rect.center.dx;
  final cy = unit.rect.center.dy;
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  if (clipToBand) canvas.clipRect(cell);
  if (needsLayer) {
    final bounds =
        cell.shift(Offset(pose.dx, pose.dy)).inflate(_reachOf(pose, cell));
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, pose.opacity.clamp(0.0, 1.0));
    if (pose.blur > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: pose.blur,
        sigmaY: pose.blur,
        tileMode: TileMode.decal,
      );
    }
    canvas.saveLayer(bounds, paint);
  }
  canvas.translate(pose.dx, pose.dy);
  if (pose.scale != 1) {
    canvas.translate(cx, cy);
    canvas.scale(pose.scale);
    canvas.translate(-cx, -cy);
  }
  if (!clipToBand) canvas.clipRect(cell);
  shaped.painter.paint(canvas, Offset.zero);
  if (needsLayer) canvas.restore();
  canvas.restore();
}

/// Paint every unit that is at rest — and every whitespace between them — in
/// ONE draw, with the moved units' cells cut out of the clip. Each cell is a
/// DIFFERENCE clip, never a hole in an even-odd path: two adjacent cells that
/// overlap by a kerned hair would otherwise cancel each other out and let a
/// sliver of resting ink show through under a moving letter.
void paintResting(
  Canvas canvas,
  ShapedText shaped,
  Iterable<UnitBox> moved, {
  Offset origin = Offset.zero,
}) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  for (final u in moved) {
    canvas.clipRect(shaped.cellOf(u), clipOp: ui.ClipOp.difference);
  }
  shaped.painter.paint(canvas, Offset.zero);
  canvas.restore();
}

/// Draw one ink pass over the glyph layer: per unit, under that unit's own
/// pose transform, so a recolour follows a moving letter. When none of the
/// targeted units is posed the pass is ONE draw through one clip.
void paintInk(
  Canvas canvas,
  TextFrame frame,
  InkPass pass, {
  Offset origin = Offset.zero,
}) {
  final shaped = frame.shaped;
  final units = pass.units;
  final targets = units ?? [for (final u in shaped.units) u.index];
  if (targets.isEmpty) return;
  final bounds = pass.bounds ?? shaped.boundsOf(targets);
  final paint = Paint()..blendMode = pass.blendMode;
  final g = pass.gradient;
  if (g != null) {
    paint.shader = g.createShader(bounds, textDirection: shaped.direction);
  } else {
    paint.color = pass.color!;
  }
  var anyPosed = false;
  for (final i in targets) {
    if (!frame.pose(i).isIdentity) {
      anyPosed = true;
      break;
    }
  }
  if (!anyPosed) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    if (units == null) {
      // The whole text: one rect over everything.
      canvas.drawRect(shaped.paintBounds, paint);
    } else {
      // A slice at rest: one clip made of its cells, one rect.
      final cells = Path();
      Rect? cover;
      for (final i in targets) {
        final cell = shaped.cellOf(shaped.units[i]);
        cells.addRect(cell);
        cover = cover == null ? cell : cover.expandToInclude(cell);
      }
      canvas.clipPath(cells);
      canvas.drawRect(cover!, paint);
    }
    canvas.restore();
    return;
  }
  for (final i in targets) {
    final u = shaped.units[i];
    final pose = frame.pose(i);
    final cell = shaped.cellOf(u);
    final cx = u.rect.center.dx;
    final cy = u.rect.center.dy;
    canvas.save();
    canvas.translate(origin.dx + pose.dx, origin.dy + pose.dy);
    if (pose.scale != 1) {
      canvas.translate(cx, cy);
      canvas.scale(pose.scale);
      canvas.translate(-cx, -cy);
    }
    canvas.clipRect(cell);
    canvas.drawRect(cell, paint);
    canvas.restore();
  }
}

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

/// Paint a composed [frame]: decor behind, the glyph layer, decor over.
void paintFrame(Canvas canvas, TextFrame frame, {Offset origin = Offset.zero}) {
  for (final d in frame.behind) {
    d(canvas, frame);
  }
  paintGlyphs(canvas, frame, origin: origin);
  for (final d in frame.over) {
    d(canvas, frame);
  }
}

/// The glyph layer for [frame]: resting units in one draw, moved units one by
/// one, then the ink passes — all inside one layer so the ink blends only with
/// glyph pixels. The layer is a single `saveLayer` only when something is posed
/// or recoloured; a text at rest with no ink pass is one plain paint, so a
/// finished reveal costs nothing more than a [Text].
void paintGlyphs(Canvas canvas, TextFrame frame, {Offset origin = Offset.zero}) {
  final shaped = frame.shaped;
  if (!frame.anyPosed && frame.ink.isEmpty) {
    shaped.painter.paint(canvas, origin);
    return;
  }
  final moved = <UnitBox>[];
  // The layer covers the paragraph plus wherever this frame's poses reach, so
  // a long rise or a wide blur is never hard-cut at the layer's edge.
  var bounds = shaped.paintBounds;
  for (final u in shaped.units) {
    final pose = frame.pose(u.index);
    if (pose.isIdentity) continue;
    moved.add(u);
    final cell = shaped.cellOf(u);
    bounds = bounds.expandToInclude(
      cell.shift(Offset(pose.dx, pose.dy)).inflate(_reachOf(pose, cell)),
    );
  }
  canvas.saveLayer(bounds.shift(origin), Paint());
  paintResting(canvas, shaped, moved, origin: origin);
  for (final u in moved) {
    final pose = frame.pose(u.index);
    if (pose.opacity <= 0) continue;
    paintUnit(canvas, shaped, u, pose, origin: origin);
  }
  for (final pass in frame.ink) {
    paintInk(canvas, frame, pass, origin: origin);
  }
  canvas.restore();
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
  bool shouldRepaint(KineticPainter old) =>
      old.shaped != shaped ||
      old.progress != progress ||
      old.clock != clock ||
      old.reduced != reduced ||
      !listEquals(old.effects, effects);
}
