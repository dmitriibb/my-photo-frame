import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/src/data/app_database.dart';
import 'package:my_photo_frame/src/data/card_repository.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/export/archive_export.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'card and collection ZIPs are readable and exclude deleted cards',
    () async {
      final root = await Directory.systemTemp.createTemp('frame_archive_test_');
      try {
        final db = await AppDatabase.open(
          p.join(root.path, 'cards.db'),
          factory: databaseFactoryFfi,
        );
        try {
          final repository = CardRepository(db, root);
          await repository.initialize();
          final photo = File(p.join(root.path, 'sample.jpg'));
          await photo.writeAsBytes(
            image.encodeJpg(image.Image(width: 3, height: 3)),
          );
          final audio = File(p.join(root.path, 'sample.m4a'));
          await audio.writeAsBytes([1, 2, 3, 4]);
          final card = await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2024, 1, 2),
            photoDateSource: PhotoDateSource.exif,
            displayDate: '2024-01-01',
            text: 'Saved memory',
            recordedAudio: audio,
            latitude: 52.5,
            longitude: 13.4,
          );
          final deleted = await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2024, 1, 3),
            photoDateSource: PhotoDateSource.capture,
          );
          await repository.softDeleteCard(deleted.id);
          final unselected = await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2024, 1, 4),
            photoDateSource: PhotoDateSource.capture,
          );
          final exporter = ArchiveExport(
            repository,
            Directory(p.join(root.path, 'exports')),
          );
          final bundle = await exporter.collection(
            (await repository.listCollections()).single,
            cardIds: {card.id},
          );
          try {
            final outer = ZipDecoder().decodeBytes(
              await bundle.file.readAsBytes(),
            );
            final outerManifest =
                jsonDecode(
                      utf8.decode(outer.findFile('manifest.json')!.content),
                    )
                    as Map<String, dynamic>;
            expect(outerManifest['format_version'], archiveFormatVersion);
            final entries = outerManifest['cards'] as List<dynamic>;
            expect(entries, hasLength(1));
            final entry = entries.single as Map<String, dynamic>;
            expect(entry['id'], card.id);
            expect(outer.findFile('cards/${unselected.id}.zip'), isNull);
            final cardBytes = outer.findFile(entry['file'] as String)!.content;
            expect(sha256.convert(cardBytes).toString(), entry['sha256']);
            final inner = ZipDecoder().decodeBytes(cardBytes);
            final manifest =
                jsonDecode(
                      utf8.decode(inner.findFile('manifest.json')!.content),
                    )
                    as Map<String, dynamic>;
            expect(manifest['format'], 'my-photo-frame-card');
            expect(manifest['format_version'], archiveFormatVersion);
            expect(
              (manifest['card'] as Map<String, dynamic>)['display_date'],
              '2024-01-01',
            );
            expect(
              (manifest['card'] as Map<String, dynamic>)['text'],
              'Saved memory',
            );
            final photoBytes = inner.findFile('photo.jpg')!.content;
            expect(
              sha256.convert(photoBytes).toString(),
              (manifest['photo'] as Map<String, dynamic>)['sha256'],
            );
            expect(inner.findFile('audio.m4a')!.content, [1, 2, 3, 4]);
          } finally {
            await bundle.dispose();
          }
          final collection = (await repository.listCollections()).single;
          final full = await exporter.collection(collection);
          try {
            final zip = ZipDecoder().decodeBytes(await full.file.readAsBytes());
            final manifest =
                jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content))
                    as Map<String, dynamic>;
            expect(manifest['cards'], hasLength(2));
          } finally {
            await full.dispose();
          }
          for (final ids in [
            <String>{},
            {deleted.id},
            {'missing'},
          ]) {
            await expectLater(
              exporter.collection(collection, cardIds: ids),
              throwsStateError,
            );
          }
          await expectLater(exporter.card(deleted), throwsStateError);
          expect(await exporter.cacheDirectory.list().toList(), isEmpty);
        } finally {
          await db.close();
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
