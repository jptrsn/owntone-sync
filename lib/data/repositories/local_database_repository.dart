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
    );
  }
}

class PendingEvent {
  final int? id;
  final int trackId;
  final String eventType; // 'play' or 'skip'
  final int timestamp;
  final bool synced;

  PendingEvent({
    this.id,
    required this.trackId,
    required this.eventType,
    required this.timestamp,
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'track_id': trackId,
      'event_type': eventType,
      'timestamp': timestamp,
      'synced': synced ? 1 : 0,
    };
  }

  factory PendingEvent.fromMap(Map<String, dynamic> map) {
    return PendingEvent(
      id: map['id'],
      trackId: map['track_id'],
      eventType: map['event_type'],
      timestamp: map['timestamp'],
      synced: map['synced'] == 1,
    );
  }
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
  Future<void> insertOrUpdateTrack(SyncedTrack track) async {
    final db = await _dbHelper.database;
    await db.insert(
      'synced_tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

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

  Future<void> deleteSyncedEvents() async {
    final db = await _dbHelper.database;
    await db.delete('pending_events', where: 'synced = ?', whereArgs: [1]);
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

  /// Get all unique artists
  Future<List<String>> getAllArtists({String sortBy = 'artist'}) async {
    final db = await _dbHelper.database; // Changed this line
    final result = await db.query(
      'synced_tracks',
      columns: ['DISTINCT artist'],
      orderBy: sortBy == 'artist' ? 'artist ASC' : 'artist DESC',
    );
    return result.map((row) => row['artist'] as String).toList();
  }

  /// Get all unique albums with artist info
  Future<List<Map<String, dynamic>>> getAllAlbums({
    String sortBy = 'album',
  }) async {
    final db = await _dbHelper.database; // Changed this line

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
      SELECT DISTINCT album, album_artist, year, artwork_path
      FROM synced_tracks
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

  /// Get tracks by album
  Future<List<SyncedTrack>> getTracksByAlbum(
    String album, {
    String sortBy = 'track',
  }) async {
    final db = await _dbHelper.database; // Changed this line

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

    final result = await db.query(
      'synced_tracks',
      where: 'album = ?',
      whereArgs: [album],
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
  Future<List<Map<String, dynamic>>> getAllPlaylistsWithCounts() async {
    final db = await _dbHelper.database; // Changed this line

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
      ORDER BY p.name ASC
    ''');

    return result;
  }

  /// Get multiple tracks by IDs in a single query
  Future<Map<int, SyncedTrack>> getTracksByIds(List<int> ids) async {
    if (ids.isEmpty) return {};

    final db = await _dbHelper.database;
    final placeholders = ids.map((_) => '?').join(',');
    final results = await db.query(
      'synced_tracks',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );

    final tracks = <int, SyncedTrack>{};
    for (final map in results) {
      final track = SyncedTrack.fromMap(map);
      tracks[track.id] = track;
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
