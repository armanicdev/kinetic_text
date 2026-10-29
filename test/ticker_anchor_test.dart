// A ticker whose anchor changes under it paints from the new edge: the
// slots were keyed by the new anchor while the painter kept laying them out
// from the old one, so 415 read 514 after a switch to a right-to-left
// language.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_text/kinetic_text.dart';

const _font = 'test/fonts/Leraw.ttf';

void main() {
  setUpAll(() async {
    final bytes = File(_font).readAsBytesSync();
    await (FontLoader('Leraw')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });

  final frame = GlobalKey();
  Widget at(TickerAnchor anchor) => MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: frame,
              child: TickerText(
                '415',
                anchor: anchor,
                style: const TextStyle(
                  fontFamily: 'Leraw',
                  fontSize: 40,
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
        ),
      );

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
  }

  testWidgets('a changed anchor paints the digits in order', (tester) async {
    await tester.pumpWidget(at(TickerAnchor.left));
    await tester.pumpAndSettle();
    final fresh = await pixels(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(at(TickerAnchor.right));
    await tester.pumpAndSettle();
    await tester.pumpWidget(at(TickerAnchor.left));
    await tester.pumpAndSettle();

    expect(await pixels(tester), equals(fresh));
  });
}
