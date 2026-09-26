import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/src/media/photo_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(
    () async => temp = await Directory.systemTemp.createTemp('photo_test_'),
  );
  tearDown(() async => temp.delete(recursive: true));

  test('camera image is center-cropped, square, and strips EXIF', () async {
    final source = image.Image(width: 120, height: 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 120; x++) {
        source.setPixelRgb(
          x,
          y,
          x < 40 ? 255 : 0,
          x >= 40 && x < 80 ? 255 : 0,
          x >= 80 ? 255 : 0,
        );
      }
    }
    source.exif.gpsIfd[1] = 'N';
    final input = File(p.join(temp.path, 'source.jpg'));
    await input.writeAsBytes(image.encodeJpg(source));

    final output = await processCardPhoto(
      input,
      Directory(p.join(temp.path, 'drafts')),
    );
    final bytes = await output.readAsBytes();
    final decoded = image.decodeJpg(bytes)!;
    expect(decoded.width, 40);
    expect(decoded.height, 40);
    expect(bytes.length, lessThanOrEqualTo(maxCardPhotoBytes));
    expect(decoded.getPixel(20, 20).g, greaterThan(200));
    expect(decoded.exif.gpsIfd.isEmpty, isTrue);
  });

  test('large noisy photo is compressed below one million bytes', () async {
    final source = image.Image(width: 1200, height: 1200);
    var seed = 17;
    for (var y = 0; y < 1200; y++) {
      for (var x = 0; x < 1200; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        source.setPixelRgb(
          x,
          y,
          seed & 255,
          (seed >> 8) & 255,
          (seed >> 16) & 255,
        );
      }
    }
    final input = File(p.join(temp.path, 'noisy.png'));
    await input.writeAsBytes(image.encodePng(source));

    final output = await processCardPhoto(
      input,
      Directory(p.join(temp.path, 'drafts')),
    );
    final bytes = await output.readAsBytes();
    final decoded = image.decodeJpg(bytes)!;
    expect(bytes.length, lessThanOrEqualTo(maxCardPhotoBytes));
    expect(decoded.width, decoded.height);
  });
}
