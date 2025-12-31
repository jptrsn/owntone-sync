import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('owntone_sync.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    // Table for tracking synced playlists
    // Path is the stable identifier - ID can change on server restart
    await db.execute('''
      CREATE TABLE synced_playlists (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        last_synced INTEGER NOT NULL
      )
    ''');

    // Table for caching playlist metadata from server
    await db.execute('''
      CREATE TABLE playlist_cache (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        last_fetched INTEGER NOT NULL
      )
    ''');

    // Table for tracking synced tracks
    await db.execute('''
      CREATE TABLE synced_tracks (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        album_artist TEXT NOT NULL,
        local_path TEXT NOT NULL,
        server_path TEXT NOT NULL,
        download_timestamp INTEGER NOT NULL,
        file_size INTEGER NOT NULL
      )
    ''');

    // Join table for playlist-track relationships
    await db.execute('''
      CREATE TABLE playlist_tracks (
        playlist_id INTEGER NOT NULL,
        track_id INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id),
        FOREIGN KEY (playlist_id) REFERENCES synced_playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES synced_tracks (id) ON DELETE CASCADE
      )
    ''');

    // Table for queued playback events
    // No foreign key constraint - events must persist even if track is deleted locally
    await db.execute('''
      CREATE TABLE pending_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create indexes for better query performance
    await db.execute(
      'CREATE INDEX idx_playlist_tracks_playlist ON playlist_tracks(playlist_id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_tracks_track ON playlist_tracks(track_id)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_events_synced ON pending_events(synced)',
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
