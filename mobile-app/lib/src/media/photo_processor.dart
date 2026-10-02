import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const maxCardPhotoBytes = 1000000;

/// Crops to a full-resolution square JPEG without source EXIF metadata.
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

  Uint8List? best;
  var low = 1;
  var high = 95;
  while (low <= high) {
    final quality = (low + high) ~/ 2;
    final bytes = image.encodeJpg(square, quality: quality);
    if (bytes.length <= maxCardPhotoBytes) {
      best = bytes;
      low = quality + 1;
    } else {
      high = quality - 1;
    }
  }
  if (best == null) {
    throw const FormatException(
      'Photo could not be compressed below 1 MB without reducing its resolution.',
    );
  }
  return best;
}
