class SyncProgress {
  final String currentPlaylist;
  final int totalPlaylists;
  final int currentPlaylistIndex;
  final int totalTracks;
  final int downloadedTracks;
  final String? currentTrackTitle;
  final double? downloadProgress;

  SyncProgress({
    required this.currentPlaylist,
    required this.totalPlaylists,
    required this.currentPlaylistIndex,
    required this.totalTracks,
    required this.downloadedTracks,
    this.currentTrackTitle,
    this.downloadProgress,
  });
}

class SyncResult {
  final bool success;
  final String? error;
  final int playlistsSynced;
  final int tracksDownloaded;
  final int tracksDeleted;

  SyncResult({
    required this.success,
    this.error,
    this.playlistsSynced = 0,
    this.tracksDownloaded = 0,
    this.tracksDeleted = 0,
  });
}
