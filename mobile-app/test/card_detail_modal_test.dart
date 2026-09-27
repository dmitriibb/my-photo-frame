import 'dart:io';

import 'package:flutter/material.dart';
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
}
