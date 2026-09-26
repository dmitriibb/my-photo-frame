import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this.db);

  static const schemaVersion = 2;
  final Database db;

  static Future<AppDatabase> open(
    String path, {
    DatabaseFactory? factory,
    bool singleInstance = true,
  }) async {
    final database = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: singleInstance,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    await database.insert('collections', {
      'id': 'default',
      'name': 'Default',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return AppDatabase._(database);
  }

  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await db.execute('''
        CREATE TABLE collections (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE cards (
          id TEXT PRIMARY KEY,
          collection_id TEXT NOT NULL REFERENCES collections(id),
          photo_date TEXT NOT NULL,
          display_date TEXT NOT NULL,
          photo_date_source TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          photo_path TEXT NOT NULL UNIQUE,
          text TEXT,
          audio_path TEXT UNIQUE,
          latitude REAL,
          longitude REAL,
          CHECK ((latitude IS NULL) = (longitude IS NULL))
        )
      ''');
      await db.execute('''
        CREATE INDEX cards_collection_active
        ON cards(collection_id, deleted_at, photo_date DESC)
      ''');
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE UNIQUE INDEX collection_name_unique
        ON collections(name COLLATE NOCASE)
      ''');
    }
  }

  Future<void> close() => db.close();
}
