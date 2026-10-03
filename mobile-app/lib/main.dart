import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'src/data/app_database.dart';
import 'src/data/card_repository.dart';
import 'src/data/models.dart';
import 'src/gallery/card_detail_screen.dart';
import 'src/gallery/collection_grid.dart';
import 'src/gallery/deleted_screen.dart';
import 'src/gallery/gallery_grid_config.dart';
import 'src/capture/camera_screen.dart';
import 'src/capture/draft_screen.dart';
import 'src/media/import_metadata.dart';
import 'src/media/photo_processor.dart';
import 'src/export/archive_export.dart';
import 'src/export/export_actions.dart';
import 'src/export/export_paths.dart';

const _purgeTask = 'purge-expired-cards';

enum _SelectionExportAction { gallery, cards }

enum _HomeAction { importFromGallery, collection }

enum _CollectionAction { delete, zip, gallery, rename }

enum _ImportMode { automatic, manual }

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _purgeTask) return true;
    final documents = await getApplicationDocumentsDirectory();
    final database = await AppDatabase.open(
      p.join(documents.path, 'cards.db'),
      singleInstance: false,
    );
    try {
      await CardRepository(database, documents).purgeExpired();
      return true;
    } finally {
      await database.db.close();
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  final documents = await getApplicationDocumentsDirectory();
  final database = await AppDatabase.open(p.join(documents.path, 'cards.db'));
  final repository = CardRepository(database, documents);
  await repository.initialize();
  await Workmanager().initialize(backgroundTaskDispatcher);
  await Workmanager().registerPeriodicTask(
    _purgeTask,
    _purgeTask,
    frequency: const Duration(hours: 24),
  );
  final cache = await getTemporaryDirectory();
  final drafts = Directory(p.join(cache.path, 'my_photo_frame_drafts'));
  if (await drafts.exists()) await drafts.delete(recursive: true);
  await drafts.create(recursive: true);
  final exports = Directory(p.join(cache.path, 'my_photo_frame_exports'));
  if (await exports.exists()) await exports.delete(recursive: true);
  runApp(MyPhotoFrame(repository: repository, draftsDirectory: drafts));
}

class MyPhotoFrame extends StatelessWidget {
  const MyPhotoFrame({
    super.key,
    required this.repository,
    required this.draftsDirectory,
  });

  final CardRepository repository;
  final Directory draftsDirectory;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Photo Frame',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF83614B)),
      scaffoldBackgroundColor: const Color(0xFFF4F0E9),
      useMaterial3: true,
    ),
    home: HomeScreen(repository: repository, draftsDirectory: draftsDirectory),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.draftsDirectory,
  });

  final CardRepository repository;
  final Directory draftsDirectory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<MemoryCard>> _cards;
  List<Collection> _collections = [];
  String _selectedCollectionId = Collection.defaultId;
  int _galleryColumns = GalleryGridConfig.defaultColumns;
  bool _importing = false;
  bool _selectionMode = false;
  bool _exportingSelection = false;
  final Set<String> _selectedCardIds = {};

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedCardIds.clear();
    });
  }

  void _selectCard(MemoryCard card) {
    if (_exportingSelection) return;
    setState(() {
      _selectionMode = true;
      if (!_selectedCardIds.add(card.id)) _selectedCardIds.remove(card.id);
    });
  }

  Future<void> _exportSelected(_SelectionExportAction action) async {
    if (_exportingSelection || _selectedCardIds.isEmpty) return;
    final collection = _collections
        .where((item) => item.id == _selectedCollectionId)
        .firstOrNull;
    if (collection == null) return;
    final selectedIds = Set<String>.of(_selectedCardIds);
    setState(() => _exportingSelection = true);
    var exportedPhotos = 0;
    try {
      if (action == _SelectionExportAction.gallery) {
        final cards = (await widget.repository.listActiveCards(
          collection.id,
        )).where((card) => selectedIds.contains(card.id)).toList();
        if (cards.length != selectedIds.length) {
          throw StateError('Some selected cards are no longer available.');
        }
        if (!await Gal.hasAccess(toAlbum: true) &&
            !await Gal.requestAccess(toAlbum: true)) {
          throw StateError('Gallery access was denied.');
        }
        for (final card in cards) {
          final current = await widget.repository.getCard(card.id);
          if (current == null || current.deletedAt != null) {
            throw StateError('A selected card is no longer available.');
          }
          await Gal.putImage(
            widget.repository.photoFile(current).path,
            album: galleryAlbum(collection.name),
          );
          exportedPhotos++;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$exportedPhotos ${exportedPhotos == 1 ? 'photo' : 'photos'} exported to Pictures/${galleryAlbum(collection.name)}.',
              ),
            ),
          );
          _clearSelection();
        }
      } else {
        final exports = Directory(
          p.join(widget.draftsDirectory.parent.path, 'my_photo_frame_exports'),
        );
        final saved = await saveArchiveToFiles(
          () => ArchiveExport(
            widget.repository,
            exports,
          ).collection(collection, cardIds: selectedIds),
        );
        if (saved && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Cards saved as ZIP.')));
          _clearSelection();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _SelectionExportAction.gallery
                  ? 'Exported $exportedPhotos of ${selectedIds.length} photos. Could not finish: $error'
                  : 'Could not export cards: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingSelection = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cards = widget.repository.listActiveCards(Collection.defaultId);
    unawaited(_loadCollections());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  Future<void> _resume() async {
    await widget.repository.purgeExpired();
    if (mounted) _refreshCards();
  }

  Future<void> _loadCollections() async {
    final collections = await widget.repository.listCollections();
    if (mounted) setState(() => _collections = collections);
  }

  void _refreshCards() {
    setState(() {
      _cards = widget.repository.listActiveCards(_selectedCollectionId);
    });
  }

  Future<void> _createCollection() async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => enteredName = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredName),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    try {
      final collection = await widget.repository.createCollection(name);
      await _loadCollections();
      if (mounted) {
        _selectedCollectionId = collection.id;
        _refreshCards();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create collection: $error')),
        );
      }
    }
  }

  Future<void> _openDeleted() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DeletedScreen(repository: widget.repository),
      ),
    );
    if (mounted) {
      await _loadCollections();
      _refreshCards();
    }
  }

  Future<void> _openCollectionActions() async {
    final collections = await widget.repository.listCollections();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Collection'),
        children: [
          for (final collection in collections)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, collection.id),
              child: Text(collection.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '_add_new'),
            child: const Row(
              children: [Icon(Icons.add), SizedBox(width: 12), Text('Add new')],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == '_add_new') {
      await _createCollection();
      return;
    }
    final collection = collections
        .where((item) => item.id == choice)
        .firstOrNull;
    if (collection == null) return;
    final action = await showDialog<_CollectionAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(collection.name),
        children: [
          SimpleDialogOption(
            onPressed: collection.id == Collection.defaultId
                ? null
                : () => Navigator.pop(dialogContext, _CollectionAction.delete),
            child: Text(
              'Delete',
              style: TextStyle(
                color: collection.id == Collection.defaultId
                    ? Theme.of(context).disabledColor
                    : null,
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _CollectionAction.zip),
            child: const Text('Export to ZIP'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _CollectionAction.gallery),
            child: const Text('Export to gallery'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _CollectionAction.rename),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _CollectionAction.delete:
        await _deleteCollection(collection);
      case _CollectionAction.zip:
        await _exportCollection(collection);
      case _CollectionAction.gallery:
        await _exportCollectionToGallery(collection);
      case _CollectionAction.rename:
        await _renameCollection(collection);
    }
  }

  Future<void> _deleteCollection(Collection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${collection.name}?'),
        content: const Text(
          'The collection and its cards will move to Deleted. You can restore them for 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.softDeleteCollection(collection.id);
      if (!mounted) return;
      if (_selectedCollectionId == collection.id) {
        _selectedCollectionId = Collection.defaultId;
      }
      await _loadCollections();
      if (!mounted) return;
      _refreshCards();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection moved to Deleted.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete collection: $error')),
        );
      }
    }
  }

  Future<void> _renameCollection(Collection collection) async {
    var name = collection.name;
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename collection'),
        content: TextFormField(
          initialValue: collection.name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => name = value,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    try {
      await widget.repository.renameCollection(collection.id, entered);
      if (mounted) await _loadCollections();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not rename collection: $error')),
        );
      }
    }
  }

  Future<void> _exportCollectionToGallery(Collection collection) async {
    var exported = 0;
    try {
      final activeCollection = await widget.repository.getCollection(
        collection.id,
      );
      if (activeCollection == null || activeCollection.deletedAt != null) {
        throw StateError('This collection is no longer available.');
      }
      final cards = await widget.repository.listActiveCards(collection.id);
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        throw StateError('Gallery access was denied.');
      }
      for (final card in cards) {
        final currentCollection = await widget.repository.getCollection(
          collection.id,
        );
        if (currentCollection == null || currentCollection.deletedAt != null) {
          throw StateError('This collection is no longer available.');
        }
        final current = await widget.repository.getCard(card.id);
        if (current == null || current.deletedAt != null) {
          throw StateError('A card is no longer available.');
        }
        await Gal.putImage(
          widget.repository.photoFile(current).path,
          album: galleryAlbum(collection.name),
        );
        exported++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$exported ${exported == 1 ? 'photo' : 'photos'} exported to gallery.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported $exported photos. Could not finish: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openDetail(MemoryCard card, List<MemoryCard> cards) async {
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => CardDetailScreen(
        card: card,
        cards: cards,
        repository: widget.repository,
        draftsDirectory: widget.draftsDirectory,
      ),
    );
    if (mounted) _refreshCards();
  }

  Future<void> _openCamera() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          repository: widget.repository,
          draftsDirectory: widget.draftsDirectory,
          initialCollectionId: _selectedCollectionId,
        ),
      ),
    );
    if (saved == true && mounted) _refreshCards();
  }

  Future<String?> _chooseImportCollection() async {
    final collections = await widget.repository.listCollections();
    if (!mounted) return null;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Import to collection'),
        children: [
          for (final collection in collections)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, collection.id),
              child: Text(collection.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '_new'),
            child: const Row(
              children: [
                Icon(Icons.add),
                SizedBox(width: 12),
                Text('New collection'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice != '_new' || !mounted) return choice;
    var name = '';
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => name = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return null;
    final collection = await widget.repository.createCollection(entered);
    await _loadCollections();
    return collection.id;
  }

  Future<_ImportMode?> _chooseImportMode() => showDialog<_ImportMode>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Import'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, _ImportMode.automatic),
          child: const Text('Auto'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, _ImportMode.manual),
          child: const Text('Manual'),
        ),
      ],
    ),
  );

  Future<void> _importPhoto() async {
    if (_importing) return;
    setState(() => _importing = true);
    var savedCount = 0;
    var failedCount = 0;
    String? destinationId;
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty || !mounted) return;
      final collectionId = await _chooseImportCollection();
      if (collectionId == null || !mounted) return;
      destinationId = collectionId;
      final mode = await _chooseImportMode();
      if (mode == null || !mounted) return;
      for (var index = 0; index < picked.length; index++) {
        if (!mounted) break;
        final original = File(picked[index].path);
        File? processed;
        try {
          final metadata = await readImportMetadata(original);
          processed = await processCardPhoto(original, widget.draftsDirectory);
          if (mode == _ImportMode.automatic) {
            await widget.repository.saveCard(
              collectionId: collectionId,
              processedPhoto: processed,
              photoDate: metadata.photoDate,
              photoDateSource: metadata.dateSource,
              displayDate: metadata.displayDate,
              displayTime: metadata.displayTime,
              latitude: metadata.latitude,
              longitude: metadata.longitude,
            );
            savedCount++;
          } else {
            if (!mounted) break;
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => DraftScreen(
                  repository: widget.repository,
                  draftsDirectory: widget.draftsDirectory,
                  photo: processed,
                  originalImportPhoto: original,
                  importProgress: '${index + 1}/${picked.length}',
                  capturedAt: metadata.photoDate,
                  dateSource: metadata.dateSource,
                  displayDate: metadata.displayDate,
                  displayTime: metadata.displayTime,
                  latitude: metadata.latitude,
                  longitude: metadata.longitude,
                  initialCollectionId: collectionId,
                ),
              ),
            );
            processed = null; // DraftScreen owns the processed photo.
            if (saved != true) break;
            savedCount++;
          }
        } catch (_) {
          failedCount++;
        } finally {
          if (processed != null && await processed.exists()) {
            await processed.delete();
          }
        }
      }
      if (mounted && (savedCount > 0 || failedCount > 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failedCount == 0
                  ? '$savedCount ${savedCount == 1 ? 'photo' : 'photos'} imported.'
                  : '$savedCount imported, $failedCount could not be imported.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported $savedCount photos. Could not finish: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        if (savedCount > 0 && destinationId != null) {
          _selectedCollectionId = destinationId;
        }
        _refreshCards();
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _exportCollection([Collection? chosen]) async {
    final collection =
        chosen ??
        _collections
            .where((item) => item.id == _selectedCollectionId)
            .firstOrNull;
    if (collection == null) return;
    final exports = Directory(
      p.join(widget.draftsDirectory.parent.path, 'my_photo_frame_exports'),
    );
    await showArchiveExportOptions(
      context,
      () => ArchiveExport(widget.repository, exports).collection(collection),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_selectionMode,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _selectionMode) _clearSelection();
    },
    child: Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: !_selectionMode,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                child: Text(
                  'My Photo Frame',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                selected: true,
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Import'),
                onTap: _importing
                    ? null
                    : () {
                        Navigator.pop(context);
                        _importPhoto();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Export'),
                onTap: () {
                  Navigator.pop(context);
                  _exportCollection();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Deleted'),
                onTap: () {
                  Navigator.pop(context);
                  _openDeleted();
                },
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Info'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const InfoScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: IconButton(
          tooltip: _selectionMode ? 'Cancel selection' : 'Menu',
          onPressed: _selectionMode
              ? _clearSelection
              : () => _scaffoldKey.currentState?.openDrawer(),
          icon: Icon(_selectionMode ? Icons.arrow_back : Icons.menu),
        ),
        title: _selectionMode
            ? Text('${_selectedCardIds.length} selected')
            : PopupMenuButton<String>(
                tooltip: 'Choose collection',
                onSelected: (id) {
                  if (id == '_add_new') {
                    _createCollection();
                    return;
                  }
                  _selectedCollectionId = id;
                  _refreshCards();
                },
                itemBuilder: (_) => [
                  for (final collection in _collections)
                    PopupMenuItem(
                      value: collection.id,
                      child: Text(collection.name),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: '_add_new',
                    child: Row(
                      children: [
                        Icon(Icons.add),
                        SizedBox(width: 12),
                        Text('Add new'),
                      ],
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _collections
                              .where((c) => c.id == _selectedCollectionId)
                              .firstOrNull
                              ?.name ??
                          'Default',
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
        actions: [
          if (_exportingSelection)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_importing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_selectionMode)
            PopupMenuButton<_SelectionExportAction>(
              tooltip: 'Selection actions',
              onSelected: _exportSelected,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _SelectionExportAction.gallery,
                  enabled: _selectedCardIds.isNotEmpty,
                  child: const Text('Export to gallery'),
                ),
                PopupMenuItem(
                  value: _SelectionExportAction.cards,
                  enabled: _selectedCardIds.isNotEmpty,
                  child: const Text('Export as cards'),
                ),
              ],
            )
          else
            PopupMenuButton<_HomeAction>(
              tooltip: 'Actions',
              enabled: !_importing,
              onSelected: (action) {
                if (action == _HomeAction.importFromGallery) _importPhoto();
                if (action == _HomeAction.collection) _openCollectionActions();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HomeAction.importFromGallery,
                  child: Text('Import from gallery'),
                ),
                PopupMenuItem(
                  value: _HomeAction.collection,
                  child: Text('Collection'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selectionMode || _exportingSelection || _importing
          ? null
          : FloatingActionButton(
              tooltip: 'Take a photo',
              onPressed: _openCamera,
              child: const Icon(Icons.camera_alt_outlined),
            ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<MemoryCard>>(
          future: _cards,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Could not load cards: ${snapshot.error}'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final cards = snapshot.data!;
            if (cards.isEmpty) {
              return const Center(
                child: Text('Your memories will appear here.'),
              );
            }
            return CollectionGrid(
              cards: cards,
              columns: _galleryColumns,
              onColumnsChanged: (columns) =>
                  setState(() => _galleryColumns = columns),
              photoFile: widget.repository.photoFile,
              selectionMode: _selectionMode,
              selectedCardIds: _selectedCardIds,
              onCardLongPress: _selectCard,
              onCardTap: (card) {
                if (_exportingSelection) return;
                if (_selectionMode) {
                  _selectCard(card);
                } else {
                  _openDetail(card, cards);
                }
              },
            );
          },
        ),
      ),
    ),
  );
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Info')),
    body: const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Photo Frame', style: TextStyle(fontSize: 24)),
          SizedBox(height: 16),
          Text(
            'Keep your favorite moments as photo cards with optional text and voice notes.',
          ),
          SizedBox(height: 12),
          Text(
            'Your cards stay on this device until you choose to export them.',
          ),
        ],
      ),
    ),
  );
}
