/// Keep a collection name in one portable filename / Android album component.
String exportCollectionName(String name) {
  var safe = name.replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_').trim();
  safe = safe.replaceAll(RegExp(r'^\.+|[. ]+$'), '');
  if (safe.isEmpty) return 'Collection';
  return String.fromCharCodes(safe.runes.take(80));
}

String galleryAlbum(String collectionName) =>
    'my-photo-frame/${exportCollectionName(collectionName)}';
