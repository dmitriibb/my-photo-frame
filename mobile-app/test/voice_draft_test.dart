import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_photo_frame/src/media/voice_draft.dart';

class FakeRecorder implements VoiceRecorderBackend {
  String? path;
  int stopCount = 0;
  int cancelCount = 0;
  bool permission = true;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(String path) async {
    this.path = path;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    await File(path!).writeAsBytes([1, 2, 3]);
    return path;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (path != null && await File(path!).exists()) await File(path!).delete();
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory drafts;

  setUp(
    () async => drafts = await Directory.systemTemp.createTemp('voice_test_'),
  );
  tearDown(() async => drafts.delete(recursive: true));

  test(
    'voice note stops at the configured maximum and leaves a playable clip',
    () async {
      expect(VoiceDraft.maxDuration, const Duration(seconds: 60));
      final recorder = FakeRecorder();
      final voice = VoiceDraft(
        recorder,
        drafts,
        maxRecordingDuration: const Duration(milliseconds: 10),
      );
      await voice.press();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(voice.isRecording, isFalse);
      expect(recorder.stopCount, 1);
      expect(await voice.clip!.readAsBytes(), [1, 2, 3]);
      voice.dispose();
    },
  );

  test('gesture cancellation discards unfinished audio', () async {
    final recorder = FakeRecorder();
    final voice = VoiceDraft(recorder, drafts);
    await voice.press();
    await voice.cancel();
    expect(voice.clip, isNull);
    expect(recorder.cancelCount, 1);
    expect(drafts.listSync(), isEmpty);
    voice.dispose();
  });

  test('permission denial creates no audio', () async {
    final recorder = FakeRecorder()..permission = false;
    final voice = VoiceDraft(recorder, drafts);
    await expectLater(
      voice.press(),
      throwsA(isA<MicrophonePermissionDenied>()),
    );
    expect(drafts.listSync(), isEmpty);
    voice.dispose();
  });
}
