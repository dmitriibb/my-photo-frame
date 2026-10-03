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
      displayTime: '16:30',
      text: '  Summer afternoon  ',
    );
    expect(await repository.photoFile(saved).exists(), isTrue);
    expect(saved.text, 'Summer afternoon');
    expect(saved.photoDate, photoDate);
    expect(saved.displayDate, '2025-07-10');
    expect(saved.displayTime, '16:30');
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
    expect(cards.single.displayTime, '16:30');
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
      throwsA(isA<StateError>()),
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
    'collection rename, delete, restore, and expiry retain private media correctly',
    () async {
      final collection = await repository.createCollection('Italy trip');
      final renamed = await repository.renameCollection(
        collection.id,
        'Summer trip',
      );
      expect(renamed.name, 'Summer trip');
      final photo = File(p.join(documents.path, 'sample.jpg'));
      await photo.writeAsBytes(
        image.encodeJpg(image.Image(width: 2, height: 2)),
      );
      final card = await repository.saveCard(
        collectionId: collection.id,
        processedPhoto: photo,
        photoDate: DateTime.utc(2025),
        photoDateSource: PhotoDateSource.capture,
      );
      final deleted = await repository.softDeleteCollection(
        collection.id,
        at: DateTime.utc(2026, 1, 1),
      );
      expect(await repository.listCollections(), hasLength(1));
      expect(await repository.listDeletedCollections(), hasLength(1));
      expect(await repository.listActiveCards(collection.id), isEmpty);
      expect(await repository.photoFile(card).exists(), isTrue);
      await expectLater(
        repository.saveCard(
          collectionId: collection.id,
          processedPhoto: photo,
          photoDate: DateTime.utc(2025),
          photoDateSource: PhotoDateSource.capture,
        ),
        throwsA(isA<StateError>()),
      );
      await repository.restoreCollection(
        collection.id,
        at: deleted.purgeAt!.subtract(const Duration(milliseconds: 1)),
      );
      expect(await repository.listActiveCards(collection.id), hasLength(1));
      final deletedAgain = await repository.softDeleteCollection(
        collection.id,
        at: DateTime.utc(2026, 2, 1),
      );
      await expectLater(
        repository.restoreCollection(collection.id, at: deletedAgain.purgeAt),
        throwsA(isA<StateError>()),
      );
      expect(await repository.purgeExpired(at: deletedAgain.purgeAt), 1);
      expect(await repository.getCollection(collection.id), isNull);
      expect(await repository.getCard(card.id), isNull);
      expect(await repository.photoFile(card).exists(), isFalse);
      await expectLater(
        repository.softDeleteCollection(Collection.defaultId),
        throwsA(isA<StateError>()),
      );
    },
  );

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

  test('location can be added and removed during the edit window', () async {
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
    final added = await repository.editCard(
      id: saved.id,
      text: null,
      latitude: 52.52,
      longitude: 13.405,
      at: saved.createdAt.add(const Duration(minutes: 1)),
    );
    expect(added.latitude, 52.52);
    expect(added.longitude, 13.405);

    final removed = await repository.editCard(
      id: saved.id,
      text: null,
      removeLocation: true,
      at: saved.createdAt.add(const Duration(minutes: 2)),
    );
    expect(removed.latitude, isNull);
    expect(removed.longitude, isNull);
  });

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
