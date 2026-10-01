import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/playlist.dart';
import '../models/sync_history.dart';

class SyncedPlaylist {
  final int id;
  final String name;
  final String path;
  final String type;
  final int lastSynced;

  SyncedPlaylist({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.lastSynced,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'type': type,
      'last_synced': lastSynced,
    };
  }

  factory SyncedPlaylist.fromMap(Map<String, dynamic> map) {
    return SyncedPlaylist(
      id: map['id'],
      name: map['name'],
      path: map['path'],
      type: map['type'],
      lastSynced: map['last_synced'],
    );
  }
}

class SyncedTrack {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String localPath;
  final String serverPath;
  final int downloadTimestamp;
  final int fileSize;
  final String genre;
  final int lengthMs;
  final int trackNumber;
  final int discNumber;
  final int year;
  final String artworkUrl;
  final String? artworkPath;
  final String? contentUri;

  /// 0-100. The last-known server value when no edit is pending; the user's
  /// value while a pending_track_edits row for this track exists (so display
  /// stays a plain column read).
  final int rating;

  SyncedTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.localPath,
    required this.serverPath,
    required this.downloadTimestamp,
    required this.fileSize,
    this.genre = '',
    this.lengthMs = 0,
    this.trackNumber = 0,
    this.discNumber = 0,
    this.year = 0,
    this.artworkUrl = '',
    this.artworkPath,
    this.contentUri,
    this.rating = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'album_artist': albumArtist,
      'local_path': localPath,
      'server_path': serverPath,
      'download_timestamp': downloadTimestamp,
      'file_size': fileSize,
      'genre': genre,
      'length_ms': lengthMs,
      'track_number': trackNumber,
      'disc_number': discNumber,
      'year': year,
      'artwork_url': artworkUrl,
      'artwork_path': artworkPath,
      'content_uri': contentUri,
      'rating': rating,
    };
  }

  factory SyncedTrack.fromMap(Map<String, dynamic> map) {
    return SyncedTrack(
      id: map['id'] as int,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      albumArtist: map['album_artist'] as String,
      localPath: map['local_path'] as String,
      serverPath: map['server_path'] as String,
      downloadTimestamp: map['download_timestamp'] as int,
      fileSize: map['file_size'] as int,
      genre: map['genre'] as String? ?? '',
      lengthMs: map['length_ms'] as int? ?? 0,
      trackNumber: map['track_number'] as int? ?? 0,
      discNumber: map['disc_number'] as int? ?? 0,
      year: map['year'] as int? ?? 0,
      artworkUrl: map['artwork_url'] as String? ?? '',
      artworkPath: map['artwork_path'] as String?,
      contentUri: map['content_uri'] as String?,
      rating: map['rating'] as int? ?? 0,
    );
  }
}

class PendingEvent {
  final int? id;
  final int trackId;
  final String eventType; // 'play' or 'skip'
  final int timestamp;
  final bool synced;
  final int retryCount;

  PendingEvent({
    this.id,
    required this.trackId,
    required this.eventType,
    required this.timestamp,
    this.synced = false,
    this.retryCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'track_id': trackId,
      'event_type': eventType,
      'timestamp': timestamp,
      'synced': synced ? 1 : 0,
      'retry_count': retryCount,
    };
  }

  factory PendingEvent.fromMap(Map<String, dynamic> map) {
    return PendingEvent(
      id: map['id'],
      trackId: map['track_id'],
      eventType: map['event_type'],
      timestamp: map['timestamp'],
      synced: map['synced'] == 1,
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }
}

/// The persisted playback state (A8), stored as the single playback_state
/// row. [queueIds] is the queue in BASE order (the player's sequence), and
/// [shuffleIndices] the base indices in play order at the moment of saving
/// (identity when shuffle is off). Restoring replays both, so the user gets
/// back the same queue, the same current track, and the same "next track".
class PlaybackStateRecord {
  final List<int> queueIds;
  final int? currentTrackId;
  final int positionMs;
  final bool shuffleEnabled;
  final List<int> shuffleIndices;
  final String repeatMode; // 'none' | 'one' | 'all'
  final String? originKind;
  final int? originId;
  final String? originName;

  PlaybackStateRecord({
    required this.queueIds,
    this.currentTrackId,
    required this.positionMs,
    required this.shuffleEnabled,
    required this.shuffleIndices,
    required this.repeatMode,
    this.originKind,
    this.originId,
    this.originName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'queue_ids': jsonEncode(queueIds),
      'current_track_id': currentTrackId,
      'position_ms': positionMs,
      'shuffle_enabled': shuffleEnabled ? 1 : 0,
      'shuffle_indices': jsonEncode(shuffleIndices),
      'repeat_mode': repeatMode,
      'origin_kind': originKind,
      'origin_id': originId,
      'origin_name': originName,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory PlaybackStateRecord.fromMap(Map<String, dynamic> map) {
    List<int> parseIntList(String? raw) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        return (jsonDecode(raw) as List<dynamic>)
            .map((e) => (e as num).toInt())
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return PlaybackStateRecord(
      queueIds: parseIntList(map['queue_ids'] as String?),
      currentTrackId: map['current_track_id'] as int?,
      positionMs: map['position_ms'] as int? ?? 0,
      shuffleEnabled: (map['shuffle_enabled'] as int? ?? 0) == 1,
      shuffleIndices: parseIntList(map['shuffle_indices'] as String?),
      repeatMode: map['repeat_mode'] as String? ?? 'none',
      originKind: map['origin_kind'] as String?,
      originId: map['origin_id'] as int?,
      originName: map['origin_name'] as String?,
    );
  }
}

/// A pending field-edit row from `pending_track_edits`.
class PendingTrackEditRow {
  final String baseValue;
  final String newValue;
  final int updatedAt;

  PendingTrackEditRow({
    required this.baseValue,
    required this.newValue,
    required this.updatedAt,
  });
}

/// Grouped results of a library search.
class LibrarySearchResult {
  final List<Map<String, dynamic>> playlists;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;
  final List<SyncedTrack> tracks;

  const LibrarySearchResult({
    required this.playlists,
    required this.artists,
    required this.albums,
    required this.tracks,
  });
}

class LocalDatabaseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Playlist operations
  Future<void> insertOrUpdatePlaylist(SyncedPlaylist playlist) async {
    final db = await _dbHelper.database;
    await db.insert(
      'synced_playlists',
      playlist.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SyncedPlaylist?> getPlaylistById(int id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'synced_playlists',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return SyncedPlaylist.fromMap(results.first);
  }

  Future<SyncedPlaylist?> getPlaylistByPath(String path) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'synced_playlists',
      where: 'path = ?',
      whereArgs: [path],
    );

    if (results.isEmpty) return null;
    return SyncedPlaylist.fromMap(results.first);
  }

  Future<List<SyncedPlaylist>> getAllPlaylists() async {
    final db = await _dbHelper.database;
    final results = await db.query('synced_playlists');
    return results.map((map) => SyncedPlaylist.fromMap(map)).toList();
  }

  Future<void> deletePlaylist(int id) async {
    final db = await _dbHelper.database;
    await db.delete('synced_playlists', where: 'id = ?', whereArgs: [id]);
  }

  // Track operations
  Future<SyncedTrack?> getTrackById(int id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'synced_tracks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return SyncedTrack.fromMap(results.first);
  }

  Future<List<SyncedTrack>> getTracksForPlaylist(int playlistId) async {
    final db = await _dbHelper.database;

    final results = await db.rawQuery(
      '''
      SELECT st.* FROM synced_tracks st
      INNER JOIN playlist_tracks pt ON st.id = pt.track_id
      WHERE pt.playlist_id = ?
    ''',
      [playlistId],
    );

    return results.map((map) => SyncedTrack.fromMap(map)).toList();
  }

  Future<List<SyncedTrack>> getOrphanedTracks() async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT st.* FROM synced_tracks st
      LEFT JOIN playlist_tracks pt ON st.id = pt.track_id
      WHERE pt.track_id IS NULL
    ''');

    return results.map((map) => SyncedTrack.fromMap(map)).toList();
  }

  Future<void> deleteTrack(int id) async {
    final db = await _dbHelper.database;
    await db.delete('synced_tracks', where: 'id = ?', whereArgs: [id]);
  }

  /// Cache resolved content URIs back onto tracks so the expensive
  /// document-ID resolution is paid once, not on every play.
  Future<void> updateTracksContentUri(Map<int, String> trackUris) async {
    if (trackUris.isEmpty) return;
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final entry in trackUris.entries) {
        await txn.update(
          'synced_tracks',
          {'content_uri': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  // Pending track-edit operations (last-write-wins field edits; the
  // composite primary key (track_id, field) keeps one row per field).

  Future<PendingTrackEditRow?> getPendingTrackEdit(
    int trackId,
    String field,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pending_track_edits',
      where: 'track_id = ? AND field = ?',
      whereArgs: [trackId, field],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PendingTrackEditRow(
      baseValue: row['base_value'] as String,
      newValue: row['new_value'] as String,
      updatedAt: row['updated_at'] as int,
    );
  }

  Future<void> insertPendingTrackEdit({
    required int trackId,
    required String field,
    required String newValue,
    required String baseValue,
  }) async {
    final db = await _dbHelper.database;
    await db.insert('pending_track_edits', {
      'track_id': trackId,
      'field': field,
      'new_value': newValue,
      'base_value': baseValue,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Overwrites only `new_value`/`updated_at` of an existing edit. The
  /// original `base_value` is preserved — it stays anchored to the server
  /// truth the first edit was made against, which is what lets the sync
  /// worker detect a later server-side change. Overwriting it with the
  /// user's previous value destroys that detection.
  Future<void> updatePendingTrackEditValue({
    required int trackId,
    required String field,
    required String newValue,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_track_edits',
      {'new_value': newValue, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'track_id = ? AND field = ?',
      whereArgs: [trackId, field],
    );
  }

  /// Sets the rating (0-100) of [trackId] locally and records it as a
  /// pending edit so the sync worker pushes it at the next sync.
  ///
  /// While a pending edit exists, [SyncedTrack.rating] holds the user's
  /// value (display stays a plain column read); the edit row's `base_value`
  /// holds what the server had when the first edit was made.
  Future<void> setTrackRating(int trackId, int rating) async {
    final clamped = rating.clamp(0, 100);
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'pending_track_edits',
        columns: ['base_value'],
        where: 'track_id = ? AND field = ?',
        whereArgs: [trackId, 'rating'],
      );
      String baseValue;
      if (existing.isEmpty) {
        // No pending edit: the rating column IS the last-known server value.
        // Read it BEFORE the update below.
        final rows = await txn.query(
          'synced_tracks',
          columns: ['rating'],
          where: 'id = ?',
          whereArgs: [trackId],
        );
        final current = rows.isEmpty ? 0 : (rows.first['rating'] as int? ?? 0);
        if (current == clamped) return; // No-op release: nothing to record.
        baseValue = '$current';
      } else {
        baseValue = existing.first['base_value'] as String;
      }
      await txn.update(
        'synced_tracks',
        {'rating': clamped},
        where: 'id = ?',
        whereArgs: [trackId],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existing.isEmpty) {
        await txn.insert('pending_track_edits', {
          'track_id': trackId,
          'field': 'rating',
          'new_value': '$clamped',
          'base_value': baseValue,
          'updated_at': now,
        });
      } else {
        await txn.update(
          'pending_track_edits',
          {'new_value': '$clamped', 'updated_at': now},
          where: 'track_id = ? AND field = ?',
          whereArgs: [trackId, 'rating'],
        );
      }
    });
  }

  // Playlist-Track relationship operations
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final db = await _dbHelper.database;
    await db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': trackId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
  }

  Future<void> clearPlaylistTracks(int playlistId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  // Pending event operations
  Future<int> insertEvent(PendingEvent event) async {
    final db = await _dbHelper.database;
    return await db.insert('pending_events', event.toMap());
  }

  Future<List<PendingEvent>> getUnsyncedEvents() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'pending_events',
      where: 'synced = ?',
      whereArgs: [0],
    );

    return results.map((map) => PendingEvent.fromMap(map)).toList();
  }

  Future<void> markEventAsSynced(int eventId) async {
    final db = await _dbHelper.database;
    await db.update(
      'pending_events',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> deleteEvent(int eventId) async {
    final db = await _dbHelper.database;
    await db.delete('pending_events', where: 'id = ?', whereArgs: [eventId]);
  }

  Future<void> incrementRetryCount(int eventId) async {
    final db = await _dbHelper.database;
    final existingEvents = await db.query(
      'pending_events',
      where: 'id = ?',
      whereArgs: [eventId],
    );
    
    if (existingEvents.isNotEmpty) {
      final retryCount = existingEvents.first['retry_count'] as int?;
      final newRetryCount = (retryCount ?? 0) + 1;
      await db.update(
        'pending_events',
        {'retry_count': newRetryCount},
        where: 'id = ?',
        whereArgs: [eventId],
      );
    }
  }

  Future<void> deleteEvents(List<int> eventIds) async {
    if (eventIds.isEmpty) return;
    final db = await _dbHelper.database;
    final placeholders = List.generate(eventIds.length, (_) => '?').join(',');
    await db.delete(
      'pending_events',
      where: 'id IN ($placeholders)',
      whereArgs: eventIds,
    );
  }

  Future<void> deleteSyncedEvents() async {
    final db = await _dbHelper.database;
    await db.delete('pending_events', where: 'synced = ?', whereArgs: [1]);
  }

  /// Count of playback events queued for the next sync (D3).
  Future<int> getPendingEventCount() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM pending_events WHERE synced = 0',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // Playback state persistence (A8)
  Future<void> savePlaybackState(PlaybackStateRecord state) async {
    final db = await _dbHelper.database;
    await db.insert(
      'playback_state',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PlaybackStateRecord?> loadPlaybackState() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'playback_state',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlaybackStateRecord.fromMap(rows.first);
  }

  Future<void> clearPlaybackState() async {
    final db = await _dbHelper.database;
    await db.delete('playback_state');
  }

  // Playlist cache operations
  Future<void> cachePlaylist(Playlist playlist) async {
    final db = await _dbHelper.database;
    await db.insert('playlist_cache', {
      'id': playlist.id,
      'name': playlist.name,
      'path': playlist.path,
      'type': playlist.type,
      'item_count': playlist.itemCount,
      'last_fetched': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCachedPlaylists() async {
    final db = await _dbHelper.database;
    return await db.query('playlist_cache', orderBy: 'name ASC');
  }

  Future<void> clearPlaylistCache() async {
    final db = await _dbHelper.database;
    await db.delete('playlist_cache');
  }

  /// Get all unique artists with track and album counts.
  ///
  /// The counts use the same membership rule as [getTracksByArtist]
  /// (`artist = X OR album_artist = X`), so the row's numbers match what the
  /// artist detail screen shows. A plain `GROUP BY artist` would count only
  /// exact-`artist` matches and understate feature credits.
  Future<List<Map<String, dynamic>>> getAllArtists(
    {String sortBy = 'artist'}
  ) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        a.artist AS artist,
        (SELECT COUNT(*) FROM synced_tracks t
          WHERE t.artist = a.artist OR t.album_artist = a.artist) AS track_count,
        (SELECT COUNT(DISTINCT t.album) FROM synced_tracks t
          WHERE t.artist = a.artist OR t.album_artist = a.artist) AS album_count
      FROM (SELECT DISTINCT artist FROM synced_tracks WHERE artist != '') a
      ORDER BY a.artist ${sortBy == 'artist' ? 'ASC' : 'DESC'}
    ''');
    return result;
  }

  /// Get all unique albums with artist info and track count
  Future<List<Map<String, dynamic>>> getAllAlbums({
    String sortBy = 'album',
  }) async {
    final db = await _dbHelper.database;

    String orderByClause;
    switch (sortBy) {
      case 'artist':
        orderByClause = 'album_artist ASC, album ASC';
        break;
      case 'year':
        orderByClause = 'year DESC, album ASC';
        break;
      default:
        orderByClause = 'album ASC';
    }

    final result = await db.rawQuery('''
      SELECT
        album,
        album_artist,
        year,
        artwork_path,
        COUNT(*) AS track_count
      FROM synced_tracks
      GROUP BY album, album_artist, year, artwork_path
      ORDER BY $orderByClause
    ''');

    return result;
  }

  /// Get tracks by artist
  Future<List<SyncedTrack>> getTracksByArtist(
    String artist, {
    String sortBy = 'album',
  }) async {
    final db = await _dbHelper.database; // Changed this line

    String orderByClause;
    switch (sortBy) {
      case 'title':
        orderByClause = 'title ASC';
        break;
      case 'album':
        orderByClause = 'album ASC, disc_number ASC, track_number ASC';
        break;
      case 'year':
        orderByClause = 'year DESC, album ASC, track_number ASC';
        break;
      default:
        orderByClause = 'album ASC, disc_number ASC, track_number ASC';
    }

    final result = await db.query(
      'synced_tracks',
      where: 'artist = ? OR album_artist = ?',
      whereArgs: [artist, artist],
      orderBy: orderByClause,
    );

    return result.map((map) => SyncedTrack.fromMap(map)).toList();
  }

  /// Get tracks by album.
  ///
  /// Album names collide across artists in real libraries (this one has
  /// nine distinct albums named "Brass"), so the optional [albumArtist] and
  /// [year] narrow the match to one displayed album row. Callers that only
  /// know the name get the union of all same-named albums.
  Future<List<SyncedTrack>> getTracksByAlbum(
    String album, {
    String? albumArtist,
    int? year,
    String sortBy = 'track',
  }) async {
    final db = await _dbHelper.database;

    String orderByClause;
    switch (sortBy) {
      case 'title':
        orderByClause = 'title ASC';
        break;
      case 'track':
        orderByClause = 'disc_number ASC, track_number ASC';
        break;
      default:
        orderByClause = 'disc_number ASC, track_number ASC';
    }

    final where = StringBuffer('album = ?');
    final args = <Object?>[album];
    if (albumArtist != null) {
      where.write(' AND album_artist = ?');
      args.add(albumArtist);
    }
    if (year != null) {
      where.write(' AND year = ?');
      args.add(year);
    }

    final result = await db.query(
      'synced_tracks',
      where: where.toString(),
      whereArgs: args,
      orderBy: orderByClause,
    );

    return result.map((map) => SyncedTrack.fromMap(map)).toList();
  }

  /// Get all tracks
  Future<List<SyncedTrack>> getAllTracks({String sortBy = 'title'}) async {
    final db = await _dbHelper.database; // Changed this line

    String orderByClause;
    switch (sortBy) {
      case 'title':
        orderByClause = 'title ASC';
        break;
      case 'artist':
        orderByClause = 'artist ASC, album ASC, track_number ASC';
        break;
      case 'album':
        orderByClause = 'album ASC, track_number ASC';
        break;
      case 'year':
        orderByClause = 'year DESC';
        break;
      case 'dateAdded':
        orderByClause = 'download_timestamp DESC';
        break;
      default:
        orderByClause = 'title ASC';
    }

    final result = await db.query('synced_tracks', orderBy: orderByClause);

    return result.map((map) => SyncedTrack.fromMap(map)).toList();
  }

  /// Get synced playlists with track counts
  Future<List<Map<String, dynamic>>> getAllPlaylistsWithCounts({
    bool nameDesc = false,
  }) async {
    final db = await _dbHelper.database;

    final result = await db.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.path,
        p.type,
        p.last_synced,
        COUNT(pt.track_id) as track_count
      FROM synced_playlists p
      LEFT JOIN playlist_tracks pt ON p.id = pt.playlist_id
      GROUP BY p.id
      ORDER BY p.name ${nameDesc ? 'DESC' : 'ASC'}
    ''');

    return result;
  }

  /// Search the synced library by track title, artist, album, and playlist
  /// name. Matching is case-insensitive: the column side is folded with
  /// SQLite's `LOWER` (ASCII) and the query side with Dart's Unicode-aware
  /// `toLowerCase()`, which stock SQLite's `LIKE`/`NOCASE` cannot do alone.
  Future<LibrarySearchResult> searchLibrary(String query) async {
    if (query.trim().isEmpty) {
      return const LibrarySearchResult(
        playlists: [],
        artists: [],
        albums: [],
        tracks: [],
      );
    }
    final db = await _dbHelper.database;
    final escaped = query
        .trim()
        .toLowerCase()
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final q = '%$escaped%';

    final playlists = await db.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.path,
        p.type,
        p.last_synced,
        COUNT(pt.track_id) as track_count
      FROM synced_playlists p
      LEFT JOIN playlist_tracks pt ON p.id = pt.playlist_id
      WHERE LOWER(p.name) LIKE ? ESCAPE '\\'
      GROUP BY p.id
      ORDER BY p.name ASC
      LIMIT 20
    ''', [q]);

    final artists = await db.rawQuery('''
      SELECT
        artist AS artist,
        COUNT(*) AS track_count,
        COUNT(DISTINCT album) AS album_count
      FROM synced_tracks
      WHERE artist != '' AND LOWER(artist) LIKE ? ESCAPE '\\'
      GROUP BY artist
      ORDER BY artist ASC
      LIMIT 20
    ''', [q]);

    final albums = await db.rawQuery('''
      SELECT
        album,
        album_artist,
        year,
        artwork_path,
        COUNT(*) AS track_count
      FROM synced_tracks
      WHERE LOWER(album) LIKE ? ESCAPE '\\'
        OR LOWER(album_artist) LIKE ? ESCAPE '\\'
      GROUP BY album, album_artist, year, artwork_path
      ORDER BY album ASC
      LIMIT 20
    ''', [q, q]);

    final trackRows = await db.rawQuery('''
      SELECT st.*
      FROM synced_tracks st
      WHERE LOWER(st.title) LIKE ? ESCAPE '\\'
        OR LOWER(st.artist) LIKE ? ESCAPE '\\'
        OR LOWER(st.album) LIKE ? ESCAPE '\\'
      ORDER BY st.title ASC
      LIMIT 100
    ''', [q, q, q]);

    return LibrarySearchResult(
      playlists: playlists,
      artists: artists,
      albums: albums,
      tracks: trackRows.map((map) => SyncedTrack.fromMap(map)).toList(),
    );
  }

  /// Get multiple tracks by IDs in a single query
  Future<Map<int, SyncedTrack>> getTracksByIds(List<int> ids) async {
    if (ids.isEmpty) return {};

    final db = await _dbHelper.database;
    final tracks = <int, SyncedTrack>{};

    for (var i = 0; i < ids.length; i += 999) {
      final chunk = ids.sublist(i, (i + 999).clamp(0, ids.length));
      final placeholders = chunk.map((_) => '?').join(',');
      final results = await db.query(
        'synced_tracks',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final map in results) {
        final track = SyncedTrack.fromMap(map);
        tracks[track.id] = track;
      }
    }

    return tracks;
  }

  // Sync history operations
  Future<int> insertSyncHistory(SyncHistoryRecord record) async {
    final db = await _dbHelper.database;
    return await db.insert('sync_history', record.toMap());
  }

  Future<void> insertSyncHistoryPlaylist(SyncHistoryPlaylist playlist) async {
    final db = await _dbHelper.database;
    await db.insert('sync_history_playlists', playlist.toMap());
  }

  Future<List<SyncHistoryRecord>> getSyncHistory({int limit = 100}) async {
    final db = await _dbHelper.database;

    // Get records from last 30 days or last 100, whichever is smaller
    final thirtyDaysAgo = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final results = await db.query(
      'sync_history',
      where: 'timestamp > ?',
      whereArgs: [thirtyDaysAgo],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    final records = <SyncHistoryRecord>[];
    for (final map in results) {
      final record = SyncHistoryRecord.fromMap(map);

      // Load playlists for this sync
      final playlistResults = await db.query(
        'sync_history_playlists',
        where: 'sync_id = ?',
        whereArgs: [record.id],
      );

      final playlists = playlistResults
          .map((m) => SyncHistoryPlaylist.fromMap(m))
          .toList();

      records.add(
        SyncHistoryRecord(
          id: record.id,
          timestamp: record.timestamp,
          status: record.status,
          playlistsSynced: record.playlistsSynced,
          tracksDownloaded: record.tracksDownloaded,
          tracksDeleted: record.tracksDeleted,
          playsSynced: record.playsSynced,
          skipsSynced: record.skipsSynced,
          errorMessage: record.errorMessage,
          durationMs: record.durationMs,
          triggerType: record.triggerType,
          playlists: playlists,
        ),
      );
    }

    return records;
  }

  Future<void> cleanOldSyncHistory() async {
    final db = await _dbHelper.database;

    // Delete records older than 30 days
    final thirtyDaysAgo = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db.delete(
      'sync_history',
      where: 'timestamp < ?',
      whereArgs: [thirtyDaysAgo],
    );

    // Keep only last 100 records
    await db.rawDelete('''
      DELETE FROM sync_history
      WHERE id NOT IN (
        SELECT id FROM sync_history
        ORDER BY timestamp DESC
        LIMIT 100
      )
    ''');
  }
}
