import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

class _RecordingSheen extends SheenMorph {
  _RecordingSheen(TextDirection direction)
      : super(sweepDirection: direction, exitEnd: 0.5, enterStart: 0.5);

  final entrances = <double>[];
  final departures = <double>[];

  @override
  void enter(UnitPose pose, double e, double lineHeight, bool up) {
    entrances.add(e);
    super.enter(pose, e, lineHeight, up);
  }

  @override
  void exit(UnitPose pose, double e, double lineHeight, bool up) {
    departures.add(e);
    super.exit(pose, e, lineHeight, up);
  }
}

Widget _host(String text, MorphStyle morph) => Directionality(
  textDirection: TextDirection.rtl,
  child: Center(child: TextMorph(
    text,
    style: const TextStyle(fontSize: 24, color: Color(0xFF000000)),
    keepShared: false,
    morph: morph,
    duration: const Duration(seconds: 1),
  )),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('physical $direction sweep over mixed-script units', (tester) async {
      final style = _RecordingSheen(direction);
      await tester.pumpWidget(_host('Previous title', style));
      await tester.pumpWidget(_host('ABC ابج 123', style));
      await tester.pump(const Duration(milliseconds: 250));
      // No incoming ink while the outgoing title is still leaving.
      expect(style.entrances, everyElement(0.0));
      style.entrances.clear();
      style.departures.clear();
      await tester.pump(const Duration(milliseconds: 450));
      final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(TextMorph), matching: find.byType(CustomPaint),
      ));
      final dynamic painter = paint.painter;
      final ShapedText shaped = painter.to;
      style.entrances.clear();
      style.departures.clear();
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), tester.getSize(find.byWidget(paint)));
      recorder.endRecording().dispose();
      // At 70%, the outgoing run is fully gone; the incoming wave follows
      // physical glyph positions even where bidi reverses logical indices.
      expect(style.departures, everyElement(1.0));
      final visual = List<int>.generate(shaped.units.length, (i) => i)
        ..sort((a, b) => shaped.units[a].rect.center.dx.compareTo(
          shaped.units[b].rect.center.dx,
        ));
      final progress = [for (final i in visual) style.entrances[i]];
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], direction == TextDirection.ltr
            ? lessThanOrEqualTo(progress[i - 1])
            : greaterThanOrEqualTo(progress[i - 1]));
      }
      final MorphDiff diff = painter.diff;
      expect(diff.prefix, 0);
      expect(diff.suffix, 0);
      await tester.pumpAndSettle();
    });
  }
}
