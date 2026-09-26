import 'dart:io';

import 'package:flutter/services.dart';

import '../data/models.dart';

class ImportMetadata {
  const ImportMetadata({
    required this.photoDate,
    required this.displayDate,
    required this.dateSource,
    this.latitude,
    this.longitude,
  });

  final DateTime photoDate;
  final String displayDate;
  final PhotoDateSource dateSource;
  final double? latitude;
  final double? longitude;
}

const _channel = MethodChannel('my_photo_frame/import_metadata');

Future<ImportMetadata> readImportMetadata(File file) async {
  final importedAt = DateTime.now();
  Map<dynamic, dynamic> raw = {};
  try {
    raw =
        await _channel.invokeMapMethod<dynamic, dynamic>('read', {
          'path': file.path,
        }) ??
        {};
  } on PlatformException {
    // Missing or damaged metadata is normal for downloaded and edited images.
  }
  final date = parseExifDate(raw['date'] as String?, raw['offset'] as String?);
  final displayDate = date == null
      ? _calendarDate(importedAt)
      : (raw['date'] as String).substring(0, 10).replaceAll(':', '-');
  final latitude = (raw['latitude'] as num?)?.toDouble();
  final longitude = (raw['longitude'] as num?)?.toDouble();
  final hasValidLocation =
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  return ImportMetadata(
    photoDate: date ?? importedAt,
    displayDate: displayDate,
    dateSource: date == null
        ? PhotoDateSource.importFallback
        : PhotoDateSource.exif,
    latitude: hasValidLocation ? latitude : null,
    longitude: hasValidLocation ? longitude : null,
  );
}

DateTime? parseExifDate(String? raw, String? offset) {
  if (raw == null) return null;
  final match = RegExp(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2}) (\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(raw);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final [year, month, day, hour, minute, second] = parts;
  if (year < 1900 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final local = DateTime(year, month, day, hour, minute, second);
  if (local.year != year || local.month != month || local.day != day) {
    return null;
  }
  if (offset != null &&
      RegExp(r'^[+-](0\d|1[0-4]):[0-5]\d$').hasMatch(offset)) {
    return DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}$offset',
    );
  }
  // EXIF commonly omits timezone. Keep the photographed wall date visible.
  return local;
}

String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
