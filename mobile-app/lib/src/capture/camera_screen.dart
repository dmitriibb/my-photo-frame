import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _appliedZoom = 1;
  double _wheelOffset = 0;
  Future<void>? _zoomTask;
  int _cameraGeneration = 0;
  Offset? _focusIndicator;
  Timer? _focusIndicatorTimer;

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
      double minZoom = 1;
      double maxZoom = 1;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } on CameraException {
        // Capture still works on devices that cannot report a zoom range.
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraGeneration++;
        _minZoom = minZoom;
        _maxZoom = math.max(minZoom, maxZoom);
        _zoom = 1.clamp(_minZoom, _maxZoom).toDouble();
        _appliedZoom = _zoom;
        _wheelOffset = 0;
        _focusIndicator = null;
      });
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
      _cameraGeneration++;
      _zoomTask = null;
      _focusIndicatorTimer?.cancel();
      _focusIndicator = null;
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
    if (_zoomTask != null) await _zoomTask;
    if (!mounted) return;
    if (_controller != controller) {
      setState(() => _capturing = false);
      return;
    }
    try {
      // CameraX keeps the last preview frame visible while the full-resolution
      // capture and square JPEG processing continue.
      await controller.pausePreview();
    } on CameraException {
      // Still allow the photo to be taken if this camera cannot pause preview.
    }
    if (!mounted) return;
    if (_controller != controller) {
      setState(() => _capturing = false);
      return;
    }
    final capturedAt = DateTime.now();
    final photoFuture = _takeAndProcess(controller);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DraftScreen(
          repository: widget.repository,
          draftsDirectory: widget.draftsDirectory,
          initialCollectionId: widget.initialCollectionId,
          photoFuture: photoFuture,
          pendingPhotoPreview: _squarePreview(controller),
          onPhotoReady: () => _releaseController(controller),
          capturedAt: capturedAt,
        ),
      ),
    );
    // A canceled draft can return while the camera is still writing the shot.
    // Wait before allowing another capture on the same controller.
    if (saved != true) {
      try {
        await photoFuture;
      } catch (_) {}
    }
    if (!mounted) return;
    if (saved == true) {
      setState(() => _capturing = false);
      Navigator.of(context).pop(true);
    } else {
      if (_controller == controller) {
        try {
          await controller.resumePreview();
        } on CameraException {
          _releaseController(controller);
        }
      }
      if (_controller == null) await _initialize();
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<File> _takeAndProcess(CameraController controller) async {
    File? raw;
    try {
      raw = File((await controller.takePicture()).path);
      final processed = await processCardPhoto(raw, widget.draftsDirectory);
      await raw.delete();
      raw = null;
      return processed;
    } finally {
      if (raw != null && await raw.exists()) await raw.delete();
    }
  }

  void _releaseController(CameraController controller) {
    if (_controller != controller) return;
    _cameraGeneration++;
    _zoomTask = null;
    _focusIndicatorTimer?.cancel();
    if (mounted) {
      setState(() {
        _controller = null;
        _focusIndicator = null;
      });
    }
    unawaited(controller.dispose());
  }

  void _moveZoomWheel(double delta) {
    if (_controller == null || _maxZoom <= _minZoom || _capturing) return;
    final nextZoom = (_zoom * math.exp(delta * 0.008))
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    setState(() {
      _wheelOffset += delta;
      _zoom = nextZoom;
    });
    final controller = _controller!;
    final generation = _cameraGeneration;
    // Start after assigning _zoomTask. At a zoom limit _applyZoom can finish
    // synchronously, which would otherwise leave a completed task in the field.
    _zoomTask ??= Future<void>.delayed(
      Duration.zero,
      () => _applyZoom(controller, generation),
    );
  }

  Future<void> _applyZoom(CameraController controller, int generation) async {
    try {
      while (_controller == controller && generation == _cameraGeneration) {
        final target = _zoom;
        if ((target - _appliedZoom).abs() < 0.001) break;
        await controller.setZoomLevel(target);
        _appliedZoom = target;
      }
    } on CameraException {
      if (mounted && _controller == controller) {
        setState(() => _zoom = _appliedZoom);
      }
    } finally {
      if (generation == _cameraGeneration) _zoomTask = null;
    }
  }

  Future<void> _focusAt(
    CameraController controller,
    Offset tap,
    double squareSide,
  ) async {
    if (_capturing) return;
    final preview = controller.value.previewSize!;
    final point = squarePreviewPoint(
      tap,
      squareSide,
      Size(preview.height, preview.width),
    );
    _focusIndicatorTimer?.cancel();
    setState(() => _focusIndicator = tap);
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _focusIndicator = null);
    });
    try {
      await controller.setFocusPoint(point);
    } on CameraException {
      if (mounted && _controller == controller) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tap to focus is unavailable on this camera.'),
          ),
        );
      }
    }
  }

  Widget _squarePreview(CameraController controller) => ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize!.height,
        height: controller.value.previewSize!.width,
        child: CameraPreview(controller),
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusIndicatorTimer?.cancel();
    _cameraGeneration++;
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
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const wheelHeight = 88.0;
            const shutterHeight = 116.0;
            const bottomSpace = 20.0;
            final squareSide = math.min(
              constraints.maxWidth,
              math.max(
                1.0,
                constraints.maxHeight -
                    wheelHeight -
                    shutterHeight -
                    bottomSpace,
              ),
            );
            return Column(
              children: [
                const Spacer(),
                if (controller != null && controller.value.isInitialized)
                  SizedBox.square(
                    dimension: squareSide,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: 'captured-photo',
                          child: _squarePreview(controller),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _focusAt(
                            controller,
                            details.localPosition,
                            squareSide,
                          ),
                        ),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white70,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        if (_focusIndicator != null)
                          Positioned(
                            left: _focusIndicator!.dx - 24,
                            top: _focusIndicator!.dy - 24,
                            child: IgnorePointer(
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.amberAccent,
                                    width: 2,
                                  ),
                                ),
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
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                        ),
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
                if (controller != null && controller.value.isInitialized)
                  SizedBox(
                    height: wheelHeight,
                    width: squareSide,
                    child: ZoomWheel(
                      zoom: _zoom,
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      offset: _wheelOffset,
                      onDrag: _moveZoomWheel,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: shutterHeight,
                  child: Center(
                    child: FilledButton(
                      onPressed: _capturing || controller == null
                          ? null
                          : _capture,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        fixedSize: const Size(96, 96),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 44,
                        semanticLabel: 'Take a photo',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: bottomSpace),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Converts a tap on the cropped square preview to camera preview coordinates.
Offset squarePreviewPoint(Offset tap, double squareSide, Size previewSize) {
  final scale = math.max(
    squareSide / previewSize.width,
    squareSide / previewSize.height,
  );
  final displayedWidth = previewSize.width * scale;
  final displayedHeight = previewSize.height * scale;
  final croppedLeft = (displayedWidth - squareSide) / 2;
  final croppedTop = (displayedHeight - squareSide) / 2;
  return Offset(
    ((tap.dx + croppedLeft) / displayedWidth).clamp(0.0, 1.0),
    ((tap.dy + croppedTop) / displayedHeight).clamp(0.0, 1.0),
  );
}

class ZoomWheel extends StatelessWidget {
  const ZoomWheel({
    super.key,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.offset,
    required this.onDrag,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final double offset;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final available = maxZoom > minZoom;
    return Semantics(
      label: 'Zoom wheel',
      value: '${zoom.toStringAsFixed(1)} times',
      increasedValue: zoom < maxZoom
          ? '${(zoom * math.exp(0.24)).clamp(minZoom, maxZoom).toStringAsFixed(1)} times'
          : null,
      decreasedValue: zoom > minZoom
          ? '${(zoom * math.exp(-0.24)).clamp(minZoom, maxZoom).toStringAsFixed(1)} times'
          : null,
      hint: available
          ? 'Drag right to zoom in, left to zoom out'
          : 'Zoom unavailable on this camera',
      onIncrease: zoom < maxZoom ? () => onDrag(30) : null,
      onDecrease: zoom > minZoom ? () => onDrag(-30) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              available ? '${zoom.toStringAsFixed(1)}×' : 'Zoom unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: available ? Colors.white : Colors.white70,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Opacity(
                opacity: available ? 1 : 0.45,
                child: CustomPaint(painter: _ZoomWheelPainter(offset)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomWheelPainter extends CustomPainter {
  const _ZoomWheelPainter(this.offset);

  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(12, 2, size.width - 24, size.height - 10);
    final shape = RRect.fromRectAndRadius(bounds, const Radius.circular(18));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF50545A),
            Color(0xFFB5BAC0),
            Color(0xFF737980),
            Color(0xFF30343A),
          ],
          stops: [0, 0.28, 0.67, 1],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipRRect(shape);
    const grooveSpacing = 8.0;
    final phase = offset % grooveSpacing;
    for (
      double x = bounds.left - grooveSpacing + phase;
      x < bounds.right + grooveSpacing;
      x += grooveSpacing
    ) {
      final distance = ((x - bounds.center.dx) / (bounds.width / 2)).abs();
      final inset = 4 + 8 * distance * distance;
      canvas.drawLine(
        Offset(x, bounds.top + inset),
        Offset(x, bounds.bottom - inset),
        Paint()
          ..color = const Color(0xAA252A30)
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(x + 2, bounds.top + inset),
        Offset(x + 2, bounds.bottom - inset),
        Paint()
          ..color = const Color(0x99E6E9EC)
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..color = const Color(0xFFCBCFD2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ZoomWheelPainter oldDelegate) =>
      oldDelegate.offset != offset;
}
