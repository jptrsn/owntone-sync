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
      version: 8,
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

    // Table for tracking synced tracks.
    //
    // `content_uri` and `artwork_source` deliberately carry NO DEFAULT. They
    // are added on upgrade by `ALTER TABLE ... ADD COLUMN` (v4 and v8), which
    // cannot carry one, and SQLite cannot alter a default afterwards without
    // rebuilding the table — so the fresh-install DDL is aligned DOWN to match
    // the upgraded schema and both paths produce identical DDL. Readers already
    // normalise NULL and '' identically (TrackUriResolver._isUsableTreeUri, the
    // v5 purge, the Kotlin writer). Do not "tidy" a default back in: a
    // fresh-vs-upgraded schema divergence is exactly what silently broke
    // sync_history for every fresh install until v6.
    //
    // Keep commentary OUT of the SQL string. SQLite stores the CREATE TABLE
    // text verbatim in sqlite_master, comments included, so a comment inside
    // the statement would itself show up as a schema diff against an upgraded
    // database.
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
        content_uri TEXT,
        rating INTEGER NOT NULL DEFAULT 0,
        artwork_source TEXT
      )
    ''');

    // Pending field edits (last-write-wins state, unlike the accumulative
    // pending_events). The composite primary key gives one row per
    // (track, field) for free; base_value anchors the edit to the server
    // value it was made against so the sync worker can detect server-side
    // changes (server wins on conflict). No FK on purpose: an edit must
    // survive local deletion of the track, since the server still has it.
    await db.execute('''
      CREATE TABLE pending_track_edits (
        track_id   INTEGER NOT NULL,
        field      TEXT    NOT NULL,
        new_value  TEXT    NOT NULL,
        base_value TEXT    NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (track_id, field)
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
    // plays_synced/skips_synced must exist here as well as in the v2->v3
    // migration: a fresh install calls _createDB directly and never runs the
    // old-version migrations, so omitting them here left fresh installs with
    // a table the Kotlin worker's INSERT cannot write to.
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
        trigger_type TEXT NOT NULL,
        plays_synced INTEGER DEFAULT NULL,
        skips_synced INTEGER DEFAULT NULL
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

    // Single-row (id = 1) table holding the playback state to restore on
    // cold start (A8): the queue as track IDs in base order, the current
    // track, the position, shuffle/repeat, and the queue origin. A table
    // rather than SharedPreferences because queues can be long.
    await db.execute('''
      CREATE TABLE playback_state (
        id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
        queue_ids TEXT NOT NULL,
        current_track_id INTEGER,
        position_ms INTEGER NOT NULL DEFAULT 0,
        shuffle_enabled INTEGER NOT NULL DEFAULT 0,
        shuffle_indices TEXT NOT NULL DEFAULT '',
        repeat_mode TEXT NOT NULL DEFAULT 'none',
        origin_kind TEXT,
        origin_id INTEGER,
        origin_name TEXT,
        updated_at INTEGER NOT NULL
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
    if (oldVersion < 5) {
      // One-time purge: cached content URIs built in the bare document form
      // (content://<authority>/document/...) lack the /tree/ segment and are
      // not readable under a tree grant — playback on them is denied with a
      // SecurityException. Invalidate them so they re-resolve to the correct
      // tree-scoped form. Runs exactly once, at the 4 -> 5 upgrade.
      await db.execute(
        "UPDATE synced_tracks SET content_uri = '' "
        "WHERE content_uri IS NOT NULL AND content_uri != '' "
        "AND content_uri NOT LIKE '%/tree/%'",
      );
    }
    if (oldVersion < 6) {
      // sync_history was created WITHOUT plays_synced/skips_synced; only the
      // v2->v3 migration adds them, so a fresh install (which runs _createDB
      // at the current version) never got them. The worker's INSERT failed on
      // those DBs and no history rows were written. DBs that came up through
      // the v3 migration already have the columns, so add only when absent.
      final columns = await db.rawQuery('PRAGMA table_info(sync_history)');
      final names = columns.map((c) => c['name'] as String).toSet();
      if (!names.contains('plays_synced')) {
        await db.execute(
          'ALTER TABLE sync_history ADD COLUMN plays_synced INTEGER DEFAULT NULL',
        );
      }
      if (!names.contains('skips_synced')) {
        await db.execute(
          'ALTER TABLE sync_history ADD COLUMN skips_synced INTEGER DEFAULT NULL',
        );
      }

      // While the columns were missing the parent INSERT failed and returned
      // -1, but the worker still wrote the playlist children with that as
      // their sync_id (PRAGMA foreign_keys is off, so the FK is unenforced).
      // Delete the orphans.
      await db.execute(
        'DELETE FROM sync_history_playlists '
        'WHERE sync_id NOT IN (SELECT id FROM sync_history)',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS playback_state (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          queue_ids TEXT NOT NULL,
          current_track_id INTEGER,
          position_ms INTEGER NOT NULL DEFAULT 0,
          shuffle_enabled INTEGER NOT NULL DEFAULT 0,
          shuffle_indices TEXT NOT NULL DEFAULT '',
          repeat_mode TEXT NOT NULL DEFAULT 'none',
          origin_kind TEXT,
          origin_id INTEGER,
          origin_name TEXT,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      // Track ratings: a last-known-value column on synced_tracks (updated
      // optimistically on edit, pulled/pushed by the sync worker) plus the
      // pending_track_edits table carrying unpushed edits.
      final columns = await db.rawQuery('PRAGMA table_info(synced_tracks)');
      final names = columns.map((c) => c['name'] as String).toSet();
      if (!names.contains('rating')) {
        await db.execute(
          'ALTER TABLE synced_tracks ADD COLUMN rating INTEGER NOT NULL DEFAULT 0',
        );
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_track_edits (
          track_id   INTEGER NOT NULL,
          field      TEXT    NOT NULL,
          new_value  TEXT    NOT NULL,
          base_value TEXT    NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (track_id, field)
        )
      ''');
    }
    if (oldVersion < 8) {
      // Album artwork cache: where each track's cover came from. NULL =
      // unresolved (the sync worker resolves it), 'embedded', 'server', or
      // 'none' = checked and absent (the negative cache — without it every
      // sync re-extracts from every artless file). The column holds no path
      // of its own: artwork_path is written by the same narrow UPDATE.
      //
      // Written by the Kotlin sync worker, which opens this DB without
      // migrating — it guards on the column's presence the same way the
      // v7 rating pass does, so add it here (and only here).
      final columns = await db.rawQuery('PRAGMA table_info(synced_tracks)');
      final names = columns.map((c) => c['name'] as String).toSet();
      if (!names.contains('artwork_source')) {
        await db.execute(
          'ALTER TABLE synced_tracks ADD COLUMN artwork_source TEXT',
        );
      }
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
