import 'package:flutter/widgets.dart';
import 'package:kinetic_text/kinetic_text.dart';

void main() => runApp(const Example());

class Example extends StatefulWidget {
  const Example({super.key});

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  int _amount = 12000;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF006DFD);
    const gap = SizedBox(height: 18);
    return WidgetsApp(
      color: accent,
      builder: (context, _) => DefaultTextStyle(
        style: const TextStyle(fontSize: 22, color: Color(0xFF111111)),
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Tap anywhere to replay the reveals and turn the figures.
              onTap: () => setState(() {
                _replay++;
                _amount += 2500;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KineticText(
                    'Fresh harvest, every morning',
                    unit: TextUnit.word,
                    replayKey: _replay,
                    effects: const [Rise(distance: 10)],
                  ),
                  gap,
                  // The rainbow intro: every hue on the way in, own ink at rest.
                  KineticText(
                    'Congratulations!',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                    replayKey: _replay,
                    duration: const Duration(milliseconds: 1400),
                    effects: const [Prism()],
                  ),
                  gap,
                  // Traced in its own ink, then filled.
                  KineticText(
                    'Verified',
                    style: const TextStyle(fontSize: 30, color: accent),
                    replayKey: _replay,
                    duration: const Duration(milliseconds: 1400),
                    effects: const [Outline(width: 1.4)],
                  ),
                  gap,
                  // Reads right to left on its own, and shimmers that way.
                  const KineticText(
                    'پشتڕاستکراوەتەوە',
                    effects: [Tint(accent), Shimmer(color: Color(0xFF9FE8FF), intensity: 0.9)],
                  ),
                  gap,
                  KineticText.rich([
                    const TextRun('Pay before '),
                    TextRun('Friday', effects: [
                      GradientInk.rainbow(seed: accent, flow: const Duration(seconds: 4)),
                    ]),
                  ]),
                  gap,
                  const ColoredBox(
                    color: Color(0xFF0B0B14),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: KineticText(
                        'OPEN LATE',
                        style: TextStyle(fontSize: 26, color: Color(0xFFFFE6FA)),
                        effects: [Glow(color: Color(0xFFFF2BD6), period: Duration(seconds: 2))],
                      ),
                    ),
                  ),
                  gap,
                  TextMorph('$_amount', morph: const MorphStyle.roll()),
                  gap,
                  TickerText('$_amount'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
