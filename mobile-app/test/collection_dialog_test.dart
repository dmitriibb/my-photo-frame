import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/main.dart';
import 'package:my_photo_frame/src/data/app_database.dart';
import 'package:my_photo_frame/src/data/card_repository.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/gallery/deleted_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('creating a collection closes the dialog and selects it', (
    tester,
  ) async {
    late Directory directory;
    late AppDatabase database;
    late CardRepository repository;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('collection_dialog_');
      database = await AppDatabase.open(
        p.join(directory.path, 'cards.db'),
        factory: databaseFactoryFfiNoIsolate,
      );
      repository = CardRepository(database, directory);
      await repository.initialize();
    });

    await tester.pumpWidget(
      MyPhotoFrame(
        repository: repository,
        draftsDirectory: Directory(p.join(directory.path, 'drafts')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose collection'));
    await tester.pumpAndSettle();
    expect(find.text('Add new'), findsOneWidget);
    await tester.tap(find.text('Add new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Italy trip');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Italy trip'), findsOneWidget);
    expect(await tester.runAsync(repository.listCollections), hasLength(2));

    final cameraButton = find.byType(FloatingActionButton);
    expect(cameraButton, findsOneWidget);
    expect(find.text('Take a photo'), findsNothing);
    final buttonCenter = tester.getCenter(cameraButton);
    expect(
      buttonCenter.dx,
      closeTo(tester.getSize(find.byType(Scaffold).first).width / 2, 1),
    );

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(find.text('Add new'), findsOneWidget);
    await tester.tap(find.text('Italy trip').last);
    await tester.pumpAndSettle();
    for (final action in [
      'Delete',
      'Export to ZIP',
      'Export to gallery',
      'Rename',
    ]) {
      expect(find.text(action), findsOneWidget);
    }
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Summer trip');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Summer trip'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    for (final item in ['Home', 'Import', 'Export', 'Deleted', 'Info']) {
      expect(find.text(item), findsOneWidget);
    }
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your cards stay on this device'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  testWidgets('restoring a card refreshes Deleted without a framework error', (
    tester,
  ) async {
    late Directory directory;
    late AppDatabase database;
    late CardRepository repository;
    late MemoryCard card;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('deleted_screen_');
      database = await AppDatabase.open(
        p.join(directory.path, 'cards.db'),
        factory: databaseFactoryFfiNoIsolate,
      );
      repository = CardRepository(database, directory);
      await repository.initialize();
      final photo = File(p.join(directory.path, 'sample.jpg'));
      await photo.writeAsBytes(
        image.encodeJpg(image.Image(width: 2, height: 2)),
      );
      card = await repository.saveCard(
        collectionId: Collection.defaultId,
        processedPhoto: photo,
        photoDate: DateTime.utc(2025),
        photoDateSource: PhotoDateSource.capture,
      );
      await repository.softDeleteCard(card.id);
    });

    await tester.pumpWidget(
      MaterialApp(home: DeletedScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20; attempt++) {
        if ((await repository.getCard(card.id))?.deletedAt == null) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No deleted cards or collections.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });
}
