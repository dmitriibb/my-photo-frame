import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/media/import_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('my_photo_frame/import_metadata');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'EXIF date keeps the photographed day across timezone offsets',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'date': '2023:12:31 23:30:00',
              'offset': '-05:00',
              'latitude': 52.5,
              'longitude': 13.4,
            },
          );
      final metadata = await readImportMetadata(File('unused'));
      expect(metadata.displayDate, '2023-12-31');
      expect(metadata.displayTime, '23:30');
      expect(metadata.photoDate.toUtc(), DateTime.utc(2024, 1, 1, 4, 30));
      expect(metadata.dateSource, PhotoDateSource.exif);
      expect(metadata.latitude, 52.5);
    },
  );

  test('bad EXIF date and coordinates fall back safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'date': '2023:02:30 10:00:00',
            'latitude': 120.0,
            'longitude': 13.4,
          },
        );
    final metadata = await readImportMetadata(File('unused'));
    expect(metadata.dateSource, PhotoDateSource.importFallback);
    expect(metadata.latitude, isNull);
    expect(metadata.longitude, isNull);
  });
}
