import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const maxCardPhotoBytes = 1000000;

/// Converts a camera image into a square JPEG without source EXIF metadata.
Future<File> processCardPhoto(File source, Directory draftsDirectory) async {
  await draftsDirectory.create(recursive: true);
  final bytes = await Isolate.run(() => _encodeCardPhoto(source.path));
  final output = File(p.join(draftsDirectory.path, '${const Uuid().v4()}.jpg'));
  await output.writeAsBytes(bytes, flush: true);
  return output;
}

Uint8List _encodeCardPhoto(String sourcePath) {
  final source = image.decodeImage(File(sourcePath).readAsBytesSync());
  if (source == null) {
    throw const FormatException('Photo could not be decoded.');
  }
  final oriented = image.bakeOrientation(source);
  final side = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final square = image.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  square.exif = image.ExifData();
  square.iccProfile = null;

  var targetSide = side > 1600 ? 1600 : side;
  while (targetSide > 0) {
    final resized = targetSide == side
        ? square
        : image.copyResize(
            square,
            width: targetSide,
            height: targetSide,
            interpolation: image.Interpolation.average,
          );
    resized.exif = image.ExifData();
    resized.iccProfile = null;
    for (final quality in [90, 80, 70, 60, 50, 40]) {
      final bytes = image.encodeJpg(resized, quality: quality);
      if (bytes.length <= maxCardPhotoBytes) {
        final verified = image.decodeJpg(bytes);
        if (verified == null || verified.width != verified.height) {
          throw const FormatException('Processed photo is not square.');
        }
        return bytes;
      }
    }
    if (targetSide <= 128) break;
    targetSide = (targetSide * 0.8).floor().clamp(128, targetSide - 1);
  }
  throw const FormatException('Photo could not be compressed below 1 MB.');
}
