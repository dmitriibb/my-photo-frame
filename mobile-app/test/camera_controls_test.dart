import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_photo_frame/src/capture/camera_screen.dart';

void main() {
  test('square tap coordinates account for the cropped preview', () {
    expect(
      squarePreviewPoint(const Offset(0, 0), 400, const Size(400, 600)),
      const Offset(0, 1 / 6),
    );
    expect(
      squarePreviewPoint(const Offset(400, 400), 400, const Size(400, 600)),
      const Offset(1, 5 / 6),
    );
    expect(
      squarePreviewPoint(const Offset(200, 200), 400, const Size(600, 400)),
      const Offset(0.5, 0.5),
    );
  });

  testWidgets('dragging the zoom wheel sends right and left movement', (
    tester,
  ) async {
    final deltas = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 320,
              height: 88,
              child: ZoomWheel(
                zoom: 1,
                minZoom: 1,
                maxZoom: 8,
                offset: 0,
                onDrag: deltas.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ZoomWheel), const Offset(100, 0));
    expect(deltas.any((delta) => delta > 0), isTrue);
    deltas.clear();
    await tester.drag(find.byType(ZoomWheel), const Offset(-100, 0));
    expect(deltas.any((delta) => delta < 0), isTrue);
  });
}
