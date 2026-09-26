import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../data/card_repository.dart';
import '../data/models.dart';
import '../media/voice_draft.dart';

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
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _deadlineTimer;
  bool _playing = false;
  bool _removeExistingAudio = false;
  bool _removeLocation = false;
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

  Future<void> _playVoice() async {
    final file = _audioForPlayback;
    if (file == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.setFilePath(file.path);
        unawaited(_player.play());
      }
    } catch (error) {
      _message('Could not play voice note: $error');
    }
  }

  Future<void> _removeAudio() async {
    await _player.stop();
    await _voice.removeClip();
    setState(() => _removeExistingAudio = true);
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
    final subscription = _playerSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_player.dispose());
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
        body: ListView(
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
            Text(widget.card.displayDate),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              enabled: _editable && !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Short description (optional)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Remove text',
                  onPressed: _editable ? _text.clear : null,
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _voice.isRecording
                          ? Theme.of(context).colorScheme.errorContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_none),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _voice.isRecording
                        ? 'Recording ${_voice.elapsedSeconds}s / 60s'
                        : audio == null
                        ? 'Hold microphone to record (max 60s)'
                        : 'Hold microphone to replace voice note (max 60s)',
                  ),
                ),
              ],
            ),
            if (audio != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: _playing ? 'Pause voice note' : 'Play voice note',
                    onPressed: _playVoice,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                  const Expanded(child: Text('Voice note')),
                  IconButton(
                    tooltip: 'Remove audio',
                    onPressed: _editable ? _removeAudio : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
            if (widget.card.latitude != null &&
                widget.card.longitude != null &&
                !_removeLocation) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined),
                  const Expanded(child: Text('Location attached')),
                  TextButton(
                    onPressed: _editable
                        ? () => setState(() => _removeLocation = true)
                        : null,
                    child: const Text('Remove location'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _editable && !_saving && !_voice.isStarting
                  ? _save
                  : null,
              child: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
