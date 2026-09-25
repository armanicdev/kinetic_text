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
  _newEffectTests();
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
      MorphStyle.fold(),
      MorphStyle.wipe(),
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

  testWidgets('morph: a label holds its leading edge while the width moves',
      (tester) async {
    // Centred by default, a word sliding up drifted sideways as the box eased
    // from one width to the other; the default is now the start edge, in
    // either direction.
    for (final dir in TextDirection.values) {
      await tester.pumpWidget(host(const TextMorph('Madyas',
        morph: MorphStyle.slide(), duration: Duration(milliseconds: 200)), dir: dir));
      await tester.pumpWidget(host(const TextMorph('Bookings',
        morph: MorphStyle.slide(), duration: Duration(milliseconds: 200)), dir: dir));
      await tester.pump(const Duration(milliseconds: 80));
      final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(TextMorph), matching: find.byType(CustomPaint)));
      final Alignment align = (paint.painter as dynamic).align;
      expect(align.x, dir == TextDirection.ltr ? -1 : 1, reason: '$dir');
      await tester.pump(const Duration(milliseconds: 200));
    }
  });

  testWidgets('morph: keepShared false exchanges every unit', (tester) async {
    // "Erbil" and "Ercil" share "Er" and "il"; kept, those stay put. Off,
    // nothing is shared and the whole word leaves and arrives.
    for (final keep in [true, false]) {
      Widget build(String t) => host(TextMorph(t, keepShared: keep,
        morph: const MorphStyle.slide(), duration: const Duration(milliseconds: 200)));
      await tester.pumpWidget(build('Erbil'));
      await tester.pumpWidget(build('Ercil'));
      await tester.pump(const Duration(milliseconds: 80));
      final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(TextMorph), matching: find.byType(CustomPaint)));
      final MorphDiff diff = (paint.painter as dynamic).diff;
      expect((diff.prefix, diff.suffix), keep ? (2, 2) : (0, 0), reason: 'keep $keep');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('morph: rich spans morph as one line in their own styles',
      (tester) async {
    InlineSpan line(String city, String code) => TextSpan(children: [
      TextSpan(text: city),
      TextSpan(text: ' · $code', style: const TextStyle(color: Color(0xFF888888))),
    ]);
    Widget build(String city, String code) => host(TextMorph.rich(line(city, code),
      unit: TextUnit.word, keepShared: false,
      morph: const MorphStyle.slide(), duration: const Duration(milliseconds: 200)));
    await tester.pumpWidget(build('Erbil', 'EBL'));
    expect(find.bySemanticsLabel('Erbil · EBL'), findsOneWidget);
    await tester.pumpWidget(build('Istanbul', 'IST'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(TextMorph), matching: find.byType(CustomPaint)));
    final MorphDiff diff = (paint.painter as dynamic).diff;
    expect((diff.prefix, diff.suffix), (0, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.bySemanticsLabel('Istanbul · IST'), findsOneWidget);
    // The same words in a new colour restyle without an exchange.
    await tester.pumpWidget(host(TextMorph.rich(const TextSpan(children: [
      TextSpan(text: 'Istanbul'),
      TextSpan(text: ' · IST', style: TextStyle(color: Color(0xFFFF0000))),
    ]), unit: TextUnit.word, duration: const Duration(milliseconds: 200))));
    expect(tester.binding.transientCallbackCount, 0);
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

void _newEffectTests() {
  testWidgets('the second ten: every reveal plays and every loop ticks',
      (tester) async {
    const accent = Color(0xFF3366FF);
    for (final effect in const <TextEffect>[
      Bounce(),
      Squeeze(),
      Outline(color: accent),
      Scramble(),
    ]) {
      await tester.pumpWidget(host(KineticText(
        'Autumn Sale 2026',
        effects: [effect],
        duration: const Duration(milliseconds: 300),
      )));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull, reason: '$effect');
      }
      expect(tester.binding.transientCallbackCount, 0, reason: '$effect is a one-shot');
    }
    for (final effect in const <TextEffect>[
      Wave(),
      Pulse(color: accent),
      Spotlight(focus: accent),
      Flicker(),
    ]) {
      await tester.pumpWidget(host(KineticText('Live now', effects: [effect])));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.transientCallbackCount, greaterThan(0), reason: '$effect loops');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 330));
        expect(tester.takeException(), isNull, reason: '$effect');
      }
      await tester.pumpWidget(host(const SizedBox()));
      expect(tester.binding.transientCallbackCount, 0, reason: '$effect released its clock');
    }
  });

  testWidgets('a stroked twin lays out on the same metrics and is disposed',
      (tester) async {
    final shaped = ShapedText.shape(
      span: const TextSpan(text: 'Verified', style: TextStyle(fontSize: 20, color: Color(0xFF000000))),
      text: 'Verified',
      direction: TextDirection.ltr,
    );
    final twin = shaped.strokedTwin(width: 1.5, color: const Color(0xFFFF0000));
    expect(twin.width, shaped.width);
    expect(twin.height, shaped.height);
    expect(identical(twin, shaped.strokedTwin(width: 1.5, color: const Color(0xFFFF0000))), isTrue,
        reason: 'cached per width and colour');
    shaped.dispose();
  });
}
