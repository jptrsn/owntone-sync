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

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
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
        file_size INTEGER NOT NULL,
        genre TEXT NOT NULL DEFAULT '',
        length_ms INTEGER NOT NULL DEFAULT 0,
        track_number INTEGER NOT NULL DEFAULT 0,
        disc_number INTEGER NOT NULL DEFAULT 0,
        year INTEGER NOT NULL DEFAULT 0,
        artwork_url TEXT NOT NULL DEFAULT '',
        artwork_path TEXT DEFAULT '',
        content_uri TEXT DEFAULT ''
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
        synced INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Table for sync history
    await db.execute('''
      CREATE TABLE sync_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        playlists_synced INTEGER NOT NULL DEFAULT 0,
        tracks_downloaded INTEGER NOT NULL DEFAULT 0,
        tracks_deleted INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        duration_ms INTEGER,
        trigger_type TEXT NOT NULL
      )
    ''');

    // Table for sync history details (which playlists were in each sync)
    await db.execute('''
      CREATE TABLE sync_history_playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id INTEGER NOT NULL,
        playlist_id INTEGER NOT NULL,
        playlist_name TEXT NOT NULL,
        tracks_in_playlist INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        FOREIGN KEY (sync_id) REFERENCES sync_history (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_sync_history_timestamp ON sync_history(timestamp DESC)',
    );

    await db.execute(
      'CREATE INDEX idx_playlist_tracks_playlist ON playlist_tracks(playlist_id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_tracks_track ON playlist_tracks(track_id)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_events_synced ON pending_events(synced)',
    );

    // Indexes for browse queries
    await db.execute(
      'CREATE INDEX idx_synced_tracks_artist ON synced_tracks(artist)',
    );
    await db.execute(
      'CREATE INDEX idx_synced_tracks_album ON synced_tracks(album)',
    );
    await db.execute(
      'CREATE INDEX idx_synced_tracks_genre ON synced_tracks(genre)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add error_message column to sync_history_playlists
      await db.execute('''
        ALTER TABLE sync_history_playlists
        ADD COLUMN error_message TEXT
      ''');
    }
    if (oldVersion < 3) {
      // Add event sync columns to sync_history
      await db.execute(
        'ALTER TABLE sync_history ADD COLUMN plays_synced INTEGER DEFAULT NULL',
      );
      await db.execute(
        'ALTER TABLE sync_history ADD COLUMN skips_synced INTEGER DEFAULT NULL',
      );
    }
    if (oldVersion < 4) {
      // Add content_uri column for audio playback
      await db.execute(
        'ALTER TABLE synced_tracks ADD COLUMN content_uri TEXT',
      );
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
