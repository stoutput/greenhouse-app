import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/ambient_lighting.dart';

void main() {
  testWidgets('static rays pass taps through and need no frame ticker', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Tap'),
              ),
            ),
            Positioned.fill(
              child: AmbientLighting(now: DateTime(2026, 11, 10, 9)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test('day and night produce subtle warm and cool rays', () async {
    Future<List<int>> totalColor(int hour) async {
      final recorder = ui.PictureRecorder();
      AmbientLightPainter(
        now: DateTime(2026, 11, 10, hour),
        dark: true,
      ).paint(Canvas(recorder), const Size(392, 820));
      final picture = recorder.endRecording();
      final image = await picture.toImage(392, 820);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final totals = [0, 0, 0, 0];
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        for (var channel = 0; channel < 4; channel++) {
          totals[channel] += bytes.getUint8(i + channel);
        }
        expect(bytes.getUint8(i + 3), lessThanOrEqualTo(34));
      }
      image.dispose();
      picture.dispose();
      return totals;
    }

    final day = await totalColor(9);
    final night = await totalColor(21);
    expect(day[3], greaterThan(0));
    expect(night[3], greaterThan(0));
    expect(day[0], greaterThan(day[2]));
    expect(night[2], greaterThan(night[0]));
  });
}
