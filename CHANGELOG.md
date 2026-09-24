# Changelog

## 0.3.0

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
