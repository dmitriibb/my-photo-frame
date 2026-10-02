import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/main.dart';
import 'package:my_photo_frame/src/data/app_database.dart';
import 'package:my_photo_frame/src/data/card_repository.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/gallery/card_detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('location icon opens the saved coordinates in a map app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const channel = MethodChannel('my_photo_frame/maps');
    MethodCall? mapCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          mapCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    late Directory directory;
    late AppDatabase database;
    late CardRepository repository;
    late MemoryCard card;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('card_location_');
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
        photoDate: DateTime.utc(2026, 9, 27),
        photoDateSource: PhotoDateSource.capture,
        latitude: 52.52,
        longitude: 13.405,
      );
    });
    await tester.pumpWidget(
      MyPhotoFrame(
        repository: repository,
        draftsDirectory: Directory(p.join(directory.path, 'drafts')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('gallery-card-${card.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open location in a map app'));
    await tester.pump();
    expect(mapCall?.method, 'openLocation');
    expect(mapCall?.arguments, {'latitude': 52.52, 'longitude': 13.405});

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  testWidgets(
    'card opens over gallery and long press actions dismiss correctly',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late Directory directory;
      late AppDatabase database;
      late CardRepository repository;
      late MemoryCard card;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('card_modal_');
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
          photoDate: DateTime.utc(2026, 9, 27),
          photoDateSource: PhotoDateSource.capture,
          text: 'A remembered day',
        );
      });
      await tester.pumpWidget(
        MyPhotoFrame(
          repository: repository,
          draftsDirectory: Directory(p.join(directory.path, 'drafts')),
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.byKey(ValueKey('gallery-card-${card.id}'));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);

      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialog.center.dx, closeTo(200, 1));
      expect(dialog.center.dy, closeTo(450, 1));
      expect(dialog.top, greaterThan(40));
      expect(dialog.bottom, lessThan(860));
      final barrier = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .firstWhere((item) => item.color != null);
      expect(barrier.color, Colors.black.withValues(alpha: 0.8));
      expect(find.text('Memory'), findsNothing);
      expect(find.text('Export card archive'), findsNothing);

      for (final target in [
        find.byType(InteractiveViewer),
        find.text(card.displayDate).last,
        find.text('A remembered day').last,
      ]) {
        await tester.longPress(target);
        await tester.pumpAndSettle();
        expect(find.text('Export card archive'), findsOneWidget);
        expect(find.text('Export photo to gallery'), findsOneWidget);
        expect(find.text('Edit card'), findsOneWidget);
        expect(find.text('Move to Deleted'), findsOneWidget);

        await tester.tapAt(Offset(dialog.left + 20, dialog.bottom - 8));
        await tester.pumpAndSettle();
        expect(find.text('Export card archive'), findsNothing);
        expect(find.byType(CardDetailScreen), findsOneWidget);
      }

      await tester.longPressAt(Offset(dialog.left + 20, dialog.bottom - 8));
      await tester.pumpAndSettle();
      expect(find.text('Export card archive'), findsOneWidget);

      await tester.tap(find.text('Move to Deleted'));
      await tester.pumpAndSettle();
      expect(find.text('Move to Deleted?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Export card archive'), findsNothing);

      await tester.longPress(find.text('A remembered day').last);
      await tester.pumpAndSettle();
      expect(find.text('Export card archive'), findsOneWidget);

      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailScreen), findsNothing);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 860));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailScreen), findsNothing);
      expect(tile, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
    },
  );

  testWidgets('swipes follow gallery order and close past either end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late Directory directory;
    late AppDatabase database;
    late CardRepository repository;
    final cards = <MemoryCard>[];
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('card_swipe_');
      database = await AppDatabase.open(
        p.join(directory.path, 'cards.db'),
        factory: databaseFactoryFfiNoIsolate,
      );
      repository = CardRepository(database, directory);
      await repository.initialize();
      for (var day = 1; day <= 3; day++) {
        final photo = File(p.join(directory.path, 'sample_$day.jpg'));
        await photo.writeAsBytes(
          image.encodeJpg(image.Image(width: 2, height: 2)),
        );
        cards.add(
          await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2026, 9, day),
            photoDateSource: PhotoDateSource.capture,
            text: 'Card $day',
          ),
        );
      }
    });
    await tester.pumpWidget(
      MyPhotoFrame(
        repository: repository,
        draftsDirectory: Directory(p.join(directory.path, 'drafts')),
      ),
    );
    await tester.pumpAndSettle();

    Finder detailText(String text) => find.descendant(
      of: find.byType(CardDetailScreen),
      matching: find.text(text),
    );

    await tester.tap(find.byKey(ValueKey('gallery-card-${cards[1].id}')));
    await tester.pumpAndSettle();
    expect(detailText('Card 2'), findsOneWidget);

    await tester.drag(find.byType(InteractiveViewer), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(detailText('Card 1'), findsOneWidget);

    await tester.drag(detailText('Card 1'), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(detailText('Card 2'), findsOneWidget);

    await tester.drag(find.byType(InteractiveViewer), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(detailText('Card 3'), findsOneWidget);

    await tester.drag(find.byType(InteractiveViewer), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailScreen), findsNothing);

    await tester.tap(find.byKey(ValueKey('gallery-card-${cards[2].id}')));
    await tester.pumpAndSettle();
    for (final text in ['Card 2', 'Card 1']) {
      await tester.drag(find.byType(InteractiveViewer), const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(detailText(text), findsOneWidget);
    }
    await tester.drag(find.byType(InteractiveViewer), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  testWidgets('incoming cards layer correctly and grow after promotion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late Directory directory;
    late AppDatabase database;
    late CardRepository repository;
    final cards = <MemoryCard>[];
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('card_layers_');
      database = await AppDatabase.open(
        p.join(directory.path, 'cards.db'),
        factory: databaseFactoryFfiNoIsolate,
      );
      repository = CardRepository(database, directory);
      await repository.initialize();
      for (var day = 1; day <= 3; day++) {
        final photo = File(p.join(directory.path, 'sample_$day.jpg'));
        await photo.writeAsBytes(
          image.encodeJpg(image.Image(width: 2, height: 2)),
        );
        cards.add(
          await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2026, 9, day),
            photoDateSource: PhotoDateSource.capture,
            text: day == 2
                ? List.filled(80, 'A longer memory.').join(' ')
                : 'Short card $day',
          ),
        );
      }
    });
    await tester.pumpWidget(
      MyPhotoFrame(
        repository: repository,
        draftsDirectory: Directory(p.join(directory.path, 'drafts')),
      ),
    );
    await tester.pumpAndSettle();

    Finder surface(MemoryCard card) =>
        find.byKey(ValueKey('swipe-surface-${card.id}'));
    Finder surfaceMaterial(MemoryCard card) => find
        .descendant(
          of: find.descendant(of: surface(card), matching: find.byType(Dialog)),
          matching: find.byType(Material),
        )
        .first;
    List<Key?> layerOrder() => tester
        .widgetList<Stack>(
          find.descendant(
            of: find.byType(CardDetailScreen),
            matching: find.byType(Stack),
          ),
        )
        .firstWhere(
          (stack) =>
              stack.children.length == 2 &&
              stack.children.every(
                (child) =>
                    child.key is ValueKey<String> &&
                    child.key.toString().contains('swipe-surface-'),
              ),
        )
        .children
        .map((child) => child.key)
        .toList();

    await tester.tap(find.byKey(ValueKey('gallery-card-${cards[2].id}')));
    await tester.pumpAndSettle();
    final shortHeight = tester.getRect(surfaceMaterial(cards[2])).height;
    final forward = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveViewer)),
    );
    await forward.moveBy(const Offset(-160, 0));
    await tester.pump();
    expect(surface(cards[1]), findsOneWidget);
    expect(layerOrder(), [
      surface(cards[1]).evaluate().single.widget.key,
      surface(cards[2]).evaluate().single.widget.key,
    ]);
    expect(
      tester.getRect(surfaceMaterial(cards[1])).height,
      lessThanOrEqualTo(shortHeight + 1),
    );
    expect(
      tester.getRect(surfaceMaterial(cards[2])).center.dx,
      lessThan(tester.getRect(surfaceMaterial(cards[1])).center.dx),
    );
    await forward.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    await tester.pump();
    final growingHeight = tester.getRect(surfaceMaterial(cards[1])).height;
    await tester.pumpAndSettle();
    expect(surface(cards[2]), findsNothing);
    final fullHeight = tester.getRect(surfaceMaterial(cards[1])).height;
    expect(growingHeight, lessThan(fullHeight));
    expect(fullHeight, greaterThan(shortHeight));

    await tester.drag(find.byType(InteractiveViewer), const Offset(-240, 0));
    await tester.pumpAndSettle();
    final backward = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveViewer)),
    );
    await backward.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(surface(cards[1]), findsOneWidget);
    expect(layerOrder(), [
      surface(cards[0]).evaluate().single.widget.key,
      surface(cards[1]).evaluate().single.widget.key,
    ]);
    expect(
      tester.getRect(surfaceMaterial(cards[1])).height,
      lessThanOrEqualTo(tester.getRect(surfaceMaterial(cards[0])).height + 1),
    );
    expect(
      tester.getRect(surfaceMaterial(cards[1])).center.dx,
      lessThan(tester.getRect(surfaceMaterial(cards[0])).center.dx),
    );
    await backward.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    await tester.pump();
    final growingBackwardHeight = tester
        .getRect(surfaceMaterial(cards[1]))
        .height;
    await tester.pumpAndSettle();
    expect(surface(cards[0]), findsNothing);
    final fullBackwardHeight = tester.getRect(surfaceMaterial(cards[1])).height;
    expect(growingBackwardHeight, lessThan(fullBackwardHeight));
    expect(fullBackwardHeight, greaterThan(shortHeight));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
  });
}
