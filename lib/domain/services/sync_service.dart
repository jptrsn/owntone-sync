import 'dart:io';
import 'package:dio/dio.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/file_system_repository.dart';
import 'package:audiotags/audiotags.dart';

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
  final int eventsySynced;

  SyncResult({
    required this.success,
    this.error,
    this.playlistsSynced = 0,
    this.tracksDownloaded = 0,
    this.tracksDeleted = 0,
    this.eventsySynced = 0,
  });
}

class SyncService {
  final OwnToneApiRepository _apiRepo;
  final LocalDatabaseRepository _dbRepo;
  final FileSystemRepository _fileRepo;

  // Callback for progress updates
  void Function(SyncProgress)? onProgress;

  // User settings
  bool deleteOrphanedFiles = false;

  // Cancellation flag
  bool _cancelRequested = false;

  SyncService({
    required OwnToneApiRepository apiRepo,
    required LocalDatabaseRepository dbRepo,
    required FileSystemRepository fileRepo,
  }) : _apiRepo = apiRepo,
       _dbRepo = dbRepo,
       _fileRepo = fileRepo;

  /// Main sync operation
  /// Main sync operation
  Future<SyncResult> syncPlaylists(List<int> playlistIds) async {
    try {
      int playlistsSynced = 0;
      int tracksDownloaded = 0;
      int tracksDeleted = 0;
      _cancelRequested = false;

      // First, fetch all playlists to calculate total tracks
      final allPlaylistTracks = <int, List<Track>>{};
      int totalTracksToSync = 0;

      for (final playlistId in playlistIds) {
        final playlist = await _fetchPlaylistWithRecovery(playlistId);
        if (playlist != null) {
          final tracksResponse = await _apiRepo.getPlaylistTracks(
            playlist.id,
            limit: 10000,
          );
          allPlaylistTracks[playlistId] = tracksResponse.items;
          totalTracksToSync += tracksResponse.items.length;
        }
      }

      int totalTracksProcessed = 0;

      // Sync each playlist
      for (int i = 0; i < playlistIds.length; i++) {
        if (_cancelRequested) {
          _cancelRequested = false; // Reset for next sync
          return SyncResult(
            success: false,
            error: 'Sync cancelled by user',
            playlistsSynced: playlistsSynced,
            tracksDownloaded: tracksDownloaded,
          );
        }

        final playlistId = playlistIds[i];

        // Fetch playlist from server
        final playlist = await _fetchPlaylistWithRecovery(playlistId);
        if (playlist == null) {
          // Playlist not found even after recovery attempt
          continue;
        }

        onProgress?.call(
          SyncProgress(
            currentPlaylist: playlist.name,
            totalPlaylists: playlistIds.length,
            currentPlaylistIndex: i,
            totalTracks: totalTracksToSync,
            downloadedTracks: totalTracksProcessed,
          ),
        );

        // Sync this playlist
        final stats = await _syncPlaylist(
          playlist,
          i,
          playlistIds.length,
          totalTracksToSync,
          totalTracksProcessed,
        );
        tracksDownloaded += stats['downloaded'] as int;
        totalTracksProcessed += allPlaylistTracks[playlistId]!.length;
        playlistsSynced++;
      }

      // Remove playlists that are no longer selected
      final allLocalPlaylists = await _dbRepo.getAllPlaylists();
      final selectedIds = playlistIds.toSet();
      for (final localPlaylist in allLocalPlaylists) {
        if (!selectedIds.contains(localPlaylist.id)) {
          // Playlist no longer selected, remove it and its relationships
          await _dbRepo.clearPlaylistTracks(localPlaylist.id);
          await _dbRepo.deletePlaylist(localPlaylist.id);

          // Delete playlist file
          await _fileRepo.deletePlaylistFile(localPlaylist.name);
        }
      }

      // Post-sync cleanup
      if (deleteOrphanedFiles) {
        tracksDeleted = await _deleteOrphanedTracks();
      }

      return SyncResult(
        success: true,
        playlistsSynced: playlistsSynced,
        tracksDownloaded: tracksDownloaded,
        tracksDeleted: tracksDeleted,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Fetch playlist with ID change recovery
  Future<Playlist?> _fetchPlaylistWithRecovery(int playlistId) async {
    try {
      // Try to fetch by ID first
      final response = await _apiRepo.getPlaylists(limit: 1000);
      final playlist = response.items.firstWhere(
        (p) => p.id == playlistId,
        orElse: () => throw Exception('Playlist not found'),
      );

      // Check if we have this playlist locally
      final localPlaylist = await _dbRepo.getPlaylistById(playlistId);

      if (localPlaylist != null && localPlaylist.path != playlist.path) {
        // Path changed - this shouldn't happen but handle it
        print('Warning: Playlist path changed for ID $playlistId');
      }

      return playlist;
    } catch (e) {
      // Playlist not found by ID, try recovery by path
      final localPlaylist = await _dbRepo.getPlaylistById(playlistId);
      if (localPlaylist == null) {
        return null;
      }

      // Search for playlist with matching path
      final response = await _apiRepo.getPlaylists(limit: 1000);
      final recoveredPlaylist = response.items.firstWhere(
        (p) => p.path == localPlaylist.path,
        orElse: () => throw Exception('Playlist not found'),
      );

      // Update local database with new ID
      await _dbRepo.insertOrUpdatePlaylist(
        SyncedPlaylist(
          id: recoveredPlaylist.id,
          name: recoveredPlaylist.name,
          path: recoveredPlaylist.path,
          type: recoveredPlaylist.type,
          lastSynced: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      print(
        'Recovered playlist: ${recoveredPlaylist.name} with new ID ${recoveredPlaylist.id}',
      );
      return recoveredPlaylist;
    }
  }

  /// Request cancellation of current sync
  void cancelSync() {
    _cancelRequested = true;
  }

  /// Sync a single playlist
  Future<Map<String, int>> _syncPlaylist(
    Playlist playlist,
    int playlistIndex,
    int totalPlaylists,
    int totalTracks,
    int tracksProcessedSoFar,
  ) async {
    int downloaded = 0;

    // Fetch all tracks in this playlist
    final tracksResponse = await _apiRepo.getPlaylistTracks(
      playlist.id,
      limit: 10000,
    );

    final serverTracks = tracksResponse.items;

    // Find tracks to download (on server but not local, or file missing)
    final tracksToDownload = <Track>[];

    // Get all server track IDs and query database once
    final serverTrackIds = serverTracks.map((t) => t.id).toList();
    final existingTracks = await _dbRepo.getTracksByIds(serverTrackIds);

    for (final track in serverTracks) {
      final localTrack = existingTracks[track.id];

      if (localTrack == null) {
        // Track not in database, need to download
        tracksToDownload.add(track);
      } else {
        // Track in database, verify file exists
        final file = File(localTrack.localPath);
        if (!await file.exists()) {
          // File missing, need to re-download
          tracksToDownload.add(track);
        }
      }
    }

    // Download new tracks
    for (int i = 0; i < tracksToDownload.length; i++) {
      if (_cancelRequested) {
        break; // Stop downloading, let sync complete cleanup
      }
      final track = tracksToDownload[i];

      onProgress?.call(
        SyncProgress(
          currentPlaylist: playlist.name,
          totalPlaylists: totalPlaylists,
          currentPlaylistIndex: playlistIndex,
          totalTracks: totalTracks,
          downloadedTracks: tracksProcessedSoFar + i,
          currentTrackTitle: track.title,
          downloadProgress: 0.0,
        ),
      );

      await _downloadTrack(track, (received, total) {
        final progress = total > 0 ? received / total : 0.0;
        onProgress?.call(
          SyncProgress(
            currentPlaylist: playlist.name,
            totalPlaylists: totalPlaylists,
            currentPlaylistIndex: playlistIndex,
            totalTracks: totalTracks,
            downloadedTracks: tracksProcessedSoFar + i,
            currentTrackTitle: track.title,
            downloadProgress: progress,
          ),
        );
      });

      downloaded++;
    }

    // Re-query to get all tracks now in database (including newly downloaded ones)
    final allExistingTracks = await _dbRepo.getTracksByIds(serverTrackIds);

    // Then add all tracks from server that exist in our database
    for (final trackId in allExistingTracks.keys) {
      await _dbRepo.addTrackToPlaylist(playlist.id, trackId);
    }

    // Update playlist in database
    await _dbRepo.insertOrUpdatePlaylist(
      SyncedPlaylist(
        id: playlist.id,
        name: playlist.name,
        path: playlist.path,
        type: playlist.type,
        lastSynced: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // Generate .m3u playlist file
    await _generatePlaylistFile(playlist, serverTracks);

    return {'downloaded': downloaded};
  }

  /// Download a single track
  Future<void> _downloadTrack(
    Track track,
    void Function(int, int)? onProgress,
  ) async {
    try {
      // Make a HEAD request first to get the Content-Type
      final headResponse = await Dio().head(
        '${_apiRepo.baseUrl}/databases/1/items/${track.id}.dat',
        options: Options(headers: {'Accept-Codecs': 'mpeg,alac,flac,wav'}),
      );

      final contentType =
          headResponse.headers.value('content-type') ??
          (track.type.isNotEmpty ? 'audio/${track.type}' : 'audio/mpeg');
      final extension = _fileRepo.getExtensionFromContentType(contentType);

      // Generate final filename and path with correct extension
      final finalPath = await _fileRepo.getTrackPath(track, extension);

      // Check if file already exists
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        // File already exists, but ensure it's in database
        final fileSize = await _fileRepo.getFileSize(finalPath);

        await _dbRepo.insertOrUpdateTrack(
          SyncedTrack(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            localPath: finalPath,
            serverPath: track.path,
            downloadTimestamp: DateTime.now().millisecondsSinceEpoch,
            fileSize: fileSize,
            genre: track.genre,
            lengthMs: track.lengthMs,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            year: track.year,
            artworkUrl: track.artworkUrl,
            artworkPath: null, // TODO: Find artwork and sync later
          ),
        );
        return;
      }

      // Create temporary file to download to
      final tracksDir = await _fileRepo.getTracksDirectory();
      final tempPath = '${tracksDir.path}/temp_${track.id}.$extension';

      // Download the file
      await _apiRepo.downloadTrack(track.id, tempPath, onProgress: onProgress);

      // Verify the file was downloaded
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        throw Exception('Download failed - file not created');
      }

      // Move temp file to final location
      await tempFile.rename(finalPath);

      // Get file size
      final fileSize = await _fileRepo.getFileSize(finalPath);

      // Handle artwork
      String? artworkPath;

      // First, try to extract embedded artwork from the audio file
      try {
        final tag = await AudioTags.read(finalPath);
        if (tag?.pictures != null && tag!.pictures!.isNotEmpty) {
          // Has embedded artwork, save it to cache
          final picture = tag.pictures!.first;
          artworkPath = await _fileRepo.getArtworkPath(track.albumId);

          // Only write if it doesn't already exist (multiple tracks share album art)
          if (!await File(artworkPath).exists()) {
            await File(artworkPath).writeAsBytes(picture.bytes);
          }
        }
      } catch (e) {
        print('Could not read embedded artwork: $e');
      }

      // If no embedded artwork and we have an artworkUrl, download it
      if (artworkPath == null && track.artworkUrl.isNotEmpty) {
        // Check if we already cached this album's artwork
        if (await _fileRepo.artworkExists(track.albumId)) {
          artworkPath = await _fileRepo.getArtworkPath(track.albumId);
        } else {
          // Download artwork
          final fullArtworkUrl = '${_apiRepo.baseUrl}${track.artworkUrl}';
          artworkPath = await _fileRepo.downloadArtwork(
            fullArtworkUrl,
            track.albumId,
          );
        }
      }

      // Save track to database
      await _dbRepo.insertOrUpdateTrack(
        SyncedTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          albumArtist: track.albumArtist,
          localPath: finalPath,
          serverPath: track.path,
          downloadTimestamp: DateTime.now().millisecondsSinceEpoch,
          fileSize: fileSize,
          genre: track.genre,
          lengthMs: track.lengthMs,
          trackNumber: track.trackNumber,
          discNumber: track.discNumber,
          year: track.year,
          artworkUrl: track.artworkUrl,
          artworkPath: artworkPath,
        ),
      );
    } catch (e) {
      // Clean up temp file on error if it exists
      final tracksDir = await _fileRepo.getTracksDirectory();

      // Try to delete temp file with any extension
      final dir = Directory(tracksDir.path);
      final files = dir.listSync();
      for (final file in files) {
        if (file.path.contains('temp_${track.id}')) {
          await file.delete();
        }
      }

      rethrow;
    }
  }

  /// Generate .m3u playlist file
  Future<void> _generatePlaylistFile(
    Playlist playlist,
    List<Track> tracks,
  ) async {
    final trackPaths = <String>[];

    for (final track in tracks) {
      // Get the track from database to find its local path
      final localTrack = await _dbRepo.getTrackById(track.id);
      if (localTrack != null) {
        trackPaths.add(localTrack.localPath);
      }
    }

    await _fileRepo.writePlaylistFile(playlist, trackPaths);
  }

  /// Delete orphaned tracks (not in any playlist)
  Future<int> _deleteOrphanedTracks() async {
    final orphanedTracks = await _dbRepo.getOrphanedTracks();

    for (final track in orphanedTracks) {
      // Delete the file
      await _fileRepo.deleteTrack(track.localPath);

      // Remove from database
      await _dbRepo.deleteTrack(track.id);
    }

    return orphanedTracks.length;
  }

  /// Sync playback events back to server
  Future<SyncResult> syncEvents() async {
    try {
      final unsyncedEvents = await _dbRepo.getUnsyncedEvents();

      // Group events by track ID
      final eventsByTrack = <int, List<PendingEvent>>{};
      for (final event in unsyncedEvents) {
        eventsByTrack.putIfAbsent(event.trackId, () => []).add(event);
      }

      int eventsSynced = 0;

      // Process each track's events
      for (final entry in eventsByTrack.entries) {
        final trackId = entry.key;
        final events = entry.value;

        try {
          // Fetch current server stats
          final track = await _apiRepo.getTrack(trackId);

          // Calculate merged stats
          int playCount = track.playCount;
          int skipCount = track.skipCount;
          int? timePlayed = track.timePlayed != null
              ? DateTime.parse(track.timePlayed!).millisecondsSinceEpoch ~/ 1000
              : null;
          int? timeSkipped = track.timeSkipped != null
              ? DateTime.parse(track.timeSkipped!).millisecondsSinceEpoch ~/
                    1000
              : null;

          for (final event in events) {
            if (event.eventType == 'play') {
              playCount++;
              // Keep most recent play timestamp
              if (timePlayed == null || event.timestamp > timePlayed) {
                timePlayed = event.timestamp;
              }
            } else if (event.eventType == 'skip') {
              skipCount++;
              // Keep most recent skip timestamp
              if (timeSkipped == null || event.timestamp > timeSkipped) {
                timeSkipped = event.timestamp;
              }
            }
          }

          // Update server
          await _apiRepo.updateTrackStats(
            trackId,
            playCount: playCount,
            skipCount: skipCount,
            timePlayed: timePlayed,
            timeSkipped: timeSkipped,
          );

          // Mark events as synced and delete them
          for (final event in events) {
            await _dbRepo.deleteEvent(event.id!);
            eventsSynced++;
          }
        } catch (e) {
          print('Failed to sync events for track $trackId: $e');
          // Continue with other tracks
        }
      }

      return SyncResult(success: true, eventsySynced: eventsSynced);
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }
}
