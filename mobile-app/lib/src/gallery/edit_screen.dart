import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/card_repository.dart';
import '../data/models.dart';
import '../media/voice_draft.dart';
import '../media/voice_playback_controls.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.card,
    required this.repository,
    required this.draftsDirectory,
  });

  final MemoryCard card;
  final CardRepository repository;
  final Directory draftsDirectory;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> with WidgetsBindingObserver {
  late final TextEditingController _text;
  late final VoiceDraft _voice;
  final GlobalKey<VoicePlaybackControlsState> _playbackKey = GlobalKey();
  Timer? _deadlineTimer;
  bool _removeExistingAudio = false;
  bool _removeLocation = false;
  bool _locating = false;
  double? _latitude;
  double? _longitude;
  bool _saving = false;

  bool get _editable =>
      DateTime.now().toUtc().isBefore(widget.card.editDeadline);

  File? get _audioForPlayback {
    if (_voice.clip != null) return _voice.clip;
    if (_removeExistingAudio) return null;
    return widget.repository.audioFile(widget.card);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text = TextEditingController(text: widget.card.text ?? '');
    _latitude = widget.card.latitude;
    _longitude = widget.card.longitude;
    _voice = VoiceDraft(PluginVoiceRecorder(), widget.draftsDirectory)
      ..addListener(_refresh);
    final remaining = widget.card.editDeadline.difference(
      DateTime.now().toUtc(),
    );
    if (remaining > Duration.zero) {
      _deadlineTimer = Timer(remaining, _refresh);
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
      final playback = _playbackKey.currentState;
      if (playback != null) unawaited(playback.stop());
      await _voice.press();
    } on MicrophonePermissionDenied {
      _message('Microphone access is needed to record a voice note.');
    } catch (error) {
      _message('Could not start recording: $error');
    }
  }

  Future<void> _removeAudio() async {
    await _playbackKey.currentState?.stop();
    await _voice.removeClip();
    setState(() => _removeExistingAudio = true);
  }

  Future<void> _addLocation() async {
    if (_locating || !_editable) return;
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
      if (mounted && _editable) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _removeLocation = false;
        });
      }
    } catch (error) {
      _message('Could not add location: $error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_editable || _saving || _voice.isStarting) return;
    setState(() => _saving = true);
    try {
      if (_voice.isRecording) await _voice.release();
      final updated = await widget.repository.editCard(
        id: widget.card.id,
        text: _text.text,
        newAudio: _voice.clip,
        removeAudio: _removeExistingAudio && _voice.clip == null,
        removeLocation: _removeLocation,
        latitude: _removeLocation ? null : _latitude,
        longitude: _removeLocation ? null : _longitude,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (error) {
      _message('Could not save changes: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadlineTimer?.cancel();
    _voice.removeListener(_refresh);
    _voice.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.card.editDeadline.toLocal();
    final audio = _audioForPlayback;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit memory')),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _editable && !_saving && !_voice.isStarting
                    ? _save
                    : null,
                child: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _editable
                    ? 'Editable until ${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}'
                    : 'The 24-hour edit window has ended.',
              ),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 1,
                child: Image.file(
                  widget.repository.photoFile(widget.card),
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.card.displayDate,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: _latitude == null
                        ? 'Add current location'
                        : 'Remove location',
                    onPressed: !_editable || _saving || _locating
                        ? null
                        : _latitude == null
                        ? _addLocation
                        : () => setState(() {
                            _latitude = null;
                            _longitude = null;
                            _removeLocation = true;
                          }),
                    icon: _locating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                enabled: _editable && !_saving,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'text',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    tooltip: 'Remove text',
                    onPressed: _editable ? _text.clear : null,
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (audio == null)
                Row(
                  children: [
                    Listener(
                      onPointerDown: _editable && !_saving
                          ? (_) => unawaited(_startVoice())
                          : null,
                      onPointerUp: _editable
                          ? (_) => unawaited(
                              _voice.release().catchError((Object error) {
                                _message('Could not finish recording: $error');
                              }),
                            )
                          : null,
                      onPointerCancel: _editable
                          ? (_) => unawaited(_voice.cancel())
                          : null,
                      child: Tooltip(
                        message: 'Hold to record voice note',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _voice.isRecording
                                ? Theme.of(context).colorScheme.errorContainer
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
              if (audio != null)
                VoicePlaybackControls(
                  key: _playbackKey,
                  file: audio,
                  onRemove: _editable ? () => unawaited(_removeAudio()) : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
