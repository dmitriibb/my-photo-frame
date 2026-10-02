import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/gallery/collection_grid.dart';
import 'package:my_photo_frame/src/gallery/gallery_grid_config.dart';

void main() {
  test('column ranges select the configured tile modes', () {
    expect(GalleryGridConfig.defaultColumns, 3);
    expect(GalleryGridConfig.minColumns, 1);
    expect(GalleryGridConfig.maxColumns, 10);
    for (final columns in [1, 2, 3]) {
      expect(GalleryGridConfig.forColumns(columns).mode, GalleryTileMode.big);
    }
    for (final columns in [4, 5, 6]) {
      expect(
        GalleryGridConfig.forColumns(columns).mode,
        GalleryTileMode.medium,
      );
    }
    for (final columns in [7, 8, 9, 10]) {
      expect(GalleryGridConfig.forColumns(columns).mode, GalleryTileMode.small);
    }
  });

  testWidgets(
    'card content changes with grid size and tapping still opens it',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('gallery_grid_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/sample.jpg')
        ..writeAsBytesSync(image.encodeJpg(image.Image(width: 2, height: 2)));
      final card = _card(photo.path);
      var opened = false;

      Future<void> show(int columns) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CollectionGrid(
                cards: [card],
                columns: columns,
                onColumnsChanged: (_) {},
                photoFile: (_) => photo,
                onCardTap: (_) => opened = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(3);
      expect(find.text('2026-09-27'), findsOneWidget);
      expect(find.text('A remembered day'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);

      await show(4);
      expect(find.text('2026-09-27'), findsOneWidget);
      expect(find.text('A remembered day'), findsNothing);
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);

      await show(6);
      expect(find.text('2026-\n09-27'), findsOneWidget);

      await show(7);
      expect(find.text('2026-09-27'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gallery-card-one')));
      expect(opened, isTrue);
    },
  );

  testWidgets('pinching out reduces the number of columns', (tester) async {
    var columns = GalleryGridConfig.defaultColumns;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CollectionGrid(
              cards: [_card('unused.jpg')],
              columns: columns,
              onColumnsChanged: (value) => setState(() => columns = value),
              photoFile: (_) => File('unused.jpg'),
              onCardTap: (_) {},
            ),
          ),
        ),
      ),
    );

    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(const Offset(350, 300));
    await second.down(const Offset(450, 300));
    await tester.pump();
    await first.moveTo(const Offset(250, 300));
    await second.moveTo(const Offset(550, 300));
    await tester.pump();
    await first.moveTo(const Offset(150, 300));
    await second.moveTo(const Offset(650, 300));
    await tester.pump();
    expect(columns, 1);
    await first.up();
    await second.up();
  });

  testWidgets('selection circles work in full, medium, and compact grids', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gallery_selection_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final photo = File('${directory.path}/sample.jpg')
      ..writeAsBytesSync(image.encodeJpg(image.Image(width: 2, height: 2)));
    var toggled = false;
    var longPressed = false;
    for (final columns in [3, 6, 10]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionGrid(
              cards: [_card(photo.path)],
              columns: columns,
              onColumnsChanged: (_) {},
              photoFile: (_) => photo,
              onCardTap: (_) => toggled = true,
              onCardLongPress: (_) => longPressed = true,
              selectionMode: true,
              selectedCardIds: const {'one'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      toggled = false;
      longPressed = false;
      await tester.tap(find.byKey(const ValueKey('gallery-select-one')));
      expect(toggled, isTrue);
      // Press outside the circle to exercise the card gesture at every density.
      final tile = tester.getRect(
        find.byKey(const ValueKey('gallery-card-one')),
      );
      await tester.longPressAt(
        Offset(tile.left + tile.width / 4, tile.top + tile.height / 2),
      );
      expect(longPressed, isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('pinching in increases columns up to the maximum', (
    tester,
  ) async {
    var columns = GalleryGridConfig.defaultColumns;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CollectionGrid(
              cards: [_card('unused.jpg')],
              columns: columns,
              onColumnsChanged: (value) => setState(() => columns = value),
              photoFile: (_) => File('unused.jpg'),
              onCardTap: (_) {},
            ),
          ),
        ),
      ),
    );

    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);
    await first.down(const Offset(150, 300));
    await second.down(const Offset(650, 300));
    await tester.pump();
    await first.moveTo(const Offset(250, 300));
    await second.moveTo(const Offset(550, 300));
    await tester.pump();
    await first.moveTo(const Offset(350, 300));
    await second.moveTo(const Offset(450, 300));
    await tester.pump();
    expect(columns, 10);
    await first.up();
    await second.up();
  });

  testWidgets(
    'changing tile modes keeps the gallery near its scroll position',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('gallery_scroll_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/sample.jpg')
        ..writeAsBytesSync(image.encodeJpg(image.Image(width: 2, height: 2)));
      final cards = [
        for (var index = 0; index < 40; index++)
          _card(photo.path, id: '$index'),
      ];
      var columns = 3;
      late StateSetter changeColumns;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                changeColumns = setState;
                return CollectionGrid(
                  cards: cards,
                  columns: columns,
                  onColumnsChanged: (value) => setState(() => columns = value),
                  photoFile: (_) => photo,
                  onCardTap: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(before, greaterThan(0));

      changeColumns(() => columns = 4);
      await tester.pumpAndSettle();
      final after = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(after, greaterThan(0));
    },
  );
}

MemoryCard _card(String path, {String id = 'one'}) => MemoryCard(
  id: id,
  collectionId: Collection.defaultId,
  photoDate: DateTime.utc(2026, 9, 27),
  displayDate: '2026-09-27',
  photoDateSource: PhotoDateSource.capture,
  createdAt: DateTime.utc(2026, 9, 27),
  updatedAt: DateTime.utc(2026, 9, 27),
  photoPath: path,
  text: 'A remembered day',
  audioPath: 'audio.m4a',
  latitude: 52.5,
  longitude: 13.4,
);
