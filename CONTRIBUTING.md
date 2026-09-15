# Contributing to kinetic_text

## The bar

Every effect is drawn from ONE shaped paragraph. A change that lays out a
substring as its own `Text` or `TextPainter` — however convenient — breaks
cursive joins in Arabic, Kurdish, Persian and Urdu, and will not be merged.
The rule of the engine: shape once, then re-draw clusters of that one layout
clipped to their cells.

Effects are immutable and compare by value. A new effect needs `==` and
`hashCode` over every field, or a parent rebuild will re-shape the text for
no reason. The test in `test/effect_test.dart` ("effects compare by value")
is where it gets asserted.

## Setup

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
```

`flutter test` must stay green on the floor Flutter in `pubspec.yaml` as well
as on stable; CI runs both.

## Adding an effect

1. Extend `TextEffect` (or `StaggeredEffect` for a one-shot reveal).
2. Read `TextFrame.progress` for a one-shot, `TextFrame.time` for a loop —
   and report `continuous => true` for a loop, so the host keeps a clock.
3. Decide `motionOnly`: a fill or a marker is not motion and should survive
   reduced motion; anything that moves should not.
4. Write poses (`frame.pose(i)`), ink passes (`frame.ink`) or decor
   (`frame.behind` / `frame.over`). Never paint glyphs yourself.
5. Add `==` / `hashCode`, a doc comment with the tuned defaults, a CHANGELOG
   line and a test.

## Reporting a bug

A minimal `KineticText` (text, style, effects, direction) and what you saw.
RTL and mixed-script reports are especially welcome — include the exact
string.
