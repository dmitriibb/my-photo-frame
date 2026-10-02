import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'gallery_grid_config.dart';

class CollectionGrid extends StatefulWidget {
  const CollectionGrid({
    super.key,
    required this.cards,
    required this.columns,
    required this.onColumnsChanged,
    required this.photoFile,
    required this.onCardTap,
    this.onCardLongPress,
    this.selectionMode = false,
    this.selectedCardIds = const {},
  });

  final List<MemoryCard> cards;
  final int columns;
  final ValueChanged<int> onColumnsChanged;
  final File Function(MemoryCard) photoFile;
  final ValueChanged<MemoryCard> onCardTap;
  final ValueChanged<MemoryCard>? onCardLongPress;
  final bool selectionMode;
  final Set<String> selectedCardIds;

  @override
  State<CollectionGrid> createState() => _CollectionGridState();
}

class _CollectionGridState extends State<CollectionGrid> {
  int _gestureStartColumns = GalleryGridConfig.defaultColumns;
  final ScrollController _scrollController = ScrollController();
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        _lastScrollOffset = _scrollController.offset;
      }
    });
  }

  @override
  void didUpdateWidget(CollectionGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMode = GalleryGridConfig.forColumns(oldWidget.columns).mode;
    final newMode = GalleryGridConfig.forColumns(widget.columns).mode;
    if (oldMode != newMode) {
      final offset = _lastScrollOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        _scrollController.jumpTo(offset.clamp(0, position.maxScrollExtent));
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = GalleryGridConfig.forColumns(widget.columns);
    return GestureDetector(
      onScaleStart: (_) => _gestureStartColumns = widget.columns,
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        final columns = (_gestureStartColumns / details.scale).round().clamp(
          GalleryGridConfig.minColumns,
          GalleryGridConfig.maxColumns,
        );
        if (columns != widget.columns) widget.onColumnsChanged(columns);
      },
      child: config.mode == GalleryTileMode.big
          ? _bigGrid(config)
          : _regularGrid(config),
    );
  }

  Widget _bigGrid(GalleryTileConfig config) {
    final rowCount =
        (widget.cards.length + widget.columns - 1) ~/ widget.columns;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        config.outerPadding,
        config.outerPadding,
        config.outerPadding,
        96,
      ),
      itemCount: rowCount,
      itemBuilder: (context, row) => Padding(
        padding: EdgeInsets.only(bottom: config.gap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < widget.columns; column++) ...[
              if (column > 0) SizedBox(width: config.gap),
              Expanded(
                child: row * widget.columns + column < widget.cards.length
                    ? _tile(widget.cards[row * widget.columns + column], config)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _regularGrid(GalleryTileConfig config) => LayoutBuilder(
    builder: (context, constraints) {
      final tileWidth =
          (constraints.maxWidth -
              2 * config.outerPadding -
              (widget.columns - 1) * config.gap) /
          widget.columns;
      return GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          config.outerPadding,
          config.outerPadding,
          config.outerPadding,
          96,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns,
          crossAxisSpacing: config.gap,
          mainAxisSpacing: config.gap,
          mainAxisExtent: tileWidth + config.footerHeight,
        ),
        itemCount: widget.cards.length,
        itemBuilder: (context, index) => _tile(widget.cards[index], config),
      );
    },
  );

  Widget _tile(MemoryCard card, GalleryTileConfig config) {
    final selected = widget.selectedCardIds.contains(card.id);
    return Stack(
      children: [
        _tileContent(card, config),
        if (widget.selectionMode) ...[
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: Semantics(
              label: 'Select card ${card.displayDate}',
              button: true,
              selected: selected,
              child: InkResponse(
                key: ValueKey('gallery-select-${card.id}'),
                onTap: () => widget.onCardTap(card),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black38, blurRadius: 3),
                      ],
                    ),
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: config.mode == GalleryTileMode.small ? 16 : 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tileContent(MemoryCard card, GalleryTileConfig config) {
    final photo = AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) => Image.file(
          widget.photoFile(card),
          fit: BoxFit.cover,
          cacheWidth:
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil()
                  .clamp(1, 4096),
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );

    if (config.mode == GalleryTileMode.small) {
      return InkWell(
        key: ValueKey('gallery-card-${card.id}'),
        onTap: () => widget.onCardTap(card),
        onLongPress: widget.onCardLongPress == null
            ? null
            : () => widget.onCardLongPress!(card),
        child: photo,
      );
    }

    return Card(
      key: ValueKey('gallery-card-${card.id}'),
      margin: EdgeInsets.zero,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onCardTap(card),
        onLongPress: widget.onCardLongPress == null
            ? null
            : () => widget.onCardLongPress!(card),
        child: Padding(
          padding: EdgeInsets.all(config.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              photo,
              if (config.showDate) ...[
                SizedBox(height: config.dateGap),
                if (config.showIndicators)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        card.displayDate,
                        style: TextStyle(fontSize: config.dateFontSize),
                      ),
                      if (card.audioPath != null)
                        Icon(
                          Icons.volume_up_rounded,
                          size: config.indicatorSize,
                        ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.columns >=
                              GalleryGridConfig.mediumWrappedDateFromColumns
                          ? card.displayDate.replaceFirst('-', '-\n')
                          : card.displayDate,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(fontSize: config.dateFontSize),
                    ),
                  ),
              ],
              if (config.showText && card.text != null) ...[
                SizedBox(height: config.textGap),
                Text(
                  card.text!,
                  style: TextStyle(fontSize: config.textFontSize),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
