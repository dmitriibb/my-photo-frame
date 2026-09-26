import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class MicrophonePermissionDenied implements Exception {
  const MicrophonePermissionDenied();
}

abstract class VoiceRecorderBackend {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class PluginVoiceRecorder implements VoiceRecorderBackend {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class VoiceDraft extends ChangeNotifier {
  VoiceDraft(
    this._backend,
    this._draftsDirectory, {
    this.maxRecordingDuration = maxDuration,
  });

  static const maxDuration = Duration(seconds: 60);

  final VoiceRecorderBackend _backend;
  final Directory _draftsDirectory;
  final Duration maxRecordingDuration;
  Timer? _limitTimer;
  Timer? _elapsedTimer;
  File? _recordingFile;
  File? clip;
  bool _pressed = false;
  bool _starting = false;
  bool _recording = false;
  bool _stopping = false;
  bool _disposed = false;
  Completer<void>? _startSettled;
  Completer<void>? _stopSettled;
  int elapsedSeconds = 0;

  bool get isRecording => _recording;
  bool get isStarting => _starting;

  Future<void> press() async {
    if (_starting || _recording || _stopping || _disposed) return;
    _pressed = true;
    _starting = true;
    _startSettled = Completer<void>();
    _notify();
    try {
      if (!await _backend.hasPermission()) {
        throw const MicrophonePermissionDenied();
      }
      if (!_pressed || _disposed) return;
      await _draftsDirectory.create(recursive: true);
      final file = File(
        p.join(_draftsDirectory.path, '${const Uuid().v4()}.m4a'),
      );
      if (!_pressed || _disposed) return;
      _recordingFile = file;
      await _backend.start(file.path);
      if (!_pressed || _disposed) {
        await _backend.cancel();
        await _delete(file);
        _recordingFile = null;
        return;
      }
      _recording = true;
      elapsedSeconds = 0;
      _limitTimer = Timer(maxRecordingDuration, () => unawaited(release()));
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds = (elapsedSeconds + 1).clamp(0, 60);
        _notify();
      });
    } catch (_) {
      final file = _recordingFile;
      _recordingFile = null;
      if (file != null) {
        try {
          await _backend.cancel();
        } catch (_) {
          // Keep the original error; the draft file is still removed below.
        }
        await _delete(file);
      }
      rethrow;
    } finally {
      _starting = false;
      _startSettled?.complete();
      _startSettled = null;
      _notify();
    }
  }

  Future<void> release() async {
    _pressed = false;
    if (!_recording || _stopping) return;
    _recording = false;
    _stopping = true;
    _stopSettled = Completer<void>();
    _cancelTimers();
    _notify();
    final file = _recordingFile;
    _recordingFile = null;
    try {
      final path = await _backend.stop();
      final completed = path == null ? null : File(path);
      if (completed != null &&
          await completed.exists() &&
          await completed.length() > 0) {
        final previous = clip;
        clip = completed;
        if (previous != null && previous.path != completed.path) {
          await _delete(previous);
        }
      } else if (file != null) {
        await _delete(file);
      }
    } catch (_) {
      if (file != null) await _delete(file);
      rethrow;
    } finally {
      _stopping = false;
      _stopSettled?.complete();
      _stopSettled = null;
      _notify();
    }
  }

  Future<void> cancel() async {
    _pressed = false;
    if (!_recording || _stopping) return;
    _recording = false;
    _cancelTimers();
    final file = _recordingFile;
    _recordingFile = null;
    try {
      await _backend.cancel();
    } finally {
      if (file != null) await _delete(file);
      _notify();
    }
  }

  Future<void> removeClip() async {
    final file = clip;
    clip = null;
    if (file != null) await _delete(file);
    _notify();
  }

  void _cancelTimers() {
    _limitTimer?.cancel();
    _elapsedTimer?.cancel();
    _limitTimer = null;
    _elapsedTimer = null;
  }

  Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pressed = false;
    _cancelTimers();
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _startSettled?.future;
    await _stopSettled?.future;
    if (_recording) {
      try {
        await _backend.cancel();
      } catch (_) {}
    }
    if (_recordingFile != null) await _delete(_recordingFile!);
    if (clip != null) await _delete(clip!);
    await _backend.dispose();
  }
}
