enum PhotoDateSource { capture, exif, file, importFallback }

class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.createdAt,
    this.deletedAt,
  });

  static const defaultId = 'default';

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? deletedAt;

  DateTime? get purgeAt => deletedAt?.add(const Duration(days: 30));

  factory Collection.fromRow(Map<String, Object?> row) => Collection(
    id: row['id']! as String,
    name: row['name']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.parse(row['deleted_at']! as String),
  );
}

class MemoryCard {
  const MemoryCard({
    required this.id,
    required this.collectionId,
    required this.photoDate,
    required this.displayDate,
    this.displayTime,
    required this.photoDateSource,
    required this.createdAt,
    required this.updatedAt,
    required this.photoPath,
    this.deletedAt,
    this.text,
    this.audioPath,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String collectionId;
  final DateTime photoDate;

  /// The day shown on the card, fixed at capture/import time (YYYY-MM-DD).
  final String displayDate;

  /// The photographed wall-clock time (HH:mm), when image metadata has one.
  final String? displayTime;
  final PhotoDateSource photoDateSource;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String photoPath;
  final String? text;
  final String? audioPath;
  final double? latitude;
  final double? longitude;

  DateTime get editDeadline => createdAt.add(const Duration(hours: 24));
  DateTime? get purgeAt => deletedAt?.add(const Duration(days: 30));

  factory MemoryCard.fromRow(Map<String, Object?> row) => MemoryCard(
    id: row['id']! as String,
    collectionId: row['collection_id']! as String,
    photoDate: DateTime.parse(row['photo_date']! as String),
    displayDate: row['display_date']! as String,
    displayTime: row['display_time'] as String?,
    photoDateSource: PhotoDateSource.values.byName(
      row['photo_date_source']! as String,
    ),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.parse(row['deleted_at']! as String),
    photoPath: row['photo_path']! as String,
    text: row['text'] as String?,
    audioPath: row['audio_path'] as String?,
    latitude: row['latitude'] as double?,
    longitude: row['longitude'] as double?,
  );
}
