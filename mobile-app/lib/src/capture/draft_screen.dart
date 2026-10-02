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
    this.photo,
    this.photoFuture,
    this.pendingPhotoPreview,
    this.onPhotoReady,
    required this.capturedAt,
    required this.initialCollectionId,
    this.dateSource = PhotoDateSource.capture,
    this.displayDate,
    this.latitude,
    this.longitude,
  }) : assert((photo == null) != (photoFuture == null));

  final CardRepository repository;
  final Directory draftsDirectory;
  final File? photo;
  final Future<File>? photoFuture;
  final Widget? pendingPhotoPreview;
  final VoidCallback? onPhotoReady;
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
  File? _photo;
  Object? _photoError;
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
    _photo = widget.photo;
    if (widget.photoFuture != null) unawaited(_resolvePhoto());
    _latitude = widget.latitude;
    _longitude = widget.longitude;
    _collections = widget.repository.listCollections();
    _voice = VoiceDraft(PluginVoiceRecorder(), widget.draftsDirectory)
      ..addListener(_refresh);
  }

  Future<void> _resolvePhoto() async {
    File? resolved;
    try {
      resolved = await widget.photoFuture!;
      if (!mounted) {
        await resolved.delete();
        return;
      }
      await precacheImage(FileImage(resolved), context);
      if (!mounted) {
        await resolved.delete();
        return;
      }
      setState(() => _photo = resolved);
      // Keep the camera texture alive until the route and image fade finish.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onPhotoReady?.call();
    } catch (error) {
      if (resolved != null && await resolved.exists()) await resolved.delete();
      if (mounted) setState(() => _photoError = error);
    }
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
    if (_saving || _voice.isStarting || _photo == null) return;
    setState(() => _saving = true);
    try {
      if (_voice.isRecording) await _voice.release();
      await widget.repository.saveCard(
        collectionId: _collectionId,
        processedPhoto: _photo!,
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
    final photo = _photo;
    if (photo != null) {
      unawaited(photo.delete().catchError((Object _) => photo));
    }
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
                onPressed: _saving || _voice.isStarting || _photo == null
                    ? null
                    : _save,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_photo == null && _photoError == null) ...[
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(_saving ? 'Saving…' : 'Done'),
                  ],
                ),
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
                        child: widget.pendingPhotoPreview == null
                            ? Image.file(_photo!, fit: BoxFit.cover)
                            : Hero(
                                tag: 'captured-photo',
                                child: ClipRect(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: _photo != null
                                        ? Image.file(
                                            _photo!,
                                            key: ValueKey(_photo!.path),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          )
                                        : Stack(
                                            key: const ValueKey(
                                              'camera-preview',
                                            ),
                                            fit: StackFit.expand,
                                            children: [
                                              widget.pendingPhotoPreview!,
                                              if (_photoError != null)
                                                ColoredBox(
                                                  color: Colors.black54,
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Text(
                                                          'Could not take photo',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        if (_photoError
                                                            is FormatException)
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  12,
                                                                ),
                                                            child: Text(
                                                              'This photo cannot fit in 1 MB without reducing its resolution. Please retake it.',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                          ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                context,
                                                              ).pop(false),
                                                          child: const Text(
                                                            'Retake',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.displayDate ??
                                  '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
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
                        ],
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
                      if (_voice.clip == null)
                        Row(
                          children: [
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
