import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/src/data/app_database.dart';
import 'package:my_photo_frame/src/data/card_repository.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory documents;
  late AppDatabase database;
  late CardRepository repository;

  Future<void> openApp() async {
    database = await AppDatabase.open(
      p.join(documents.path, 'cards.db'),
      factory: databaseFactoryFfi,
    );
    repository = CardRepository(database, documents);
    await repository.initialize();
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('my_photo_frame_test_');
    await openApp();
  });

  tearDown(() async {
    await database.close();
    await documents.delete(recursive: true);
  });

  test('Default is created once and a card survives reopening', () async {
    final samplePhoto = File(p.join(documents.path, 'sample.jpg'));
    await samplePhoto.writeAsBytes(
      image.encodeJpg(image.Image(width: 2, height: 2)),
    );
    final photoDate = DateTime.utc(2025, 7, 10, 16, 30);
    final saved = await repository.saveCard(
      collectionId: Collection.defaultId,
      processedPhoto: samplePhoto,
      photoDate: photoDate,
      photoDateSource: PhotoDateSource.capture,
      text: '  Summer afternoon  ',
    );
    expect(await repository.photoFile(saved).exists(), isTrue);
    expect(saved.text, 'Summer afternoon');
    expect(saved.photoDate, photoDate);
    expect(saved.displayDate, '2025-07-10');
    expect(saved.editDeadline, saved.createdAt.add(const Duration(hours: 24)));

    await database.close();
    await openApp();

    final collections = await repository.listCollections();
    expect(collections, hasLength(1));
    expect(collections.single.name, 'Default');
    final cards = await repository.listActiveCards(Collection.defaultId);
    expect(cards, hasLength(1));
    expect(cards.single.id, saved.id);
    expect(cards.single.displayDate, '2025-07-10');
    expect(
      await repository.photoFile(cards.single).readAsBytes(),
      await samplePhoto.readAsBytes(),
    );
  });

  test('failed database insert leaves no private media behind', () async {
    final samplePhoto = File(p.join(documents.path, 'sample.jpg'));
    await samplePhoto.writeAsBytes(
      image.encodeJpg(image.Image(width: 2, height: 2)),
    );
    await expectLater(
      repository.saveCard(
        collectionId: 'missing',
        processedPhoto: samplePhoto,
        photoDate: DateTime.utc(2025),
        photoDateSource: PhotoDateSource.capture,
      ),
      throwsA(isA<Exception>()),
    );
    expect(Directory(p.join(documents.path, 'photos')).listSync(), isEmpty);
    expect(await repository.listActiveCards(Collection.defaultId), isEmpty);
  });

  test('startup removes media left by an interrupted save', () async {
    final orphan = File(p.join(documents.path, 'photos', 'orphan.jpg'));
    await orphan.writeAsBytes([1, 2, 3]);
    await repository.initialize();
    expect(await orphan.exists(), isFalse);
  });

  test('collection names are unique without regard to case', () async {
    final trip = await repository.createCollection('  Italy trip  ');
    expect(trip.name, 'Italy trip');
    expect(await repository.listCollections(), hasLength(2));
    await expectLater(
      repository.createCollection('italy trip'),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'optional fields can change before 24 hours and not at the deadline',
    () async {
      final samplePhoto = File(p.join(documents.path, 'sample.jpg'));
      await samplePhoto.writeAsBytes(
        image.encodeJpg(image.Image(width: 2, height: 2)),
      );
      final sampleAudio = File(p.join(documents.path, 'sample.m4a'));
      await sampleAudio.writeAsBytes([1, 2, 3]);
      final saved = await repository.saveCard(
        collectionId: Collection.defaultId,
        processedPhoto: samplePhoto,
        photoDate: DateTime.utc(2025),
        photoDateSource: PhotoDateSource.capture,
        text: 'First',
        recordedAudio: sampleAudio,
        latitude: 51.5,
        longitude: -0.1,
      );
      final oldAudio = repository.audioFile(saved)!;
      final edited = await repository.editCard(
        id: saved.id,
        text: null,
        removeAudio: true,
        removeLocation: true,
        at: saved.editDeadline.subtract(const Duration(milliseconds: 1)),
      );
      expect(edited.text, isNull);
      expect(edited.audioPath, isNull);
      expect(edited.latitude, isNull);
      expect(edited.longitude, isNull);
      expect(edited.editDeadline, saved.editDeadline);
      expect(await oldAudio.exists(), isFalse);
      expect(await repository.photoFile(edited).exists(), isTrue);
      await expectLater(
        repository.editCard(
          id: saved.id,
          text: 'Too late',
          at: saved.editDeadline,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'deleted card restores within 30 days and purges at the boundary',
    () async {
      final samplePhoto = File(p.join(documents.path, 'sample.jpg'));
      await samplePhoto.writeAsBytes(
        image.encodeJpg(image.Image(width: 2, height: 2)),
      );
      final saved = await repository.saveCard(
        collectionId: Collection.defaultId,
        processedPhoto: samplePhoto,
        photoDate: DateTime.utc(2025),
        photoDateSource: PhotoDateSource.capture,
      );
      final deletedAt = saved.createdAt.add(const Duration(hours: 25));
      final deleted = await repository.softDeleteCard(saved.id, at: deletedAt);
      expect(await repository.listActiveCards(Collection.defaultId), isEmpty);
      expect(await repository.listDeletedCards(), hasLength(1));
      final restored = await repository.restoreCard(
        saved.id,
        at: deleted.purgeAt!.subtract(const Duration(milliseconds: 1)),
      );
      expect(restored.editDeadline, saved.editDeadline);
      await expectLater(
        repository.editCard(
          id: saved.id,
          text: 'Too late',
          at: deleted.purgeAt,
        ),
        throwsA(isA<StateError>()),
      );
      final deletedAgain = await repository.softDeleteCard(
        saved.id,
        at: deleted.purgeAt!.subtract(const Duration(milliseconds: 1)),
      );
      await expectLater(
        repository.restoreCard(saved.id, at: deletedAgain.purgeAt),
        throwsA(isA<StateError>()),
      );
      expect(await repository.purgeExpired(at: deletedAgain.purgeAt), 1);
      expect(await repository.getCard(saved.id), isNull);
      expect(await repository.photoFile(saved).exists(), isFalse);
    },
  );
}
