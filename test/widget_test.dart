import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

Widget host(Widget child, {bool reduce = false, TextDirection dir = TextDirection.ltr}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: dir,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
          child: Center(child: child),
        ),
      ),
    );

void main() {
  _tickerTests();
  testWidgets('a reveal plays to the end and reports it', (tester) async {
    var ended = 0;
    await tester.pumpWidget(host(KineticText(
      'Hello world',
      unit: TextUnit.word,
      effects: const [Rise(), Glint(sheen: [Color(0xFFFFFFFF)])],
      duration: const Duration(milliseconds: 400),
      onEnd: () => ended++,
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ended, 1);
    expect(tester.binding.transientCallbackCount, 0, reason: 'no loop → no clock');
  });

  testWidgets('a loop keeps a clock and disposes cleanly', (tester) async {
    await tester.pumpWidget(host(const KineticText(
      'Pay now',
      effects: [Shimmer(), Sparkle(color: Color(0xFF00FF00))],
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(const SizedBox()));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion: end state at once, loops silent, ink kept', (tester) async {
    final controller = KineticController();
    await tester.pumpWidget(host(
      KineticText.rich([
        const TextRun('Fresh '),
        TextRun('harvest', effects: [GradientInk.rainbow(), const Sparkle(color: Color(0xFFFFFFFF))]),
      ], effects: const [Rise(), Shimmer()], controller: controller),
      reduce: true,
    ));
    await tester.pump();
    expect(controller.progress!.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich runs, highlight, underline and typewriter paint', (tester) async {
    await tester.pumpWidget(host(KineticText.rich(
      [
        const TextRun('Pay '),
        TextRun('12,000', effects: const [
          Highlight(color: Color(0x3300FF00)),
          Underline(color: Color(0xFF0000FF)),
        ]),
      ],
      effects: const [Typewriter(cursor: Color(0xFF000000)), Blur(sigma: 4)],
      unit: TextUnit.grapheme,
      duration: const Duration(milliseconds: 300),
    )));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('semantics speaks the plain text', (tester) async {
    await tester.pumpWidget(host(const KineticText.rich([TextRun('Hel'), TextRun('lo')])));
    expect(find.bySemanticsLabel('Hello'), findsOneWidget);
  });

  testWidgets('a replay key replays and a controller drives', (tester) async {
    final c = KineticController();
    var ends = 0;
    Widget build(int key) => host(KineticText('abc',
        effects: const [Rise()],
        replayKey: key,
        controller: c,
        duration: const Duration(milliseconds: 100),
        onEnd: () => ends++));
    await tester.pumpWidget(build(0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(ends, 1);
    await tester.pumpWidget(build(1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(ends, 2);
    c.replay();
    await tester.pump(); // the ticker's first frame
    await tester.pump(const Duration(milliseconds: 150));
    expect(ends, 3);
  });

  testWidgets('morph: every style flies without error and lands on the new text',
      (tester) async {
    for (final style in const [
      MorphStyle.sheen(),
      MorphStyle.slide(),
      MorphStyle.roll(),
      MorphStyle.crossfade(),
    ]) {
      Widget build(String t) => host(TextMorph(t, morph: style, duration: const Duration(milliseconds: 200)));
      await tester.pumpWidget(build('12,000'));
      await tester.pumpWidget(build('120,500'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$style');
      await tester.pump(const Duration(milliseconds: 60));
      // Interrupt mid-flight.
      await tester.pumpWidget(build('Winter Sale'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull, reason: '$style');
      expect(find.bySemanticsLabel('Winter Sale'), findsOneWidget);
    }
  });

  testWidgets('RTL text shapes and reveals', (tester) async {
    await tester.pumpWidget(host(
      const KineticText('وەسڵی کارەبا', effects: [Rise(), Shimmer()]),
      dir: TextDirection.rtl,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('a parent rebuild with fresh effects does not re-shape', (tester) async {
    const accent = Color(0xFF006DFD);
    Widget build(int tick) => host(KineticText(
          'Fresh harvest',
          // Non-const on purpose: a new instance every build.
          effects: [Glint(sheen: [accent]), GradientInk.rainbow(seed: accent)],
          replayKey: 0,
        ));
    await tester.pumpWidget(build(0));
    await tester.pump(const Duration(milliseconds: 100));
    final shaped = ShapedText.debugShapeCount;
    await tester.pumpWidget(build(1));
    await tester.pumpWidget(build(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ShapedText.debugShapeCount, shaped, reason: 'same text, same style: no relayout');
    // A style change IS a re-shape.
    await tester.pumpWidget(host(const KineticText('Fresh harvest', style: TextStyle(fontSize: 30))));
    expect(ShapedText.debugShapeCount, shaped + 1);
  });

  testWidgets('a delayed autoplay is cancelled on early unmount', (tester) async {
    await tester.pumpWidget(host(const KineticText(
      'Later',
      effects: [Rise()],
      delay: Duration(seconds: 5),
    )));
    await tester.pump();
    // Unmount while the delay timer is still armed; flutter_test fails the
    // test at teardown if a Timer leaks.
    await tester.pumpWidget(host(const SizedBox()));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('lays out like Text: baseline, intrinsics, ellipsis', (tester) async {
    const style = TextStyle(fontSize: 24, color: Color(0xFF000000));
    await tester.pumpWidget(host(Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: const [
        Text('Pay', style: style),
        SizedBox(width: 8),
        KineticText('12,000', style: TextStyle(fontSize: 40, color: Color(0xFF000000))),
      ],
    )));
    final plain = tester.getRect(find.text('Pay'));
    final kinetic = tester.getRect(find.byType(KineticText));
    expect(kinetic.height, greaterThan(plain.height));
    double baselineOf(String t, TextStyle s) {
      final p = TextPainter(
        text: TextSpan(text: t, style: s),
        textDirection: TextDirection.ltr,
      )..layout();
      final b = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      p.dispose();
      return b;
    }

    expect(
      kinetic.top + baselineOf('12,000', const TextStyle(fontSize: 40)),
      closeTo(plain.top + baselineOf('Pay', style), 0.5),
      reason: 'baselines meet',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(IntrinsicWidth(
      child: Column(
        children: const [KineticText('an intrinsic width', style: style), Text('x')],
      ),
    )));
    expect(tester.takeException(), isNull, reason: 'a render object with intrinsics');

    await tester.pumpWidget(host(const SizedBox(
      width: 60,
      child: KineticText(
        'far too long for sixty pixels',
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    )));
    expect(tester.getSize(find.byType(KineticText)).width, lessThanOrEqualTo(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ink pass at rest and a posed one both paint', (tester) async {
    await tester.pumpWidget(host(KineticText.rich(
      [
        const TextRun('flat ', effects: [Tint(Color(0xFFFF0000))]),
        TextRun('lit', effects: const [Shimmer(period: Duration(milliseconds: 200), rest: 0)]),
      ],
      effects: const [Rise()],
      duration: const Duration(milliseconds: 100),
    )));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(host(const SizedBox()));
  });
}

void _tickerTests() {
  testWidgets('a ticker turns, settles and lets go of its clock', (tester) async {
    await tester.pumpWidget(host(const TickerText('1,999')));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0, reason: 'at rest: no clock');
    final rest = tester.getSize(find.byType(TickerText));
    expect(rest.width, greaterThan(0));

    await tester.pumpWidget(host(const TickerText('12,000')));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'rolling');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final mid = tester.getSize(find.byType(TickerText));
    expect(mid.width, greaterThan(rest.width), reason: 'the field is widening');

    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0, reason: 'settled: clock released');
    expect(tester.getSemantics(find.byType(TickerText)).label, '12,000');

    await tester.pumpWidget(host(const TickerText('Sold out', anchor: TickerAnchor.left)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ticker sits on the text baseline and snaps under reduced motion',
      (tester) async {
    await tester.pumpWidget(host(
      const Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [TickerText('250'), Text('kg')],
      ),
      reduce: true,
    ));
    await tester.pump();
    final ticker = tester.getRect(find.byType(TickerText));
    final label = tester.getRect(find.text('kg'));
    expect(ticker.bottom, moreOrLessEquals(label.bottom, epsilon: 0.5),
        reason: 'same style, same line: the baselines agree');

    await tester.pumpWidget(host(
      const Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [TickerText('1,000'), Text('kg')],
      ),
      reduce: true,
    ));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0, reason: 'reduced motion: snapped');
  });
}
