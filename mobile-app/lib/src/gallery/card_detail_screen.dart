import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../data/card_repository.dart';
import '../data/models.dart';
import '../export/archive_export.dart';
import '../export/export_actions.dart';
import '../media/voice_playback_controls.dart';
import 'edit_screen.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({
    super.key,
    required this.card,
    required this.cards,
    required this.repository,
    required this.draftsDirectory,
  });

  final MemoryCard card;
  final List<MemoryCard> cards;
  final CardRepository repository;
  final Directory draftsDirectory;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<VoicePlaybackControlsState> _playbackKey = GlobalKey();
  late final AnimationController _swipeAnimation;
  final Set<int> _pressedPointers = {};
  VelocityTracker? _velocityTracker;
  int? _activePointer;
  Offset? _pointerStart;
  bool _dragging = false;
  bool _transitioning = false;
  double _dragOffset = 0;
  double _animationStart = 0;
  double _animationEnd = 0;
  double _frontHeight = 0;
  final GlobalKey _frontContentKey = GlobalKey();
  late final List<MemoryCard> _cards;
  late int _currentIndex;
  bool _exportingPhoto = false;
  bool _showActions = false;
  late MemoryCard _card;

  @override
  void initState() {
    super.initState();
    _cards = List.of(widget.cards);
    _currentIndex = _cards.indexWhere((card) => card.id == widget.card.id);
    assert(_currentIndex >= 0);
    _card = _cards[_currentIndex];
    _swipeAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          if (!mounted) return;
          setState(() {
            final progress = Curves.easeOutCubic.transform(
              _swipeAnimation.value,
            );
            _dragOffset =
                _animationStart + (_animationEnd - _animationStart) * progress;
          });
        });
  }

  Future<void> _edit() async {
    await _playbackKey.currentState?.stop();
    if (!mounted) return;
    final updated = await Navigator.of(context).push<MemoryCard>(
      MaterialPageRoute(
        builder: (_) => EditScreen(
          card: _card,
          repository: widget.repository,
          draftsDirectory: widget.draftsDirectory,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _card = updated;
        _cards[_currentIndex] = updated;
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pressedPointers.add(event.pointer);
    if (_pressedPointers.length != 1 || _transitioning || _showActions) {
      _activePointer = null;
      if (_dragging) unawaited(_settleOffset());
      return;
    }
    _activePointer = event.pointer;
    _pointerStart = event.position;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _dragging = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _transitioning) return;
    final start = _pointerStart;
    if (start == null) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - start;
    if (!_dragging) {
      if (delta.dx.abs() < 12 || delta.dx.abs() <= delta.dy.abs() * 1.3) {
        return;
      }
      _dragging = true;
    }
    setState(() => _dragOffset = delta.dx);
  }

  void _onPointerEnd(PointerEvent event) {
    _pressedPointers.remove(event.pointer);
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    _velocityTracker = null;
    if (!_dragging || _transitioning) return;
    _dragging = false;
    final distance = _dragOffset.abs();
    if (distance >= 80 || (distance >= 20 && velocity.abs() >= 600)) {
      unawaited(_swipe(_dragOffset.sign));
    } else {
      unawaited(_settleOffset());
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pressedPointers.remove(event.pointer);
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _velocityTracker = null;
    if (_dragging) {
      _dragging = false;
      unawaited(_settleOffset());
    }
  }

  Future<void> _animateOffset(double target) async {
    _animationStart = _dragOffset;
    _animationEnd = target;
    await _swipeAnimation.forward(from: 0);
  }

  Future<void> _settleOffset() async {
    if (_transitioning) return;
    _transitioning = true;
    await _animateOffset(0);
    _transitioning = false;
  }

  Future<void> _swipe(double direction) async {
    if (_transitioning) return;
    _transitioning = true;
    await _playbackKey.currentState?.stop();
    if (!mounted) return;
    final exitOffset = direction * MediaQuery.sizeOf(context).width * 1.2;
    await _animateOffset(exitOffset);
    if (!mounted) return;
    final nextIndex = _currentIndex - direction.toInt();
    if (nextIndex < 0 || nextIndex >= _cards.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _currentIndex = nextIndex;
      _card = _cards[nextIndex];
      _showActions = false;
      _dragOffset = 0;
    });
    _transitioning = false;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to Deleted?'),
        content: const Text('You can restore this card for 30 days.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Deleted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _playbackKey.currentState?.stop();
      await widget.repository.softDeleteCard(_card.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete card: $error')),
        );
      }
    }
  }

  Future<void> _exportPhoto() async {
    if (_exportingPhoto) return;
    setState(() => _exportingPhoto = true);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw StateError('Gallery access was denied.');
      }
      await Gal.putImage(widget.repository.photoFile(_card).path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo exported to gallery.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPhoto = false);
    }
  }

  Future<void> _exportCard() async {
    final exports = Directory(
      p.join(widget.draftsDirectory.parent.path, 'my_photo_frame_exports'),
    );
    await showArchiveExportOptions(
      context,
      () => ArchiveExport(widget.repository, exports).card(_card),
    );
  }

  void _selectAction(Future<void> Function() action) {
    setState(() => _showActions = false);
    unawaited(action());
  }

  Widget _actionMenu() => Material(
    color: Colors.white,
    elevation: 8,
    borderRadius: BorderRadius.circular(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Export card archive'),
            onTap: () => _selectAction(_exportCard),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('Export photo to gallery'),
            onTap: _exportingPhoto ? null : () => _selectAction(_exportPhoto),
          ),
          if (DateTime.now().toUtc().isBefore(_card.editDeadline))
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit card'),
              onTap: () => _selectAction(_edit),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Move to Deleted'),
            onTap: () => _selectAction(_delete),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _swipeAnimation.dispose();
    super.dispose();
  }

  void _measureFrontHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _frontContentKey.currentContext?.findRenderObject();
      if (box is! RenderBox) return;
      if ((box.size.height - _frontHeight).abs() > 1) {
        setState(() => _frontHeight = box.size.height);
      }
    });
  }

  Widget _cardContent(MemoryCard card, {required bool active}) => Stack(
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: active ? () => setState(() => _showActions = true) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: active
                    ? InteractiveViewer(
                        key: ValueKey('detail-photo-${card.id}'),
                        child: Image.file(
                          widget.repository.photoFile(card),
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image.file(
                        widget.repository.photoFile(card),
                        fit: BoxFit.contain,
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                card.displayDate,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (card.text != null) ...[
                const SizedBox(height: 12),
                Text(card.text!),
              ],
              if (card.audioPath != null) ...[
                const SizedBox(height: 8),
                if (active)
                  VoicePlaybackControls(
                    key: _playbackKey,
                    file: widget.repository.audioFile(card)!,
                    onRemove: null,
                  )
                else
                  const Icon(Icons.play_arrow),
              ],
              if (card.latitude != null && card.longitude != null)
                const Icon(Icons.location_on_outlined),
            ],
          ),
        ),
      ),
      if (active && _showActions) ...[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showActions = false),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Align(alignment: Alignment.topRight, child: _actionMenu()),
        ),
      ],
    ],
  );

  Widget _surface(
    MemoryCard card, {
    required bool active,
    required double offset,
    required double scale,
    required double rotation,
    double? previewHeight,
  }) {
    final dialog = Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: previewHeight ?? double.infinity,
          ),
          child: KeyedSubtree(
            key: active ? _frontContentKey : null,
            child: SingleChildScrollView(
              child: _cardContent(card, active: active),
            ),
          ),
        ),
      ),
    );
    return Align(
      key: ValueKey('swipe-surface-${card.id}'),
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(offset, 0),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: IgnorePointer(
              ignoring: !active,
              child: Listener(
                onPointerDown: active ? _onPointerDown : null,
                onPointerMove: active ? _onPointerMove : null,
                onPointerUp: active ? _onPointerEnd : null,
                onPointerCancel: active ? _onPointerCancel : null,
                child: dialog,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _measureFrontHeight();
    final width = MediaQuery.sizeOf(context).width;
    final direction = _dragOffset.sign.toInt();
    final incomingIndex = _currentIndex - direction;
    final hasIncoming =
        direction != 0 && incomingIndex >= 0 && incomingIndex < _cards.length;
    final progress = (_dragOffset.abs() / (width * 0.5)).clamp(0.0, 1.0);
    final forward = direction < 0;
    final current = _surface(
      _card,
      active: true,
      offset: hasIncoming && !forward ? 0 : _dragOffset,
      scale: hasIncoming && !forward ? 1 - 0.06 * progress : 1,
      rotation: hasIncoming && !forward ? 0 : _dragOffset / width * 0.08,
    );
    if (!hasIncoming) {
      return Stack(fit: StackFit.expand, children: [current]);
    }
    final incoming = _surface(
      _cards[incomingIndex],
      active: false,
      offset: forward ? 0 : -width * (1 - progress),
      scale: forward ? 0.94 + 0.06 * progress : 1,
      rotation: forward ? 0 : -0.04 * (1 - progress),
      previewHeight: _frontHeight > 0
          ? _frontHeight * (forward ? 1 : 0.94)
          : null,
    );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: forward ? [incoming, current] : [current, incoming],
    );
  }
}
