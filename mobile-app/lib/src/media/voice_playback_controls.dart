import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class VoicePlaybackControls extends StatefulWidget {
  const VoicePlaybackControls({
    super.key,
    required this.file,
    required this.onRemove,
  });

  final File file;
  final VoidCallback? onRemove;

  @override
  State<VoicePlaybackControls> createState() => VoicePlaybackControlsState();
}

class VoicePlaybackControlsState extends State<VoicePlaybackControls>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(
          () => _playing =
              state.playing &&
              state.processingState != ProcessingState.completed,
        );
      }
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration ?? Duration.zero);
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(VoicePlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) unawaited(_load());
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _position = Duration.zero;
      _duration = Duration.zero;
      _playing = false;
    });
    try {
      await _player.stop();
      final duration = await _player.setFilePath(widget.file.path);
      if (mounted && version == _loadVersion) {
        setState(() => _duration = duration ?? Duration.zero);
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load voice note.')),
        );
      }
    }
  }

  Future<void> stop() => _player.stop();

  Future<void> _togglePlayback() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        unawaited(_player.play());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice note.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_player.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playerSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final progress = total == 0
        ? 0.0
        : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: _playing ? 'Pause voice note' : 'Play voice note',
              onPressed: _togglePlayback,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            Text(_formatDuration(_duration)),
            const Spacer(),
            if (widget.onRemove != null)
              IconButton(
                tooltip: 'Remove voice note',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        if (_playing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(value: progress),
          ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
