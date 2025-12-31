class SyncHistoryRecord {
  final int? id;
  final int timestamp;
  final String status; // 'success', 'failed', 'cancelled', 'skipped'
  final int playlistsSynced;
  final int tracksDownloaded;
  final int tracksDeleted;
  final String? errorMessage;
  final int? durationMs;
  final String triggerType; // 'manual', 'scheduled'
  final List<SyncHistoryPlaylist>? playlists;

  SyncHistoryRecord({
    this.id,
    required this.timestamp,
    required this.status,
    this.playlistsSynced = 0,
    this.tracksDownloaded = 0,
    this.tracksDeleted = 0,
    this.errorMessage,
    this.durationMs,
    required this.triggerType,
    this.playlists,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp,
      'status': status,
      'playlists_synced': playlistsSynced,
      'tracks_downloaded': tracksDownloaded,
      'tracks_deleted': tracksDeleted,
      'error_message': errorMessage,
      'duration_ms': durationMs,
      'trigger_type': triggerType,
    };
  }

  factory SyncHistoryRecord.fromMap(Map<String, dynamic> map) {
    return SyncHistoryRecord(
      id: map['id'] as int?,
      timestamp: map['timestamp'] as int,
      status: map['status'] as String,
      playlistsSynced: map['playlists_synced'] as int? ?? 0,
      tracksDownloaded: map['tracks_downloaded'] as int? ?? 0,
      tracksDeleted: map['tracks_deleted'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
      durationMs: map['duration_ms'] as int?,
      triggerType: map['trigger_type'] as String,
    );
  }
}

class SyncHistoryPlaylist {
  final int? id;
  final int syncId;
  final int playlistId;
  final String playlistName;
  final int tracksInPlaylist;

  SyncHistoryPlaylist({
    this.id,
    required this.syncId,
    required this.playlistId,
    required this.playlistName,
    this.tracksInPlaylist = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'playlist_id': playlistId,
      'playlist_name': playlistName,
      'tracks_in_playlist': tracksInPlaylist,
    };
  }

  factory SyncHistoryPlaylist.fromMap(Map<String, dynamic> map) {
    return SyncHistoryPlaylist(
      id: map['id'] as int?,
      syncId: map['sync_id'] as int,
      playlistId: map['playlist_id'] as int,
      playlistName: map['playlist_name'] as String,
      tracksInPlaylist: map['tracks_in_playlist'] as int? ?? 0,
    );
  }
}
