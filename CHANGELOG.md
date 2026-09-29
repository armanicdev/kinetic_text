# Changelog

## 1.0.0

The engine is finished: every letter moves whole, every sweep reads the way
its words do, and ten new effects.

### Every letter moves whole

- **Glyph-exact units.** A glyph's ink does not stop at its box: the tail of a
  Kurdish `ڕ` and the V under it, an italic overhang, a stacked mark all reach
  into the next letter's box or below the line. Units used to be cut out along
  their boxes, so a moving letter lost those parts and left them behind on its
  neighbour (the shimmer artefact on `ڕ`). Now every unit is drawn from a
  *class twin* — the same paragraph laid out again with only one class of
  units inked — clipped to a generous cell, so a moving letter carries all of
  its ink and leaves none behind. The twins stack back into the original
  pixel for pixel; they are built lazily, the first time something moves, and
  a text at rest is still one plain paint.
- **Ink passes are exact too.** A tint, a sheen or a mask applies inside each
  moving letter's own layer, and over exactly the glyphs of its slice.
- **Ligatures are one unit.** Characters the font sets as one glyph (`fi`, a
  lam-alef) move together instead of each carrying half a glyph.
- Underlines and span backgrounds stay on the line under moving letters,
  drawn once and exactly; an ellipsis survives while a letter moves.

### Direction and alignment from the text itself

- **`KineticText` and `TextMorph` read in the text's own direction.** With no
  `textDirection` given, a paragraph takes the direction of its first letter
  (the HTML `dir="auto"` rule): an English label on a Kurdish page reads left
  to right, its `!` on the right; a Kurdish label on an English page right to
  left, aligned right. Text with no letter (a figure) follows the ambient
  `Directionality`. Pass `textDirection` to pin a label to the page.
- **Every sweep follows the words it runs over.** `Shimmer`, `Spotlight`,
  `GradientInk` (and its flow), `Highlight`, `Underline`, `Wipe`, `Sway`, the
  `Typewriter` cursor and the `Outline` trace take their direction from their
  own slice: a Kurdish word inside an English line shimmers right to left.
- **`SweepOrigin`** — `reading` (the default), `end`, `left`, `right`,
  `center` (out from the middle, two bands) and `edges` (in from both sides)
  — on `Shimmer`, `Spotlight` and `Wipe`.
- **`TextMorph.textAlign`.** `alignment` is now optional: when set it wins;
  otherwise `textAlign` (or the ambient `DefaultTextStyle.textAlign`) places
  each text — start by default, the start of that text's own direction.
- `ShapedText.directionOf`, `ShapedText.readingDirectionOf`,
  `TextFrame.directionOf` / `readsRtl`, `InkPass.textDirection`.

### Better motion

- **`Outline` traces in the text's own colour by default.** `color` is now
  optional; `colors` runs the rings through a gradient along the reading
  order, `Outline.rainbow()` through every hue; `fill: false` leaves the text
  outlined. The trace turns clockwise for a left-to-right letter and
  anticlockwise for a right-to-left one.
- `Shimmer` lifts its letters from the baseline instead of swelling them
  about their middle; `Bounce` and `Squeeze` land on the baseline.
- Poses gained `rotation`, `rotateX` and `rotateY` (a 3D tilt seen in
  perspective) and a `pivot` (`UnitPivot.center`, `baseline`, `top`,
  `bottom`); `poseMatrix` exposes the transform.
- `TickerText` resamples a turning glyph through a matrix filter (smooth at
  any fraction of a pixel, like every other moving glyph), never clips a
  glyph to its slot, and turns Arabic-Indic (`٠–٩`) and Persian (`۰–۹`)
  digits on their own rings.

### New effects

- **`Prism`** — the rainbow intro: letters rise in washed in the spectrum and
  settle into their own ink.
- **`Wipe`** — a soft edge uncovers the text, from any `SweepOrigin`.
- **`Flip`** — letters flip up in 3D perspective, about the baseline or about
  their middle.
- **`Tumble`** — letters drop in turned and land upright.
- **`Glow`** — a neon halo from a blurred copy of the ink; follows moving
  letters and any ink pass; still or breathing.
- **`Sway`** — letters swing on a pin, a beat apart.
- `Shimmer.rainbow`, `Glint.rainbow`, `Outline.rainbow`, and
  `rainbowColors` / `colorAround` for your own.
- `paintGlyphsOf` — draw a subset of a frame's letters, posed and inked (what
  `Glow` blurs).

### Breaking

- `paintUnit`, `paintResting` and `paintInk` are gone; `paintFrame`,
  `paintGlyphs` and `paintGlyphsOf` draw frames, and `ShapedText.paintUnits`
  / `paintExcept` draw units exactly.
- `ShapedText.cellOf` now includes the overhang margin (`ShapedText.overhang`
  of a line height on every side).
- `paintFrame` translates its decor by `origin` as well as its glyphs.
- The default direction change above: pass `textDirection:
  Directionality.of(context)` where a label must follow the page.

## 0.3.0

- **New: `TextMorph.keepShared`.** True by default, as before: the letters the
  two texts share at their start and end stay put. Set it false to exchange
  every unit, so the old value leaves whole and the new one arrives whole; with
  `unit: TextUnit.word` a value swaps word by word, no letter left standing
  because it happened to match.
- **New: `TextMorph.rich`.** One line in several styles, a name in full ink
  and a code after it in a quieter one, morphed as one: each unit keeps its
  span's style while it moves, and the diff reads the plain text. A new style
  on the same words restyles in place without an exchange.

- **`TextMorph` holds its leading edge.** `alignment` now defaults to
  `AlignmentDirectional.centerStart` (was `Alignment.center`). Centred, each
  text rode the middle of a box whose width was easing between the two
  values, so a word sliding up or down also drifted sideways; pinned to the
  start it moves only on the morph's own axis, in LTR and RTL. Pass
  `alignment: Alignment.center` to keep a centred label centred.

## 0.2.0

- **New: `TickerText`** — an odometer figure. One continuous wheel per
  character slot, chasing its target with frame-rate-independent exponential
  smoothing; retarget mid-roll and the wheels redirect without a reset.
  Digits take the shorter way round the 0–9 ring, other characters turn one
  step; eased width, per-slot fade for characters that come and go, a text
  baseline, reduced-motion snap, `TickerAnchor` (right for figures, left for
  labels) and `RollDirection` (auto from the number in the text, up, down).
- **`MorphStyle.roll` rebuilt on the same drum.** The leaving and arriving
  glyphs turn over a cylinder on one clock — foreshortened and dimmed by their
  angle, fully off past the drum's window — instead of sliding under a band
  clip that left a sliver of the old glyph showing. New `KineticEase.chase`
  (the ticker's exponential settle). The `travel` parameter is gone.
- **Moving letters are resampled, not re-placed.** A posed unit is drawn at
  rest into a layer whose matrix image filter carries the pose (the trick
  behind `Transform.filterQuality`), so a 1 px drift or a 0.92→1 grow is
  smooth at any fraction of a pixel. Under a raw canvas transform Impeller
  snapped glyph y to whole pixels and re-rasterized the atlas at each scale,
  which made a slow `Float` or `Glint` step pixel by pixel. Settled text is
  still crisp vector text.
- **Ten more effects.** Reveals `Bounce`, `Squeeze`, `Outline` (a stroke
  sweeps round each letter from a stroked twin of the same paragraph, then
  the fill rises), `Scramble`; loops `Wave`, `Pulse`, `Spotlight` (the
  shimmer's band as an alpha mask in one ink pass, the line held at `dim`,
  an optional `focus` outline under the band),
  `Flicker`; morph styles `fold` (split-flap) and `wipe`.
- `ShapedText.strokedTwin` — the same layout with a stroked ink, cached.
- `UnitPose.scaleY` — a vertical squash effects can compose with `scale`.
- `MorphStyle.exitEnd` / `enterStart` — where each leg of a morph runs; the
  band-clip hook (`clipToBand`) is removed.

## 0.1.0

First release.

- `KineticText` — text shaped once, animated per grapheme, word or line. Rich
  runs (`KineticText.rich`) scope effects to one span.
- Reveals: `Rise` (cascade, fade, pop), `Glint` (sheen draw-on), `Blur`,
  `Typewriter` (with a blinking cursor).
- Loops: `Shimmer` (sheen sweep with a letter pop, reading-order aware for
  RTL), `Sparkle`, `Float`.
- Ink: `GradientInk` (incl. `rainbow`, static or flowing), `Tint`.
- Decor: `Highlight` (marker sweep), `Underline` and `Underline.strike`
  (draw-on).
- `TextMorph` — a label that rewrites itself in place; shared letters stay,
  changed letters exchange in `sheen`, `slide`, `roll` (odometer) or
  `crossfade` style; the width eases underneath.
- `KineticController`, external `progress`, `replayKey`, a cancellable
  `delay`, reduced-motion handling, stagger orders (`reading`, `reverse`,
  `center`, `edges`, `scatter`).
- Lays out like `Text`: a render object with intrinsic sizes, a text
  baseline, `textAlign` / `maxLines` / `overflow` / `locale` /
  `strutStyle` / `textHeightBehavior`, the ambient `DefaultTextStyle` and
  bold-text accessibility setting.
- Effects and morph styles compare by value; a rebuild never re-shapes.
- `ShapedText`, `TextFrame`, `TextEffect` — the engine is open for your own
  effects.
