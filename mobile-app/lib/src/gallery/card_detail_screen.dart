import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';

import '../data/card_repository.dart';
import '../data/models.dart';
import '../export/archive_export.dart';
import '../export/export_actions.dart';
import 'edit_screen.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({
    super.key,
    required this.card,
    required this.repository,
    required this.draftsDirectory,
  });

  final MemoryCard card;
  final CardRepository repository;
  final Directory draftsDirectory;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _subscription;
  bool _playing = false;
  bool _exportingPhoto = false;
  late MemoryCard _card;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _subscription = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(
          () => _playing =
              state.playing &&
              state.processingState != ProcessingState.completed,
        );
      }
    });
  }

  Future<void> _toggleAudio() async {
    final file = widget.repository.audioFile(_card);
    if (file == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.setFilePath(file.path);
        unawaited(_player.play());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play voice note: $error')),
        );
      }
    }
  }

  Future<void> _edit() async {
    await _player.stop();
    if (!mounted) return;
    final updated = await Navigator.of(context).push<MemoryCard>(
      MaterialPageRoute(
        builder: (_) => EditScreen(
          card: _card,
          repository: widget.repository,
          draftsDirectory: widget.draftsDirectory,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _card = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to Deleted?'),
        content: const Text('You can restore this card for 30 days.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _player.stop();
      await widget.repository.softDeleteCard(_card.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete card: $error')),
        );
      }
    }
  }

  Future<void> _exportPhoto() async {
    if (_exportingPhoto) return;
    setState(() => _exportingPhoto = true);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw StateError('Gallery access was denied.');
      }
      await Gal.putImage(widget.repository.photoFile(_card).path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo exported to gallery.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPhoto = false);
    }
  }

  Future<void> _exportCard() async {
    final exports = Directory(
      p.join(widget.draftsDirectory.parent.path, 'my_photo_frame_exports'),
    );
    await showArchiveExportOptions(
      context,
      () => ArchiveExport(widget.repository, exports).card(_card),
    );
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Memory'),
      actions: [
        IconButton(
          tooltip: 'Export card archive',
          onPressed: _exportCard,
          icon: const Icon(Icons.archive_outlined),
        ),
        IconButton(
          tooltip: 'Export photo to gallery',
          onPressed: _exportingPhoto ? null : _exportPhoto,
          icon: const Icon(Icons.save_alt_outlined),
        ),
        if (DateTime.now().toUtc().isBefore(_card.editDeadline))
          IconButton(
            tooltip: 'Edit card',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        IconButton(
          tooltip: 'Move to Deleted',
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    child: Image.file(
                      widget.repository.photoFile(_card),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _card.displayDate,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_card.text != null) ...[
                  const SizedBox(height: 12),
                  Text(_card.text!),
                ],
                if (_card.audioPath != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _toggleAudio,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      _playing ? 'Pause voice note' : 'Play voice note',
                    ),
                  ),
                ],
                if (_card.latitude != null && _card.longitude != null)
                  const Icon(Icons.location_on_outlined),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
