import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'models.dart';

class CardRepository {
  CardRepository(this.database, this.documentsDirectory);

  final AppDatabase database;
  final Directory documentsDirectory;
  final Uuid _uuid = const Uuid();

  Directory get _photos => Directory(p.join(documentsDirectory.path, 'photos'));
  Directory get _audio => Directory(p.join(documentsDirectory.path, 'audio'));

  Future<void> initialize() async {
    await _photos.create(recursive: true);
    await _audio.create(recursive: true);
    await purgeExpired();
    await _removeOrphanedMedia();
  }

  File photoFile(MemoryCard card) =>
      File(p.join(documentsDirectory.path, card.photoPath));

  File? audioFile(MemoryCard card) => card.audioPath == null
      ? null
      : File(p.join(documentsDirectory.path, card.audioPath));

  Future<List<Collection>> listCollections() async {
    final rows = await database.db.query(
      'collections',
      orderBy: 'created_at, id',
    );
    return rows.map(Collection.fromRow).toList();
  }

  Future<Collection> createCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Collection name cannot be empty.');
    }
    final id = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    await database.db.insert('collections', {
      'id': id,
      'name': trimmed,
      'created_at': createdAt.toIso8601String(),
    });
    return Collection(id: id, name: trimmed, createdAt: createdAt);
  }

  Future<List<MemoryCard>> listActiveCards(String collectionId) async {
    final rows = await database.db.query(
      'cards',
      where: 'collection_id = ? AND deleted_at IS NULL',
      whereArgs: [collectionId],
      orderBy: 'photo_date DESC, created_at DESC',
    );
    return rows.map(MemoryCard.fromRow).toList();
  }

  Future<MemoryCard?> getCard(String id) async {
    final rows = await database.db.query(
      'cards',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : MemoryCard.fromRow(rows.single);
  }

  Future<List<MemoryCard>> listDeletedCards() async {
    final rows = await database.db.query(
      'cards',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(MemoryCard.fromRow).toList();
  }

  Future<MemoryCard> editCard({
    required String id,
    required String? text,
    File? newAudio,
    bool removeAudio = false,
    bool removeLocation = false,
    DateTime? at,
  }) async {
    if (newAudio != null && removeAudio) {
      throw ArgumentError('Cannot replace and remove audio together.');
    }
    final now = (at ?? DateTime.now()).toUtc();
    final current = await getCard(id);
    if (current == null ||
        current.deletedAt != null ||
        !now.isBefore(current.editDeadline)) {
      throw StateError('This card can no longer be edited.');
    }
    if (newAudio != null && !await newAudio.exists()) {
      throw ArgumentError('New audio does not exist.');
    }
    final newAudioPath = newAudio == null
        ? null
        : p.posix.join('audio', '${id}_${_uuid.v4()}.m4a');
    final newAudioTarget = newAudioPath == null
        ? null
        : File(p.join(documentsDirectory.path, newAudioPath));
    String? oldAudioPath;
    try {
      if (newAudio != null) await newAudio.copy(newAudioTarget!.path);
      await database.db.transaction((txn) async {
        final rows = await txn.query('cards', where: 'id = ?', whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Card not found.');
        final latest = MemoryCard.fromRow(rows.single);
        if (latest.deletedAt != null || !now.isBefore(latest.editDeadline)) {
          throw StateError('This card can no longer be edited.');
        }
        oldAudioPath = latest.audioPath;
        await txn.update(
          'cards',
          {
            'text': text?.trim().isEmpty == true ? null : text?.trim(),
            'audio_path':
                newAudioPath ?? (removeAudio ? null : latest.audioPath),
            'latitude': removeLocation ? null : latest.latitude,
            'longitude': removeLocation ? null : latest.longitude,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } catch (_) {
      if (newAudioTarget != null) await _deleteIfPresent(newAudioTarget);
      rethrow;
    }
    if ((newAudio != null || removeAudio) && oldAudioPath != null) {
      try {
        await _deleteIfPresent(
          File(p.join(documentsDirectory.path, oldAudioPath!)),
        );
      } catch (_) {
        // The committed edit is valid; the startup orphan sweep will retry.
      }
    }
    return (await getCard(id))!;
  }

  Future<MemoryCard> softDeleteCard(String id, {DateTime? at}) async {
    final now = (at ?? DateTime.now()).toUtc();
    final count = await database.db.update(
      'cards',
      {
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Active card not found.');
    return (await getCard(id))!;
  }

  Future<MemoryCard> restoreCard(String id, {DateTime? at}) async {
    final now = (at ?? DateTime.now()).toUtc();
    await database.db.transaction((txn) async {
      final rows = await txn.query('cards', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Card not found.');
      final card = MemoryCard.fromRow(rows.single);
      if (card.deletedAt == null || !now.isBefore(card.purgeAt!)) {
        throw StateError('This card can no longer be restored.');
      }
      await txn.update(
        'cards',
        {'deleted_at': null, 'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    return (await getCard(id))!;
  }

  Future<int> purgeExpired({DateTime? at}) async {
    final cutoff = (at ?? DateTime.now()).toUtc().subtract(
      const Duration(days: 30),
    );
    final expired = <MemoryCard>[];
    await database.db.transaction((txn) async {
      final rows = await txn.query(
        'cards',
        where: 'deleted_at IS NOT NULL AND deleted_at <= ?',
        whereArgs: [cutoff.toIso8601String()],
      );
      expired.addAll(rows.map(MemoryCard.fromRow));
      for (final card in expired) {
        await txn.delete('cards', where: 'id = ?', whereArgs: [card.id]);
      }
    });
    for (final card in expired) {
      try {
        await _deleteIfPresent(photoFile(card));
        final audio = audioFile(card);
        if (audio != null) await _deleteIfPresent(audio);
      } catch (_) {
        // Rows are already gone. Orphan cleanup retries next launch.
      }
    }
    return expired.length;
  }

  // The caller supplies a normalized private-ready photo. Capture and import
  // flows will perform square crop, orientation, metadata stripping, and encoding.
  Future<MemoryCard> saveCard({
    required String collectionId,
    required File processedPhoto,
    required DateTime photoDate,
    required PhotoDateSource photoDateSource,
    String? displayDate,
    String? text,
    File? recordedAudio,
    double? latitude,
    double? longitude,
  }) async {
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError('Location requires both latitude and longitude.');
    }
    if (!await processedPhoto.exists()) {
      throw ArgumentError('Processed photo does not exist.');
    }
    if (recordedAudio != null && !await recordedAudio.exists()) {
      throw ArgumentError('Recorded audio does not exist.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    // Database paths use forward slashes so a later export is platform neutral.
    final photoPath = p.posix.join('photos', '$id.jpg');
    final audioPath = recordedAudio == null
        ? null
        : p.posix.join('audio', '$id.m4a');
    final photoTarget = File(p.join(documentsDirectory.path, photoPath));
    final audioTarget = audioPath == null
        ? null
        : File(p.join(documentsDirectory.path, audioPath));
    try {
      await processedPhoto.copy(photoTarget.path);
      if (recordedAudio != null) {
        await recordedAudio.copy(audioTarget!.path);
      }
      await database.db.transaction((txn) async {
        await txn.insert('cards', {
          'id': id,
          'collection_id': collectionId,
          'photo_date': photoDate.toUtc().toIso8601String(),
          'display_date':
              displayDate ??
              '${photoDate.year.toString().padLeft(4, '0')}-${photoDate.month.toString().padLeft(2, '0')}-${photoDate.day.toString().padLeft(2, '0')}',
          'photo_date_source': photoDateSource.name,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'deleted_at': null,
          'photo_path': photoPath,
          'text': text?.trim().isEmpty == true ? null : text?.trim(),
          'audio_path': audioPath,
          'latitude': latitude,
          'longitude': longitude,
        });
      });
    } catch (_) {
      await _deleteIfPresent(photoTarget);
      if (audioTarget != null) await _deleteIfPresent(audioTarget);
      rethrow;
    }
    return (await getCard(id))!;
  }

  Future<void> _removeOrphanedMedia() async {
    final rows = await database.db.query(
      'cards',
      columns: ['photo_path', 'audio_path'],
    );
    final referenced = <String>{
      for (final row in rows) row['photo_path']! as String,
      for (final row in rows)
        if (row['audio_path'] != null) row['audio_path']! as String,
    };
    for (final directory in [_photos, _audio]) {
      await for (final entity in directory.list()) {
        if (entity is File &&
            !referenced.contains(
              p.posix.join(p.basename(directory.path), p.basename(entity.path)),
            )) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}
