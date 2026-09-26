import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../media/photo_processor.dart';
import 'draft_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.repository,
    required this.draftsDirectory,
    required this.initialCollectionId,
  });

  final CardRepository repository;
  final Directory draftsDirectory;
  final String initialCollectionId;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _initializing = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializing || _controller != null) return;
    _initializing = true;
    if (mounted) setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found.');
      }
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'CameraAccessDenied'
              ? 'Camera access is needed to take a photo. Allow it in Android settings, then retry.'
              : 'Camera is unavailable: ${error.description ?? error.code}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera is unavailable: $error');
    } finally {
      _initializing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      _controller = null;
      if (controller != null) unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initialize());
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    File? raw;
    try {
      final capturedAt = DateTime.now();
      raw = File((await controller.takePicture()).path);
      final processed = await processCardPhoto(raw, widget.draftsDirectory);
      await raw.delete();
      raw = null;
      if (!mounted) {
        await processed.delete();
        return;
      }
      setState(() => _controller = null);
      await controller.dispose();
      if (!mounted) {
        await processed.delete();
        return;
      }
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DraftScreen(
            repository: widget.repository,
            draftsDirectory: widget.draftsDirectory,
            initialCollectionId: widget.initialCollectionId,
            photo: processed,
            capturedAt: capturedAt,
          ),
        ),
      );
      if (mounted) {
        if (saved == true) {
          Navigator.of(context).pop(true);
        } else {
          await _initialize();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save photo: $error')));
      }
    } finally {
      if (raw != null && await raw.exists()) await raw.delete();
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Take a photo'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const Spacer(),
          if (controller != null && controller.value.isInitialized)
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize!.height,
                        height: controller.value.previewSize!.width,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _initialize,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: FilledButton.tonalIcon(
              onPressed: _capturing || controller == null ? null : _capture,
              icon: _capturing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: const Text('Capture square photo'),
            ),
          ),
        ],
      ),
    );
  }
}
