# kinetic_text

**Kinetic typography for Flutter** — per-letter, per-word and per-line text
motion from ONE shaped paragraph: staggered reveals, sheen and shimmer sweeps,
gradient and rainbow ink on any span, sparkle, marker highlight, draw-on
underline, typewriter, and a text morph that rewrites a label in place.

- 🪶 **Zero dependencies.** Nothing beyond the Flutter SDK. No shaders to
  ship, no Rive, no Lottie.
- 🔤 **Every script stays joined.** The text is laid out once as a whole, and
  each letter is re-drawn from that one layout. Arabic and Kurdish keep their
  cursive joins, ligatures keep their shape, bidi keeps its order — a
  per-letter effect never splits the string into separate `Text`s.
- 🎯 **Effects compose.** A cascade, a shimmer and a rainbow on the same word
  all write into one pose per letter and paint in one layer. Stagger in
  reading order, reverse, from the centre, from the edges, or scattered.
- ♿ **Reduced motion is a first-class path.** One-shots resolve to their end
  state, loops go quiet, fills and markers stay.
- 📐 **Lays out like `Text`.** Reads the ambient `DefaultTextStyle`,
  `Directionality`, text scale and bold-text setting; wraps to its
  constraints; reports intrinsic sizes and a text baseline (so it sits in a
  baseline-aligned `Row` or an `IntrinsicWidth` like any text); speaks its
  plain text to assistive technology.
- 🧊 **Cheap when still.** A finished reveal is one plain paint. Effects
  compare by value, so a parent rebuild never re-lays the paragraph out.

> By [Armanic Studio](https://pub.dev/publishers/armanic.studio). Sibling of
> [iconic_morph](https://pub.dev/packages/iconic_morph).

## Install

```yaml
dependencies:
  kinetic_text: ^0.1.0
```

```dart
import 'package:kinetic_text/kinetic_text.dart';
```

## Quick start

```dart
// A headline cascading in, word by word.
KineticText(
  'Fresh harvest, every morning',
  style: headline,
  unit: TextUnit.word,
  effects: const [Rise(distance: 10)],
);

// A rainbow on one word, a marker under another — the rest plain.
KineticText.rich([
  const TextRun('Pay '),
  TextRun('12,000 IQD', effects: [Highlight(color: tint), Underline(color: accent)]),
  const TextRun(' before '),
  TextRun('Friday', effects: [GradientInk.rainbow(seed: accent, flow: const Duration(seconds: 4))]),
], style: body);

// A button label that shimmers while a payment clears.
KineticText('Pay now', style: label, effects: const [Shimmer()]);

// A value that rewrites itself — digits roll like an odometer.
TextMorph('$amount IQD', style: figure, morph: const MorphStyle.roll());

// A title that dissolves into the next one under a sheen.
TextMorph(title, style: headline, morph: MorphStyle.sheen(sheen: [accent]));
```

## Effects

| Kind | Effect | What it does |
| --- | --- | --- |
| Reveal | `Rise` | Cascade in from below (or any side), `Rise.fade`, `Rise.pop` |
| Reveal | `Glint` | Grow + fade in under a travelling sheen |
| Reveal | `Blur` | Resolve out of a blur (word/line units) |
| Reveal | `Typewriter` | Hard-cut, one unit at a time, optional blinking cursor |
| Loop | `Shimmer` | A light band sweeps in reading order, letters lift under it |
| Loop | `Sparkle` | A few small glints twinkle on the glyphs |
| Loop | `Float` | A tiny slow drift, each letter a beat behind |
| Ink | `GradientInk` | Gradient fill on a span, `rainbow`, optional flow |
| Ink | `Tint` | Flat recolour of a span, no relayout |
| Decor | `Highlight` | A rounded marker sweeps in behind a span |
| Decor | `Underline` | A stroke draws on under (or `strike` through) a span |

Reveals play over `KineticText.duration` on mount, on a `replayKey` change,
or from a `KineticController`; pass `progress:` to drive them from a scroll
or a parent animation instead. Loops run on their own clock while mounted.

## Morph

`TextMorph` diffs the two texts by unit: the shared prefix and suffix stay
(gliding to their new place when the width changes), the differing middle
leaves and arrives in the chosen style — `sheen`, `slide`, `roll`
(numeric-aware odometer) or `crossfade` — and the box's width eases between
the two.

## Your own effect

```dart
class Wobble extends TextEffect {
  const Wobble();
  @override
  bool get continuous => true;
  @override
  void apply(TextFrame frame, UnitSlice slice) {
    for (var k = 0; k < slice.length; k++) {
      frame.pose(slice.units[k]).dy += 2 * sin(frame.time * 4 + k);
    }
  }
}
```

A `TextFrame` gives you the `ShapedText` (every unit's rect, line and range),
the one-shot `progress`, the loop `time`, and lets you add ink passes and
decor painters behind or over the glyphs.

## Notes on cost

- Shaping happens once per text/style/width — never on a rebuild that only
  constructs a fresh effect list; a frame at rest with no ink pass is one
  plain paint.
- A moving letter is one clipped re-draw of the paragraph; a fading or
  blurred one costs a small layer. Staggers keep the moving set small.
- `Blur` on every letter of a paragraph is a layer per letter — use word or
  line units.
- Horizontal travel suits word units; letters have no slack to slide.

## Names

The effect classes are short on purpose — `Rise`, `Shimmer`, `Blur`, `Float`,
`Tint` — because they read as a list: `effects: const [Rise(), Shimmer()]`.
If another library in your file exports one of these names (`package:shimmer`
has a `Shimmer`), hide it on one side:

```dart
import 'package:kinetic_text/kinetic_text.dart' hide Shimmer;
```

Nothing else in the barrel collides with Flutter's own exports.

## License

MIT — see `LICENSE`.
