import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/card_repository.dart';
import '../data/models.dart';
import '../media/voice_draft.dart';
import '../media/voice_playback_controls.dart';

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
  final GlobalKey<VoicePlaybackControlsState> _playbackKey = GlobalKey();
  late final VoiceDraft _voice;
  bool _saving = false;
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
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_voice.cancel());
    }
  }

  Future<void> _startVoice() async {
    try {
      unawaited(_playbackKey.currentState?.stop());
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

  Future<void> _removeVoice() async {
    await _playbackKey.currentState?.stop();
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
        latitude: _latitude,
        longitude: _longitude,
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving || _voice.isStarting ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Done'),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
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
                      const SizedBox(height: 8),
                      TextField(
                        controller: _text,
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'text',
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            tooltip: _latitude == null
                                ? 'Add current location'
                                : 'Remove location',
                            onPressed: _locating
                                ? null
                                : _latitude == null
                                ? _addLocation
                                : () => setState(() {
                                    _latitude = null;
                                    _longitude = null;
                                  }),
                            icon: _locating
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _latitude == null
                                        ? Icons.location_off_outlined
                                        : Icons.location_on,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Listener(
                            onPointerDown: (_) => unawaited(_startVoice()),
                            onPointerUp: (_) => unawaited(_finishVoice()),
                            onPointerCancel: (_) => unawaited(_cancelVoice()),
                            child: Tooltip(
                              message: 'Hold to record voice note',
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _voice.isRecording
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.errorContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.mic),
                              ),
                            ),
                          ),
                          if (_voice.isRecording || _voice.isStarting) ...[
                            const SizedBox(width: 12),
                            Text(
                              _voice.isRecording
                                  ? 'Recording ${_voice.elapsedSeconds}s / 60s'
                                  : 'Starting microphone…',
                            ),
                          ],
                        ],
                      ),
                      if (_voice.clip != null)
                        VoicePlaybackControls(
                          key: _playbackKey,
                          file: _voice.clip!,
                          onRemove: () => unawaited(_removeVoice()),
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}
