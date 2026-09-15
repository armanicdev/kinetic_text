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

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF006DFD);
    return WidgetsApp(
      color: accent,
      builder: (context, _) => DefaultTextStyle(
        style: const TextStyle(fontSize: 22, color: Color(0xFF111111)),
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const KineticText(
                  'Fresh harvest, every morning',
                  unit: TextUnit.word,
                  effects: [Rise(distance: 10)],
                ),
                const SizedBox(height: 16),
                KineticText.rich([
                  const TextRun('Pay before '),
                  TextRun('Friday', effects: [
                    GradientInk.rainbow(seed: accent, flow: const Duration(seconds: 4)),
                  ]),
                ]),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _amount += 2500),
                  child: TextMorph('$_amount', morph: const MorphStyle.roll()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
