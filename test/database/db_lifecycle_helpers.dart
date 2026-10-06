import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:owntone_sync/data/database/database_helper.dart';

/// The file `DatabaseHelper` opens (`_initDB` hard-codes the name;
/// sqflite_common_ffi resolves relative paths against
/// `<cwd>/.dart_tool/sqflite_common_ffi/databases`).
String dbFilePath() => p.join(
  p.absolute(p.join('.dart_tool', 'sqflite_common_ffi', 'databases')),
  'owntone_sync.db',
);

/// The v3 schema, verbatim from `main` @ 9970b9f (v0.1.8, the last release
/// before the audio player; `PRAGMA user_version` = 3 on every install of it).
/// A fresh v3 install ran exactly this `_createDB`: `sync_history` WITHOUT
/// `plays_synced`/`skips_synced`, `sync_history_playlists` WITH
/// `error_message`, `synced_tracks` WITHOUT `content_uri`/`rating`/
/// `artwork_source`.
const List<String> v3CreateStatements = [
  '''
      CREATE TABLE synced_playlists (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        last_synced INTEGER NOT NULL
      )
  ''',
  '''
      CREATE TABLE playlist_cache (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        last_fetched INTEGER NOT NULL
      )
  ''',
  '''
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
        artwork_path TEXT DEFAULT ''
      )
  ''',
  '''
      CREATE TABLE playlist_tracks (
        playlist_id INTEGER NOT NULL,
        track_id INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id),
        FOREIGN KEY (playlist_id) REFERENCES synced_playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES synced_tracks (id) ON DELETE CASCADE
      )
  ''',
  '''
      CREATE TABLE pending_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
  ''',
  '''
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
  ''',
  '''
      CREATE TABLE sync_history_playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id INTEGER NOT NULL,
        playlist_id INTEGER NOT NULL,
        playlist_name TEXT NOT NULL,
        tracks_in_playlist INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        FOREIGN KEY (sync_id) REFERENCES sync_history (id) ON DELETE CASCADE
      )
  ''',
  'CREATE INDEX idx_sync_history_timestamp ON sync_history(timestamp DESC)',
  'CREATE INDEX idx_playlist_tracks_playlist ON playlist_tracks(playlist_id)',
  'CREATE INDEX idx_playlist_tracks_track ON playlist_tracks(track_id)',
  'CREATE INDEX idx_pending_events_synced ON pending_events(synced)',
  'CREATE INDEX idx_synced_tracks_artist ON synced_tracks(artist)',
  'CREATE INDEX idx_synced_tracks_album ON synced_tracks(album)',
  'CREATE INDEX idx_synced_tracks_genre ON synced_tracks(genre)',
];

// The DDL of the migration steps, verbatim from `database_helper.dart`
// `_onUpgrade` (what a real database carries after having run each step).
const String v4AddContentUri =
    'ALTER TABLE synced_tracks ADD COLUMN content_uri TEXT';

const String v6AddPlaysSynced =
    'ALTER TABLE sync_history ADD COLUMN plays_synced INTEGER DEFAULT NULL';

const String v6AddSkipsSynced =
    'ALTER TABLE sync_history ADD COLUMN skips_synced INTEGER DEFAULT NULL';

const String v6CreatePlaybackState = '''
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
  ''';

const String v7AddRating =
    'ALTER TABLE synced_tracks ADD COLUMN rating INTEGER NOT NULL DEFAULT 0';

const String v7CreatePendingTrackEdits = '''
        CREATE TABLE IF NOT EXISTS pending_track_edits (
          track_id   INTEGER NOT NULL,
          field      TEXT    NOT NULL,
          new_value  TEXT    NOT NULL,
          base_value TEXT    NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (track_id, field)
        )
  ''';

const String v8AddArtworkSource =
    'ALTER TABLE synced_tracks ADD COLUMN artwork_source TEXT';

/// Rows written into the v3 fixture (data-preservation checks compare against
/// these exact values after the full v3 -> v8 chain).
Future<void> seedV3Data(Database db) async {
  await db.insert('synced_playlists', {
    'id': 1,
    'name': 'Brass',
    'path': '/playlists/brass',
    'type': 'static',
    'last_synced': 1000,
  });
  await db.insert('synced_playlists', {
    'id': 2,
    'name': 'Soul',
    'path': '/playlists/soul',
    'type': 'static',
    'last_synced': 1000,
  });
  await db.insert('playlist_cache', {
    'id': 1,
    'name': 'Brass',
    'path': '/playlists/brass',
    'type': 'static',
    'item_count': 33,
    'last_fetched': 1000,
  });
  await db.insert('synced_tracks', {
    'id': 1,
    'title': 'Track One',
    'artist': 'Artist A',
    'album': 'Album X',
    'album_artist': 'AA X',
    'local_path': '/music/t1.mp3',
    'server_path': '/media/t1.mp3',
    'download_timestamp': 111,
    'file_size': 1000000,
    'genre': 'Jazz',
    'length_ms': 60000,
    'track_number': 1,
    'disc_number': 1,
    'year': 1970,
    'artwork_url': '/artwork/item/1',
    'artwork_path': '',
  });
  // Omitted columns take the table defaults (genre '', length_ms 0, ...).
  await db.insert('synced_tracks', {
    'id': 2,
    'title': 'Track Two',
    'artist': 'Artist B',
    'album': 'Album Y',
    'album_artist': 'AA Y',
    'local_path': '/music/t2.mp3',
    'server_path': '/media/t2.mp3',
    'download_timestamp': 222,
    'file_size': 2000000,
  });
  await db.insert('synced_tracks', {
    'id': 3,
    'title': 'Track Three',
    'artist': 'Artist C',
    'album': 'Album Z',
    'album_artist': 'AA Z',
    'local_path': '/music/t3.mp3',
    'server_path': '/media/t3.mp3',
    'download_timestamp': 333,
    'file_size': 3000000,
    'length_ms': 300000,
    'year': 1990,
  });
  await db.insert('playlist_tracks', {'playlist_id': 1, 'track_id': 1});
  await db.insert('playlist_tracks', {'playlist_id': 1, 'track_id': 2});
  await db.insert('playlist_tracks', {'playlist_id': 2, 'track_id': 3});
  await db.insert('pending_events', {
    'track_id': 1,
    'event_type': 'play',
    'timestamp': 12345,
    'synced': 0,
    'retry_count': 0,
  });
  // v3 shape: no plays_synced / skips_synced columns to fill.
  await db.insert('sync_history', {
    'timestamp': 1000,
    'status': 'success',
    'playlists_synced': 2,
    'tracks_downloaded': 3,
    'tracks_deleted': 0,
    'error_message': null,
    'duration_ms': 1234,
    'trigger_type': 'manual',
  });
  await db.insert('sync_history_playlists', {
    'sync_id': 1,
    'playlist_id': 1,
    'playlist_name': 'Brass',
    'tracks_in_playlist': 33,
    'error_message': null,
  });
  await db.insert('sync_history_playlists', {
    'sync_id': 1,
    'playlist_id': 2,
    'playlist_name': 'Soul',
    'tracks_in_playlist': 62,
    'error_message': null,
  });
}

/// Builds a fixture database at [version] the way the real migration chain
/// leaves it: v3 DDL plus the schema effects of every step up to [version].
/// [seed] writes the v3 data-preservation rows first.
Future<void> buildFixtureAtVersion(
  Database db,
  int version, {
  bool seed = false,
}) async {
  for (final statement in v3CreateStatements) {
    await db.execute(statement);
  }
  if (version >= 4) await db.execute(v4AddContentUri);
  if (version >= 6) {
    await db.execute(v6AddPlaysSynced);
    await db.execute(v6AddSkipsSynced);
    await db.execute(v6CreatePlaybackState);
  }
  if (version >= 7) {
    await db.execute(v7AddRating);
    await db.execute(v7CreatePendingTrackEdits);
  }
  if (version >= 8) await db.execute(v8AddArtworkSource);
  if (seed) await seedV3Data(db);
  await db.execute('PRAGMA user_version = $version');
}

/// Normalised structural schema: user_version, and per table the columns in
/// order (name, type, notnull, default, pk), the indexes (with their columns
/// in order, uniqueness and origin — auto-indexes included, so UNIQUE column
/// constraints are covered) and the foreign keys.
Future<Map<String, Object?>> snapshotSchema(Database db) async {
  final versionRow = (await db.rawQuery('PRAGMA user_version')).first;
  final tableNames = (
    await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )
  ).map((r) => r['name'] as String).toList();

  final tables = <String, Object?>{};
  for (final name in tableNames) {
    final columns = (await db.rawQuery("PRAGMA table_info('$name')"))
        .map((c) => <String, Object?>{
              'name': c['name'],
              'type': c['type'],
              'notnull': c['notnull'],
              'dflt_value': c['dflt_value'],
              'pk': c['pk'],
            })
        .toList();

    final indexList = await db.rawQuery("PRAGMA index_list('$name')");
    final indexes = <String, Object?>{};
    for (final index in indexList) {
      final indexName = index['name'] as String;
      final indexColumns = (await db.rawQuery("PRAGMA index_info('$indexName')"))
          .map((c) => c['name'] as String)
          .toList();
      indexes[indexName] = <String, Object?>{
        'unique': index['unique'],
        'origin': index['origin'],
        'columns': indexColumns,
      };
    }

    final foreignKeys = (await db.rawQuery("PRAGMA foreign_key_list('$name')"))
        .map((f) => <String, Object?>{
              'ref': f['table'],
              'from': f['from'],
              'to': f['to'],
              'on_update': f['on_update'],
              'on_delete': f['on_delete'],
              'match': f['match'],
            })
        .toList();

    tables[name] = <String, Object?>{
      'columns': columns,
      'indexes': indexes,
      'foreign_keys': foreignKeys,
    };
  }
  return {
    'user_version': versionRow.values.first,
    'tables': tables,
  };
}

/// The v3 seed rows as they must exist after the full chain (including the
/// values the new columns take on pre-existing rows).
Map<String, Object?> expectedPreservedRows() => {
  'synced_playlists': [
    {
      'id': 1,
      'name': 'Brass',
      'path': '/playlists/brass',
      'type': 'static',
      'last_synced': 1000,
    },
    {
      'id': 2,
      'name': 'Soul',
      'path': '/playlists/soul',
      'type': 'static',
      'last_synced': 1000,
    },
  ],
  'playlist_cache': [
    {
      'id': 1,
      'name': 'Brass',
      'path': '/playlists/brass',
      'type': 'static',
      'item_count': 33,
      'last_fetched': 1000,
    },
  ],
  // The three new columns land on pre-existing rows with their defaults:
  // content_uri NULL (v4 ADD COLUMN carries no default), rating 0 (NOT NULL
  // DEFAULT 0), artwork_source NULL.
  'synced_tracks': [
    {
      'id': 1,
      'title': 'Track One',
      'artist': 'Artist A',
      'album': 'Album X',
      'album_artist': 'AA X',
      'local_path': '/music/t1.mp3',
      'server_path': '/media/t1.mp3',
      'download_timestamp': 111,
      'file_size': 1000000,
      'genre': 'Jazz',
      'length_ms': 60000,
      'track_number': 1,
      'disc_number': 1,
      'year': 1970,
      'artwork_url': '/artwork/item/1',
      'artwork_path': '',
      'content_uri': null,
      'rating': 0,
      'artwork_source': null,
    },
    {
      'id': 2,
      'title': 'Track Two',
      'artist': 'Artist B',
      'album': 'Album Y',
      'album_artist': 'AA Y',
      'local_path': '/music/t2.mp3',
      'server_path': '/media/t2.mp3',
      'download_timestamp': 222,
      'file_size': 2000000,
      'genre': '',
      'length_ms': 0,
      'track_number': 0,
      'disc_number': 0,
      'year': 0,
      'artwork_url': '',
      'artwork_path': '',
      'content_uri': null,
      'rating': 0,
      'artwork_source': null,
    },
    {
      'id': 3,
      'title': 'Track Three',
      'artist': 'Artist C',
      'album': 'Album Z',
      'album_artist': 'AA Z',
      'local_path': '/music/t3.mp3',
      'server_path': '/media/t3.mp3',
      'download_timestamp': 333,
      'file_size': 3000000,
      'genre': '',
      'length_ms': 300000,
      'track_number': 0,
      'disc_number': 0,
      'year': 1990,
      'artwork_url': '',
      'artwork_path': '',
      'content_uri': null,
      'rating': 0,
      'artwork_source': null,
    },
  ],
  'playlist_tracks': [
    {'playlist_id': 1, 'track_id': 1},
    {'playlist_id': 1, 'track_id': 2},
    {'playlist_id': 2, 'track_id': 3},
  ],
  'pending_events': [
    {
      'id': 1,
      'track_id': 1,
      'event_type': 'play',
      'timestamp': 12345,
      'synced': 0,
      'retry_count': 0,
    },
  ],
  // The v3 history row survives with the v6-added columns NULL.
  'sync_history': [
    {
      'id': 1,
      'timestamp': 1000,
      'status': 'success',
      'playlists_synced': 2,
      'tracks_downloaded': 3,
      'tracks_deleted': 0,
      'error_message': null,
      'duration_ms': 1234,
      'trigger_type': 'manual',
      'plays_synced': null,
      'skips_synced': null,
    },
  ],
  'sync_history_playlists': [
    {
      'id': 1,
      'sync_id': 1,
      'playlist_id': 1,
      'playlist_name': 'Brass',
      'tracks_in_playlist': 33,
      'error_message': null,
    },
    {
      'id': 2,
      'sync_id': 1,
      'playlist_id': 2,
      'playlist_name': 'Soul',
      'tracks_in_playlist': 62,
      'error_message': null,
    },
  ],
};

/// Structural equality for the snapshot/row maps (which cross an isolate
/// boundary as plain data, so `==` on maps would compare by identity).
bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

String _describeColumn(Map<String, Object?> c) =>
    '${c['name']} ${c['type']} notnull=${c['notnull']} '
    'dflt=${c['dflt_value']} pk=${c['pk']}';

/// Every structural difference between two [snapshotSchema] results, as
/// human-readable strings (empty list = identical).
List<String> schemaDiffs(Map<String, Object?> a, Map<String, Object?> b) {
  final diffs = <String>[];
  if (a['user_version'] != b['user_version']) {
    diffs.add(
      'user_version: fresh=${a['user_version']} migrated=${b['user_version']}',
    );
  }
  final ta = (a['tables']! as Map).cast<String, Object?>();
  final tb = (b['tables']! as Map).cast<String, Object?>();
  final names = {...ta.keys, ...tb.keys}.toList()..sort();
  for (final name in names) {
    if (!ta.containsKey(name)) {
      diffs.add('table "$name": missing from fresh');
      continue;
    }
    if (!tb.containsKey(name)) {
      diffs.add('table "$name": missing from migrated');
      continue;
    }
    final aTable = (ta[name]! as Map).cast<String, Object?>();
    final bTable = (tb[name]! as Map).cast<String, Object?>();

    final aCols = (aTable['columns']! as List).cast<Map<String, Object?>>();
    final bCols = (bTable['columns']! as List).cast<Map<String, Object?>>();
    if (aCols.length != bCols.length) {
      diffs.add(
        'table "$name": ${aCols.length} columns fresh vs ${bCols.length} migrated',
      );
    }
    for (var i = 0; i < aCols.length && i < bCols.length; i++) {
      if (!deepEquals(aCols[i], bCols[i])) {
        diffs.add(
          'table "$name" column #$i: '
          'fresh=[${_describeColumn(aCols[i])}] migrated=[${_describeColumn(bCols[i])}]',
        );
      }
    }

    final aIdx = (aTable['indexes']! as Map).cast<String, Object?>();
    final bIdx = (bTable['indexes']! as Map).cast<String, Object?>();
    for (final idx in {...aIdx.keys, ...bIdx.keys}.toList()..sort()) {
      if (!aIdx.containsKey(idx)) {
        diffs.add('table "$name": index "$idx" missing from fresh');
      } else if (!bIdx.containsKey(idx)) {
        diffs.add('table "$name": index "$idx" missing from migrated');
      } else if (!deepEquals(aIdx[idx], bIdx[idx])) {
        diffs.add('table "$name" index "$idx": ${aIdx[idx]} vs ${bIdx[idx]}');
      }
    }

    final aFk = aTable['foreign_keys']! as List;
    final bFk = bTable['foreign_keys']! as List;
    if (aFk.length != bFk.length) {
      diffs.add(
        'table "$name": ${aFk.length} foreign keys fresh vs ${bFk.length} migrated',
      );
    } else {
      for (var i = 0; i < aFk.length; i++) {
        if (!deepEquals(aFk[i], bFk[i])) {
          diffs.add('table "$name" foreign key #$i: ${aFk[i]} vs ${bFk[i]}');
        }
      }
    }
  }
  return diffs;
}

/// Sets up the FFI factory in a fresh isolate and clears the DB file.
/// Every lifecycle runs in its own isolate because `DatabaseHelper` caches
/// its `Database` in a static that `close()` never clears.
Future<void> prepareFreshIsolate() async {
  databaseFactory = databaseFactoryFfiNoIsolate;
  final file = File(dbFilePath());
  if (file.existsSync()) file.deleteSync();
}

/// Fresh-install v8: `DatabaseHelper` creates the file, running the
/// production `_createDB`. Returns the normalised schema.
Future<Map<String, Object?>> freshV8Lifecycle() async {
  await prepareFreshIsolate();
  final db = await DatabaseHelper.instance.database;
  try {
    return await snapshotSchema(db);
  } finally {
    await db.close();
  }
}

/// The full upgrade path every v0.1.8 user ran: v3 fixture (seeded) ->
/// production `_onUpgrade(3, 8)`. Returns schema + the surviving rows.
Future<Map<String, Object?>> seededV3ToV8Lifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 3, seed: true);
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final expectedTables = expectedPreservedRows().keys.toList()..sort();
    final rows = <String, Object?>{};
    for (final table in expectedTables) {
      // playlist_tracks has no id column (composite PK).
      final orderBy =
          table == 'playlist_tracks' ? 'playlist_id, track_id' : 'id';
      rows[table] = await migrated.query(table, orderBy: orderBy);
    }
    return {
      'schema': await snapshotSchema(migrated),
      'rows': rows,
    };
  } finally {
    await migrated.close();
  }
}

/// v4 fixture (content_uri present, v5 purge not yet run) -> open at 8.
/// The v5 purge must blank every cached URI lacking a `/tree/` segment.
Future<Map<String, Object?>> v5PurgeLifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 4);
  const bareUri =
      'content://com.android.externalstorage.documents/document/primary%3AMusic%2Fa.mp3';
  const treeUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fb.mp3';
  final urisById = {1: bareUri, 2: treeUri, 3: null, 4: ''};
  for (final id in urisById.keys.toList()..sort()) {
    await db.insert('synced_tracks', {
      'id': id,
      'title': 'T$id',
      'artist': 'A',
      'album': 'AL',
      'album_artist': 'AA',
      'local_path': '/l$id',
      'server_path': '/s$id',
      'download_timestamp': 1,
      'file_size': 1,
      'content_uri': urisById[id],
    });
  }
  await db.execute('PRAGMA user_version = 4');
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final rows = await migrated
        .query('synced_tracks', columns: ['id', 'content_uri'], orderBy: 'id');
    return {
      'uris': rows.map((r) => r['content_uri']).toList(),
      'user_version':
          (await migrated.rawQuery('PRAGMA user_version')).first.values.first,
    };
  } finally {
    await migrated.close();
  }
}

/// v5 fixture (v3 lineage: sync_history lacks the event columns) plus
/// sync_history_playlists orphans (sync_id = -1, the historical bug shape,
/// and sync_id = 999) -> open at 8. The v6 step must add the columns,
/// delete the orphans, and create playback_state.
Future<Map<String, Object?>> v6Lifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 5);
  await db.insert('sync_history', {
    'timestamp': 1000,
    'status': 'success',
    'playlists_synced': 1,
    'tracks_downloaded': 1,
    'tracks_deleted': 0,
    'error_message': null,
    'duration_ms': 1,
    'trigger_type': 'manual',
  });
  await db.insert('sync_history_playlists', {
    'sync_id': 1,
    'playlist_id': 1,
    'playlist_name': 'Kept',
    'tracks_in_playlist': 1,
    'error_message': null,
  });
  await db.insert('sync_history_playlists', {
    'sync_id': -1,
    'playlist_id': 2,
    'playlist_name': 'OrphanNegOne',
    'tracks_in_playlist': 1,
    'error_message': null,
  });
  await db.insert('sync_history_playlists', {
    'sync_id': 999,
    'playlist_id': 3,
    'playlist_name': 'OrphanNineHundredNinetyNine',
    'tracks_in_playlist': 1,
    'error_message': null,
  });
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final historyColumns =
        (await migrated.rawQuery('PRAGMA table_info(sync_history)'))
            .map((c) => c['name'] as String)
            .toList();
    final children = await migrated.query(
      'sync_history_playlists',
      columns: ['id', 'sync_id', 'playlist_name'],
      orderBy: 'id',
    );
    final tables = (
      await migrated.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
    ).map((r) => r['name'] as String).toSet();
    return {
      'history_columns': historyColumns,
      'children': children,
      'tables': tables.toList(),
      'user_version':
          (await migrated.rawQuery('PRAGMA user_version')).first.values.first,
    };
  } finally {
    await migrated.close();
  }
}

/// v6 fixture -> open at 8. The v7 step must add `rating` and create
/// `pending_track_edits`.
Future<Map<String, Object?>> v7Lifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 6, seed: true);
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final rating = (await migrated.rawQuery('PRAGMA table_info(synced_tracks)'))
        .firstWhere((c) => c['name'] == 'rating');
    final tables = (
      await migrated.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
    ).map((r) => r['name'] as String).toSet();
    final editsColumns = (
      await migrated.rawQuery('PRAGMA table_info(pending_track_edits)')
    )
        .map((c) => c['name'] as String)
        .toList();
    final seededRating = (
      await migrated
          .query('synced_tracks', columns: ['id', 'rating'], where: 'id = 1')
    ).first['rating'];
    return {
      'rating': rating,
      'tables': tables.toList(),
      'pending_track_edits_columns': editsColumns,
      'seeded_track_rating': seededRating,
    };
  } finally {
    await migrated.close();
  }
}

/// v7 fixture -> open at 8. The v8 step must add `artwork_source`.
Future<Map<String, Object?>> v8Lifecycle() async {
  await prepareFreshIsolate();
  await prepareFixtureForV8Step();
  final migrated = await DatabaseHelper.instance.database;
  try {
    final artwork = (
      await migrated.rawQuery('PRAGMA table_info(synced_tracks)')
    ).firstWhere((c) => c['name'] == 'artwork_source');
    return {'artwork_source': artwork};
  } finally {
    await migrated.close();
  }
}

Future<void> prepareFixtureForV8Step() async {
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 7);
  await db.close();
}

/// v5 fixture whose sync_history ALREADY has plays_synced/skips_synced
/// (the shape of a DB that came up through the old v2->v3 migration). The
/// v6 step's PRAGMA guard must skip the ADD COLUMNs, not fail or
/// double-add.
Future<Map<String, Object?>> v6IdempotentLifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 5);
  await db.execute(v6AddPlaysSynced);
  await db.execute(v6AddSkipsSynced);
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final columns = (await migrated.rawQuery('PRAGMA table_info(sync_history)'))
        .map((c) => c['name'] as String)
        .toList();
    return {
      'columns': columns,
      'user_version':
          (await migrated.rawQuery('PRAGMA user_version')).first.values.first,
    };
  } finally {
    await migrated.close();
  }
}

/// v7 fixture whose synced_tracks ALREADY has artwork_source. The v8 step's
/// guard must skip the ADD COLUMN, not fail or double-add.
Future<Map<String, Object?>> v8IdempotentLifecycle() async {
  await prepareFreshIsolate();
  final db = await openDatabase(dbFilePath());
  await buildFixtureAtVersion(db, 7);
  await db.execute(v8AddArtworkSource);
  await db.close();

  final migrated = await DatabaseHelper.instance.database;
  try {
    final columns = (await migrated.rawQuery('PRAGMA table_info(synced_tracks)'))
        .where((c) => c['name'] == 'artwork_source')
        .toList();
    return {
      'artwork_source_column_count': columns.length,
      'user_version':
          (await migrated.rawQuery('PRAGMA user_version')).first.values.first,
    };
  } finally {
    await migrated.close();
  }
}
