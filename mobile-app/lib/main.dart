import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
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
import 'src/gallery/deleted_screen.dart';
import 'src/capture/camera_screen.dart';
import 'src/capture/draft_screen.dart';
import 'src/media/import_metadata.dart';
import 'src/media/photo_processor.dart';
import 'src/export/archive_export.dart';
import 'src/export/export_actions.dart';

const _purgeTask = 'purge-expired-cards';

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
  late Future<List<MemoryCard>> _cards;
  List<Collection> _collections = [];
  String _selectedCollectionId = Collection.defaultId;
  bool _importing = false;

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
    if (mounted) _refreshCards();
  }

  Future<void> _openDetail(MemoryCard card) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardDetailScreen(
          card: card,
          repository: widget.repository,
          draftsDirectory: widget.draftsDirectory,
        ),
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

  Future<void> _importPhoto() async {
    if (_importing) return;
    setState(() => _importing = true);
    File? processed;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final metadata = await readImportMetadata(File(picked.path));
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop memory',
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
        ],
      );
      if (cropped == null) return;
      processed = await processCardPhoto(
        File(cropped.path),
        widget.draftsDirectory,
      );
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DraftScreen(
            repository: widget.repository,
            draftsDirectory: widget.draftsDirectory,
            photo: processed!,
            capturedAt: metadata.photoDate,
            dateSource: metadata.dateSource,
            displayDate: metadata.displayDate,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            initialCollectionId: _selectedCollectionId,
          ),
        ),
      );
      processed = null; // DraftScreen owns and removes its temporary photo.
      if (saved == true && mounted) _refreshCards();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import photo: $error')),
        );
      }
    } finally {
      if (processed != null && await processed.exists()) {
        await processed.delete();
      }
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportCollection() async {
    final collection = _collections
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: PopupMenuButton<String>(
        tooltip: 'Choose collection',
        onSelected: (id) {
          _selectedCollectionId = id;
          _refreshCards();
        },
        itemBuilder: (_) => [
          for (final collection in _collections)
            PopupMenuItem(value: collection.id, child: Text(collection.name)),
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
        IconButton(
          tooltip: 'Export collection',
          onPressed: _exportCollection,
          icon: const Icon(Icons.archive_outlined),
        ),
        IconButton(
          tooltip: 'Import photo',
          onPressed: _importing ? null : _importPhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
        IconButton(
          tooltip: 'New collection',
          onPressed: _createCollection,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        IconButton(
          tooltip: 'Deleted',
          onPressed: _openDeleted,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _openCamera,
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Take a photo'),
    ),
    body: FutureBuilder<List<MemoryCard>>(
      future: _cards,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load cards: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cards = snapshot.data!;
        if (cards.isEmpty) {
          return const Center(child: Text('Your memories will appear here.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 24),
              color: Colors.white,
              child: InkWell(
                onTap: () => _openDetail(card),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: Image.file(
                          widget.repository.photoFile(card),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        card.displayDate,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (card.text != null) ...[
                        const SizedBox(height: 8),
                        Text(card.text!),
                      ],
                      if (card.audioPath != null) const Icon(Icons.mic_rounded),
                      if (card.latitude != null && card.longitude != null)
                        const Icon(Icons.location_on_outlined),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
