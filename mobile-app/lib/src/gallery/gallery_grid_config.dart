enum GalleryTileMode { big, medium, small }

/// Central settings for collection density and the content shown at each size.
class GalleryGridConfig {
  static const defaultColumns = 3;
  static const minColumns = 1;
  static const maxColumns = 10;
  static const bigMaxColumns = 3;
  static const mediumMaxColumns = 6;
  static const mediumWrappedDateFromColumns = 6;

  static const bigSingleColumn = GalleryTileConfig(
    mode: GalleryTileMode.big,
    showDate: true,
    showText: true,
    showIndicators: true,
    outerPadding: 20,
    gap: 24,
    cardPadding: 12,
    dateGap: 12,
    textGap: 8,
    dateFontSize: 16,
    textFontSize: 14,
    indicatorSize: 24,
  );

  static const big = GalleryTileConfig(
    mode: GalleryTileMode.big,
    showDate: true,
    showText: true,
    showIndicators: true,
    outerPadding: 12,
    gap: 12,
    cardPadding: 10,
    dateGap: 8,
    textGap: 6,
    dateFontSize: 12,
    textFontSize: 12,
    indicatorSize: 16,
  );

  static const medium = GalleryTileConfig(
    mode: GalleryTileMode.medium,
    showDate: true,
    showText: false,
    showIndicators: false,
    outerPadding: 8,
    gap: 6,
    cardPadding: 4,
    dateGap: 4,
    textGap: 0,
    dateFontSize: 10,
    textFontSize: 0,
    indicatorSize: 0,
    footerHeight: 32,
  );

  static const small = GalleryTileConfig(
    mode: GalleryTileMode.small,
    showDate: false,
    showText: false,
    showIndicators: false,
    outerPadding: 2,
    gap: 2,
    cardPadding: 0,
    dateGap: 0,
    textGap: 0,
    dateFontSize: 0,
    textFontSize: 0,
    indicatorSize: 0,
  );

  static GalleryTileConfig forColumns(int columns) {
    assert(columns >= minColumns && columns <= maxColumns);
    if (columns == 1) return bigSingleColumn;
    if (columns <= bigMaxColumns) return big;
    if (columns <= mediumMaxColumns) return medium;
    return small;
  }
}

class GalleryTileConfig {
  const GalleryTileConfig({
    required this.mode,
    required this.showDate,
    required this.showText,
    required this.showIndicators,
    required this.outerPadding,
    required this.gap,
    required this.cardPadding,
    required this.dateGap,
    required this.textGap,
    required this.dateFontSize,
    required this.textFontSize,
    required this.indicatorSize,
    this.footerHeight = 0,
  });

  final GalleryTileMode mode;
  final bool showDate;
  final bool showText;
  final bool showIndicators;
  final double outerPadding;
  final double gap;
  final double cardPadding;
  final double dateGap;
  final double textGap;
  final double dateFontSize;
  final double textFontSize;
  final double indicatorSize;
  final double footerHeight;
}
