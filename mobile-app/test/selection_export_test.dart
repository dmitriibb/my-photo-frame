import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:my_photo_frame/main.dart';
import 'package:my_photo_frame/src/data/app_database.dart';
import 'package:my_photo_frame/src/data/card_repository.dart';
import 'package:my_photo_frame/src/data/models.dart';
import 'package:my_photo_frame/src/export/export_paths.dart';
import 'package:my_photo_frame/src/gallery/card_detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('collection folder names cannot create extra path components', () {
    expect(galleryAlbum('Italy trip'), 'my-photo-frame/Italy trip');
    expect(exportCollectionName('../trip\\summer:*?'), '_trip_summer___');
    expect(exportCollectionName('...'), 'Collection');
    expect(exportCollectionName('  夏休み  '), '夏休み');
    expect(exportCollectionName('a' * 100), hasLength(80));
  });

  testWidgets('long press, circle toggles, empty selection, and Back', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.show(tester);
    final first = fixture.cards.first.id;
    final second = fixture.cards.last.id;
    await tester.longPress(find.byKey(ValueKey('gallery-card-$first')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(ValueKey('gallery-select-$first')), findsOneWidget);
    expect(find.byKey(ValueKey('gallery-select-$second')), findsOneWidget);
    expect(find.byType(CardDetailScreen), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byKey(ValueKey('gallery-select-$second')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('gallery-select-$first')));
    await tester.tap(find.byKey(ValueKey('gallery-select-$second')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Selection actions'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem>(
            find.ancestor(
              of: find.text('Export to gallery'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuItem>(
            find.ancestor(
              of: find.text('Export as cards'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.binding.handlePopRoute(); // Close the action menu first.
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsNothing);
    expect(find.byTooltip('Selection actions'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.longPress(find.byKey(ValueKey('gallery-card-$first')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('gallery-select-$first')), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets(
    'gallery export sends only selected photos into collection album',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gal'),
        (call) async {
          calls.add(call);
          return call.method == 'putImage' ? null : true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('gal'),
          null,
        ),
      );
      await fixture.show(tester);
      await tester.longPress(
        find.byKey(ValueKey('gallery-card-${fixture.cards.first.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selection actions'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Export to gallery'));
        for (
          var i = 0;
          i < 100 && !calls.any((call) => call.method == 'putImage');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      final exported = calls
          .where((call) => call.method == 'putImage')
          .toList();
      expect(exported, hasLength(1));
      expect(
        exported.single.arguments['path'],
        fixture.repository.photoFile(fixture.cards.first).path,
      );
      expect(exported.single.arguments['album'], 'my-photo-frame/Default');
      expect(find.textContaining('1 photo exported'), findsOneWidget);
      expect(find.byTooltip('Selection actions'), findsNothing);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'card export opens save picker directly, cancellation retains selection',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final original = FilePickerPlatform.instance;
      final picker = _SavePicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = original);
      await fixture.show(tester);
      await tester.longPress(
        find.byKey(ValueKey('gallery-card-${fixture.cards.first.id}')),
      );
      await tester.pumpAndSettle();

      Future<void> export() async {
        await tester.tap(find.byTooltip('Selection actions'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Export as cards'));
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            final exports = Directory(
              p.join(fixture.directory.path, 'my_photo_frame_exports'),
            );
            if (picker.bytes != null &&
                await exports.exists() &&
                await exports.list().isEmpty) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(picker.bytes, isNotNull);
        await tester.pumpAndSettle();
      }

      await export();
      expect(picker.fileName, 'Default-selected-cards.zip');
      expect(picker.mimeType, 'application/zip');
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Save to Files'), findsNothing);
      final zip = ZipDecoder().decodeBytes(picker.bytes!);
      final manifest =
          jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content))
              as Map<String, dynamic>;
      expect((manifest['cards'] as List).single['id'], fixture.cards.first.id);
      expect(zip.findFile('cards/${fixture.cards.last.id}.zip'), isNull);

      picker.result = Uri.parse('content://documents/selected.zip');
      picker.bytes = null;
      await export();
      expect(find.text('Cards saved as ZIP.'), findsOneWidget);
      expect(find.byTooltip('Selection actions'), findsNothing);
      await fixture.dispose(tester);
    },
  );
}

class _Fixture {
  _Fixture(this.directory, this.database, this.repository, this.cards);
  final Directory directory;
  final AppDatabase database;
  final CardRepository repository;
  final List<MemoryCard> cards;

  static Future<_Fixture> create(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'selection_export_',
      );
      final database = await AppDatabase.open(
        p.join(directory.path, 'cards.db'),
        factory: databaseFactoryFfiNoIsolate,
      );
      final repository = CardRepository(database, directory);
      await repository.initialize();
      final photo = File(p.join(directory.path, 'sample.jpg'));
      await photo.writeAsBytes(
        image.encodeJpg(image.Image(width: 2, height: 2)),
      );
      final cards = <MemoryCard>[];
      for (var i = 0; i < 2; i++) {
        cards.add(
          await repository.saveCard(
            collectionId: Collection.defaultId,
            processedPhoto: photo,
            photoDate: DateTime.utc(2025, 1, i + 1),
            photoDateSource: PhotoDateSource.capture,
          ),
        );
      }
      return _Fixture(directory, database, repository, cards);
    }))!;
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MyPhotoFrame(
        repository: repository,
        draftsDirectory: Directory(p.join(directory.path, 'drafts')),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(database.close);
    for (var attempt = 0; attempt < 10; attempt++) {
      final deleted = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          await directory.delete(recursive: true);
          return true;
        } on PathAccessException {
          if (attempt == 9) rethrow;
          return false;
        }
      });
      if (deleted == true) break;
      await tester.pump();
    }
  }
}

class _SavePicker extends FilePickerPlatform {
  Uint8List? bytes;
  String? fileName;
  String? mimeType;
  Uri? result;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.bytes = bytes;
    this.fileName = fileName;
    this.mimeType = mimeType;
    return result;
  }
}
