import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/card_repository.dart';
import '../data/models.dart';
import 'export_paths.dart';

const archiveFormatVersion = 1;

class ExportBundle {
  const ExportBundle(this.file, this.directory);

  final File file;
  final Directory directory;

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class ArchiveExport {
  const ArchiveExport(this.repository, this.cacheDirectory);

  final CardRepository repository;
  final Directory cacheDirectory;

  Future<Directory> _scratch() async {
    await cacheDirectory.create(recursive: true);
    return cacheDirectory.createTemp('export_');
  }

  Future<ExportBundle> card(MemoryCard card) async {
    final directory = await _scratch();
    try {
      final file = File(p.join(directory.path, 'card-${card.id}.zip'));
      await _writeCard(card, file, directory);
      return ExportBundle(file, directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<ExportBundle> collection(
    Collection collection, {
    Set<String>? cardIds,
  }) async {
    final directory = await _scratch();
    try {
      final active = await repository.listActiveCards(collection.id);
      final cards = cardIds == null
          ? active
          : active.where((card) => cardIds.contains(card.id)).toList();
      if (cardIds != null &&
          (cardIds.isEmpty || cards.length != cardIds.length)) {
        throw StateError('Some selected cards are no longer available.');
      }
      final entries = <Map<String, Object?>>[];
      final cardFiles = <File>[];
      for (final card in cards) {
        final cardDirectory = await Directory(
          p.join(directory.path, card.id),
        ).create();
        final file = File(p.join(cardDirectory.path, '${card.id}.zip'));
        await _writeCard(card, file, cardDirectory);
        cardFiles.add(file);
        entries.add({
          'id': card.id,
          'file': 'cards/${card.id}.zip',
          'bytes': await file.length(),
          'sha256': await _hash(file),
        });
      }
      final manifest = await _writeManifest(
        directory,
        'collection_manifest.json',
        {
          'format': 'my-photo-frame-collection',
          'format_version': archiveFormatVersion,
          'collection': {
            'id': collection.id,
            'name': collection.name,
            'created_at': collection.createdAt.toUtc().toIso8601String(),
          },
          'cards': entries,
        },
      );
      final output = File(
        p.join(
          directory.path,
          '${exportCollectionName(collection.name)}${cardIds == null ? '' : '-selected-cards'}.zip',
        ),
      );
      final encoder = ZipFileEncoder()..create(output.path);
      try {
        await encoder.addFile(manifest, 'manifest.json');
        for (var i = 0; i < cardFiles.length; i++) {
          await encoder.addFile(
            cardFiles[i],
            entries[i]['file']! as String,
            ZipFileEncoder.store,
          );
        }
      } finally {
        await encoder.close();
      }
      return ExportBundle(output, directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _writeCard(
    MemoryCard original,
    File output,
    Directory scratch,
  ) async {
    final card = await repository.getCard(original.id);
    if (card == null || card.deletedAt != null) {
      throw StateError('This card is no longer available for export.');
    }
    final photo = repository.photoFile(card);
    final audio = repository.audioFile(card);
    final manifest = await _writeManifest(scratch, 'card_manifest.json', {
      'format': 'my-photo-frame-card',
      'format_version': archiveFormatVersion,
      'card': {
        'id': card.id,
        'collection_id': card.collectionId,
        'photo_date': card.photoDate.toUtc().toIso8601String(),
        'display_date': card.displayDate,
        'photo_date_source': card.photoDateSource.name,
        'created_at': card.createdAt.toUtc().toIso8601String(),
        'updated_at': card.updatedAt.toUtc().toIso8601String(),
        'text': card.text,
        'latitude': card.latitude,
        'longitude': card.longitude,
      },
      'photo': {
        'file': 'photo.jpg',
        'bytes': await photo.length(),
        'sha256': await _hash(photo),
      },
      'audio': audio == null
          ? null
          : {
              'file': 'audio.m4a',
              'bytes': await audio.length(),
              'sha256': await _hash(audio),
            },
    });
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      await encoder.addFile(manifest, 'manifest.json');
      await encoder.addFile(photo, 'photo.jpg', ZipFileEncoder.store);
      if (audio != null) {
        await encoder.addFile(audio, 'audio.m4a', ZipFileEncoder.store);
      }
    } finally {
      await encoder.close();
    }
  }

  Future<File> _writeManifest(
    Directory directory,
    String filename,
    Map<String, Object?> contents,
  ) async {
    final file = File(p.join(directory.path, filename));
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(contents)}\n',
    );
    return file;
  }

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
