# kinetic_text

**Kinetic typography for Flutter** — per-letter, per-word and per-line text
motion from ONE shaped paragraph: staggered reveals, a rainbow intro, 3D
flips, outline traces, shimmer and spotlight sweeps, neon glow, gradient and
rainbow ink on any span, marker highlight, draw-on underline, typewriter, a
text morph that rewrites a label in place, and a ticker whose digits turn
like an odometer.

- 🪶 **Zero dependencies.** Nothing beyond the Flutter SDK. No shaders to
  ship, no Rive, no Lottie.
- 🔤 **Every script stays joined.** The text is laid out once as a whole, and
  each letter is re-drawn from that one layout. Arabic and Kurdish keep their
  cursive joins, ligatures keep their shape, bidi keeps its order — a
  per-letter effect never splits the string into separate `Text`s.
- ✂️ **Every letter moves whole.** A glyph's ink reaches past its box — the
  tail of a Kurdish `ڕ` and the V under it, an italic `f`, a stacked mark.
  A moving letter carries all of it and leaves nothing behind on its
  neighbours (see [How letters move](#how-letters-move)).
- ↔️ **Reads the way its words do.** A label takes the direction of its own
  text unless told otherwise, and every sweep, marker, trace and cursor
  follows the words it runs over — a Kurdish word in an English line
  shimmers right to left.
- 🎯 **Effects compose.** A cascade, a shimmer and a rainbow on the same word
  all write into one pose per letter. Stagger in reading order, reverse,
  from the centre, from the edges, or scattered.
- ♿ **Reduced motion is a first-class path.** One-shots resolve to their end
  state, loops go quiet, fills, markers and glows stay.
- 📐 **Lays out like `Text`.** Reads the ambient `DefaultTextStyle`, text
  scale and bold-text setting; wraps to its constraints; reports intrinsic
  sizes and a text baseline (so it sits in a baseline-aligned `Row` or an
  `IntrinsicWidth` like any text); speaks its plain text to assistive
  technology.
- 🧊 **Cheap when still.** A finished reveal is one plain paint. Effects
  compare by value, so a parent rebuild never re-lays the paragraph out.

> By [Armanic Studio](https://pub.dev/publishers/armanic.studio). Sibling of
> [iconic_morph](https://pub.dev/packages/iconic_morph).

## Install

```yaml
dependencies:
  kinetic_text: ^1.0.0
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

// The rainbow intro: letters rise in through the spectrum and settle into
// their own ink.
KineticText('Congratulations', style: headline, effects: const [Prism()]);

// A stroke traces each letter in its own colour, then the fill rises.
KineticText('Verified', style: title, effects: const [Outline()]);

// A rainbow on one word, a marker under another — the rest plain.
KineticText.rich([
  const TextRun('Pay '),
  TextRun('12,000', effects: [Highlight(color: tint), Underline(color: accent)]),
  const TextRun(' before '),
  TextRun('Friday', effects: [GradientInk.rainbow(seed: accent, flow: const Duration(seconds: 4))]),
], style: body);

// A button label that shimmers while a payment clears — right to left for a
// Kurdish label, left to right for an English one.
KineticText(label, style: button, effects: const [Shimmer()]);

// Neon.
KineticText('OPEN', style: sign, effects: const [Glow(color: Color(0xFFFF2BD6))]);

// A figure whose digits turn like an odometer — retarget it mid-roll and
// every wheel just redirects.
TickerText(formatted, style: figure);

// A value that rewrites itself — the changed letters roll on the same drum.
TextMorph('$amount', style: figure, morph: const MorphStyle.roll());
```

## Effects

| Kind | Effect | What it does |
| --- | --- | --- |
| Reveal | `Rise` | Cascade in from below (or any side), `Rise.fade`, `Rise.pop` |
| Reveal | `Glint` | Grow + fade in under a travelling sheen, `Glint.rainbow` |
| Reveal | `Prism` | The rainbow intro: rise in washed in the spectrum, settle into own ink |
| Reveal | `Outline` | A stroke traces each letter (in its own ink by default), then the fill rises; `colors`, `Outline.rainbow`, `fill: false` |
| Reveal | `Flip` | Letters flip up in 3D perspective, about the baseline or their middle |
| Reveal | `Tumble` | Letters drop in turned and land upright |
| Reveal | `Wipe` | A soft edge uncovers the text, from any `SweepOrigin` |
| Reveal | `Blur` | Resolve out of a blur (word/line units) |
| Reveal | `Typewriter` | Hard-cut, one unit at a time, optional blinking cursor |
| Reveal | `Bounce` | Drop in from above, land on the baseline with one soft squash |
| Reveal | `Squeeze` | Wide and flat, stretching upright as it lands (a stamp) |
| Reveal | `Scramble` | Random glyphs lock onto the real ones in order (the terminal) |
| Loop | `Shimmer` | A light band sweeps in reading order, letters lift under it; `Shimmer.rainbow` |
| Loop | `Spotlight` | The shimmer's band as light: the line sits dim, letters under it are full ink, optional focus outline |
| Loop | `Glow` | A neon halo from a blurred copy of the ink — still, or breathing |
| Loop | `Sparkle` | A few small glints twinkle on the glyphs |
| Loop | `Float` | A tiny slow drift, each letter a beat behind |
| Loop | `Wave` | A rounded ripple runs through the line |
| Loop | `Sway` | Letters swing on a pin at the top of the line, a beat apart |
| Loop | `Pulse` | A slow glow breathes through the ink, no motion |
| Loop | `Flicker` | One or two letters stutter dark and recover (a loose sign) |
| Ink | `GradientInk` | Gradient fill on a span, `rainbow`, optional flow |
| Ink | `Tint` | Flat recolour of a span, no relayout |
| Decor | `Highlight` | A rounded marker sweeps in behind a span |
| Decor | `Underline` | A stroke draws on under (or `strike` through) a span |

Reveals play over `KineticText.duration` on mount, on a `replayKey` change,
or from a `KineticController`; pass `progress:` to drive them from a scroll
or a parent animation instead. Loops run on their own clock while mounted.

## Direction and alignment

With no `textDirection`, `KineticText` and `TextMorph` lay a text out in its
OWN direction — that of its first letter, the HTML `dir="auto"` rule. An
English label on a Kurdish screen reads left to right with its `!` on the
right; a Kurdish label on an English screen reads right to left and aligns
right. Text with no letter at all (a figure, an emoji) follows the ambient
`Directionality`.

```dart
KineticText('Hello!');                      // LTR, wherever it sits
KineticText('سڵاو!');                        // RTL, wherever it sits
KineticText(label, textDirection: Directionality.of(context)); // follow the page
```

`textAlign` works as on `Text` — `start` and `end` are the start and end of
the text's own direction. `TextMorph` takes `alignment` (wins when set) or
`textAlign`; by default each value holds the start of its own reading
direction while the box eases between widths.

Every sweep reads the words it runs over, not the page: a `Shimmer` band, a
`Spotlight`, a `GradientInk` flow, a `Highlight` or `Underline`, a `Wipe`
and the `Outline` trace start where their slice starts reading. A
`SweepOrigin` turns them:

```dart
Shimmer(origin: SweepOrigin.center)   // two bands, out from the middle
Spotlight(origin: SweepOrigin.edges)  // in from both sides, crossing
Wipe(origin: SweepOrigin.left)        // a physical edge, whatever the text
```

## Morph

`TextMorph` diffs the two texts by unit: the shared prefix and suffix stay
(gliding to their new place when the width changes), the differing middle
leaves and arrives in the chosen style — `sheen`, `slide`, `roll`, `fold`
(split-flap), `wipe` or `crossfade` — and the box's width eases between the
two. `keepShared: false` exchanges everything; `TextMorph.rich` morphs a
line in several styles as one.

`roll` turns the changed letters over a drum: the old glyph curves away
(foreshortening and dimming as it leaves the drum's window), the new one
curves in from the other side on the same clock, up when the number in the
text grew and down when it shrank. Nothing is clipped, and because it works
on the shaped paragraph, it keeps cursive scripts joined.

## Ticker

`TickerText` is the odometer proper — the SwiftUI `numericText` feel. Each
character sits in a slot keyed from the right (or `TickerAnchor.left` for a
label) and owns a **continuous wheel** that chases its target every frame,
not a 0→1 timeline that restarts on each change. Set a new value mid-roll
and every wheel redirects from where it is; a digit that has to go from 2 to
7 passes 3, 4, 5 and 6 on the way, the shorter way round the ring. Western
(`0–9`), Arabic-Indic (`٠–٩`) and Persian (`۰–۹`) digits each turn on their
own ring. The width eases as characters come and go; new slots fade in,
dropped slots fade out. Pass a formatted string and a tabular-figure style:

```dart
TickerText('1,250,000', style: figure.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
```

Characters are laid out one per slot, so use it for figures and Latin
labels; for cursive words reach for `TextMorph` with `MorphStyle.roll`,
which turns the same drum from one shaped paragraph.

## How letters move

A letter's ink does not stop at its box. Cut a moving letter out along its
box and its tail stays behind on the next letter while the letter itself
flies off clipped. So `ShapedText` builds **class twins**: the same
paragraph laid out again with the same metrics, in which only one class of
units keeps its ink and every other code unit is transparent. Units of one
class are never near each other, so clipping a class twin to a generous cell
(the unit's box plus `ShapedText.overhang` of a line on every side) yields
exactly that letter — tails and marks included, none of its neighbours'.
The twins stack back into the original pixel for pixel.

A moving letter is drawn at rest into a layer whose matrix image filter
carries its pose (the trick behind `Transform.filterQuality`), so a 1 px
drift or a 0.92 → 1 grow glides at any fraction of a pixel. Settled text is
crisp vector text.

## Your own effect

```dart
class Wobble extends TextEffect {
  const Wobble();
  @override
  bool get continuous => true;
  @override
  void apply(TextFrame frame, UnitSlice slice) {
    for (var k = 0; k < slice.length; k++) {
      frame.pose(slice.units[k])
        ..rotation += 0.05 * sin(frame.time * 4 + k)
        ..pivot = UnitPivot.baseline;
    }
  }
}
```

A `TextFrame` gives you the `ShapedText` (every unit's rect, line, range and
reading direction), the one-shot `progress`, the loop `time`, a pose per unit
(`dx`, `dy`, `scale`, `scaleY`, `rotation`, `rotateX`, `rotateY`, `opacity`,
`blur`, `pivot`), and lets you add ink passes and decor painters behind or
over the glyphs. `frame.directionOf(slice)` tells you which way your slice
reads.

## Notes on cost

- Shaping happens once per text/style/width — never on a rebuild that only
  constructs a fresh effect list; a frame at rest with no ink pass is one
  plain paint.
- The class twins (a handful per text — about four on a line of letters) are
  laid out once, the first time something moves, and cached with the shaped
  text. While anything moves, the resting text is one clipped paint per
  class and each moving letter one small layer.
- `Blur` on every letter of a paragraph is a layer per letter — use word or
  line units.
- `Spotlight`, `Wipe` and `Pulse` are one ink pass per frame and no layer
  per letter; `Glow` is one blurred layer.
- `Outline` lays the paragraph out again with a stroked ink — once per class,
  cached. `Scramble` sets its stand-in glyphs one at a time, so keep it to
  Latin text and figures.
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

MIT — see `LICENSE`. The Leraw font the tests shape Kurdish with is under the
SIL Open Font License (`test/fonts/OFL-Leraw.txt`).
