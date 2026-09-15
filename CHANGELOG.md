# Changelog

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
