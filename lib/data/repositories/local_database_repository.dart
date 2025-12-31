import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/playlist.dart';

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
    };
  }

  factory SyncedTrack.fromMap(Map<String, dynamic> map) {
    return SyncedTrack(
      id: map['id'],
      title: map['title'],
      artist: map['artist'],
      album: map['album'],
      albumArtist: map['album_artist'],
      localPath: map['local_path'],
      serverPath: map['server_path'],
      downloadTimestamp: map['download_timestamp'],
      fileSize: map['file_size'],
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
}
