import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';

import '../data/card_repository.dart';
import '../data/models.dart';
import '../media/voice_draft.dart';

class DraftScreen extends StatefulWidget {
  const DraftScreen({
    super.key,
    required this.repository,
    required this.draftsDirectory,
    required this.photo,
    required this.capturedAt,
    required this.initialCollectionId,
    this.dateSource = PhotoDateSource.capture,
    this.displayDate,
    this.latitude,
    this.longitude,
  });

  final CardRepository repository;
  final Directory draftsDirectory;
  final File photo;
  final DateTime capturedAt;
  final String initialCollectionId;
  final PhotoDateSource dateSource;
  final String? displayDate;
  final double? latitude;
  final double? longitude;

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  late final VoiceDraft _voice;
  StreamSubscription<PlayerState>? _playerSubscription;
  bool _saving = false;
  bool _playing = false;
  bool _includeLocation = true;
  bool _locating = false;
  double? _latitude;
  double? _longitude;
  late String _collectionId;
  late Future<List<Collection>> _collections;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _collectionId = widget.initialCollectionId;
    _latitude = widget.latitude;
    _longitude = widget.longitude;
    _collections = widget.repository.listCollections();
    _voice = VoiceDraft(PluginVoiceRecorder(), widget.draftsDirectory)
      ..addListener(_refresh);
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(
          () => _playing =
              state.playing &&
              state.processingState != ProcessingState.completed,
        );
      }
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_voice.cancel());
      unawaited(_player.pause());
    }
  }

  Future<void> _startVoice() async {
    try {
      unawaited(_player.stop().catchError((Object _) {}));
      await _voice.press();
    } on MicrophonePermissionDenied {
      _message('Microphone access is needed to record a voice note.');
    } catch (error) {
      _message('Could not start recording: $error');
    }
  }

  Future<void> _finishVoice() async {
    try {
      await _voice.release();
    } catch (error) {
      _message('Could not finish recording: $error');
    }
  }

  Future<void> _cancelVoice() async {
    try {
      await _voice.cancel();
    } catch (error) {
      _message('Could not cancel recording: $error');
    }
  }

  Future<void> _playVoice() async {
    final clip = _voice.clip;
    if (clip == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.setFilePath(clip.path);
        unawaited(_player.play());
      }
    } catch (error) {
      _message('Could not play recording: $error');
    }
  }

  Future<void> _removeVoice() async {
    await _player.stop();
    await _voice.removeClip();
  }

  Future<void> _addLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Location services are off.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was denied.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _includeLocation = true;
        });
      }
    } catch (error) {
      _message('Could not add location: $error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _voice.isStarting) return;
    setState(() => _saving = true);
    try {
      if (_voice.isRecording) await _voice.release();
      await widget.repository.saveCard(
        collectionId: _collectionId,
        processedPhoto: widget.photo,
        photoDate: widget.capturedAt,
        photoDateSource: widget.dateSource,
        displayDate: widget.displayDate,
        text: _text.text,
        recordedAudio: _voice.clip,
        latitude: _includeLocation ? _latitude : null,
        longitude: _includeLocation ? _longitude : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _message('Could not save card: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_refresh);
    _voice.dispose();
    _text.dispose();
    unawaited(_playerSubscription?.cancel());
    unawaited(_player.dispose());
    unawaited(widget.photo.delete().catchError((Object _) => widget.photo));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.capturedAt;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New memory'),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
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
                      child: Image.file(widget.photo, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.displayDate ??
                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_latitude != null && _longitude != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include photo location'),
                        value: _includeLocation,
                        onChanged: (value) =>
                            setState(() => _includeLocation = value),
                      ),
                    if (_latitude == null &&
                        widget.dateSource == PhotoDateSource.capture)
                      TextButton.icon(
                        onPressed: _locating ? null : _addLocation,
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: Text(
                          _locating
                              ? 'Getting location…'
                              : 'Add current location',
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _text,
                      maxLines: 4,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Short description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Listener(
                          onPointerDown: (_) => unawaited(_startVoice()),
                          onPointerUp: (_) => unawaited(_finishVoice()),
                          onPointerCancel: (_) => unawaited(_cancelVoice()),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _voice.isRecording
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _voice.isRecording ? Icons.mic : Icons.mic_none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _voice.isRecording
                                ? 'Recording ${_voice.elapsedSeconds}s / 60s'
                                : _voice.isStarting
                                ? 'Starting microphone…'
                                : 'Hold microphone to record (max 60s)',
                          ),
                        ),
                      ],
                    ),
                    if (_voice.clip != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            tooltip: _playing
                                ? 'Pause voice note'
                                : 'Play voice note',
                            onPressed: _playVoice,
                            icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          const Expanded(child: Text('Voice note ready')),
                          IconButton(
                            tooltip: 'Remove voice note',
                            onPressed: _removeVoice,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Collection>>(
              future: _collections,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return DropdownButtonFormField<String>(
                  initialValue: _collectionId,
                  decoration: const InputDecoration(
                    labelText: 'Collection',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final collection in snapshot.data!)
                      DropdownMenuItem(
                        value: collection.id,
                        child: Text(collection.name),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) setState(() => _collectionId = id);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving || _voice.isStarting ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}
