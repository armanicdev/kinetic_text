/// Kinetic typography for Flutter — per-letter, per-word and per-line text
/// motion from one shaped paragraph.
///
/// Start with [KineticText] (a label with effects), [TextMorph] (a label
/// that rewrites itself in place) and [TickerText] (a figure whose digits
/// turn like an odometer). Effects: [Rise], [Glint], [Blur],
/// [Typewriter], [Bounce], [Squeeze], [Outline], [Scramble], [Shimmer],
/// [Sparkle], [Float], [Wave], [Pulse], [Spotlight], [Flicker], [GradientInk],
/// [Tint], [Highlight], [Underline]. Build your own on [TextEffect] over a
/// [ShapedText].
library;

export 'src/easing.dart';
export 'src/effect.dart';
export 'src/effects/decor.dart';
export 'src/effects/ink.dart';
export 'src/effects/loops.dart';
export 'src/effects/reveals.dart';
export 'src/frame.dart';
export 'src/kinetic_text_widget.dart';
export 'src/morph.dart';
export 'src/painter.dart';
export 'src/shaped_text.dart';
export 'src/ticker.dart';
