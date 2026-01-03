import 'dart:io';
import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';
import 'package:dio/dio.dart';

import '../../data/models/playlist.dart';
import '../../data/models/sync_history.dart';
import '../../data/models/track.dart';
import '../../data/repositories/file_system_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../utils/logger.dart';

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
  Future<SyncResult> syncPlaylists(
    List<int> playlistIds, {
    String triggerType = 'manual',
  }) async {
    logger.i(
      'Starting playlist sync for ${playlistIds.length} playlists (trigger: $triggerType)',
    );
    final startTime = DateTime.now();

    try {
      int playlistsSynced = 0;
      int tracksDownloaded = 0;
      int tracksDeleted = 0;
      _cancelRequested = false;

      // Track playlist details for history
      final playlistDetails = <Map<String, dynamic>>[];

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

          // Log cancelled sync
          await _logSyncHistory(
            status: 'cancelled',
            playlistsSynced: playlistsSynced,
            tracksDownloaded: tracksDownloaded,
            tracksDeleted: tracksDeleted,
            errorMessage: 'Sync cancelled by user',
            durationMs: DateTime.now().difference(startTime).inMilliseconds,
            triggerType: triggerType,
            playlistDetails: playlistDetails,
          );

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

        final downloaded = stats['downloaded'] as int;
        tracksDownloaded += downloaded;
        totalTracksProcessed += allPlaylistTracks[playlistId]!.length;
        playlistsSynced++;

        // Track playlist details for history
        playlistDetails.add({
          'playlist_id': playlist.id,
          'playlist_name': playlist.name,
          'tracks_in_playlist': allPlaylistTracks[playlistId]!.length,
        });
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

      // Log successful sync
      await _logSyncHistory(
        status: 'success',
        playlistsSynced: playlistsSynced,
        tracksDownloaded: tracksDownloaded,
        tracksDeleted: tracksDeleted,
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
        triggerType: triggerType,
        playlistDetails: playlistDetails,
      );

      return SyncResult(
        success: true,
        playlistsSynced: playlistsSynced,
        tracksDownloaded: tracksDownloaded,
        tracksDeleted: tracksDeleted,
      );
    } catch (e) {
      // Log failed sync
      await _logSyncHistory(
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
        triggerType: triggerType,
        playlistDetails: [],
      );

      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Log sync history to database
  Future<void> _logSyncHistory({
    required String status,
    int playlistsSynced = 0,
    int tracksDownloaded = 0,
    int tracksDeleted = 0,
    String? errorMessage,
    required int durationMs,
    required String triggerType,
    required List<Map<String, dynamic>> playlistDetails,
  }) async {
    final record = SyncHistoryRecord(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: status,
      playlistsSynced: playlistsSynced,
      tracksDownloaded: tracksDownloaded,
      tracksDeleted: tracksDeleted,
      errorMessage: errorMessage,
      durationMs: durationMs,
      triggerType: triggerType,
    );

    final syncId = await _dbRepo.insertSyncHistory(record);

    // Insert playlist details
    for (final detail in playlistDetails) {
      await _dbRepo.insertSyncHistoryPlaylist(
        SyncHistoryPlaylist(
          syncId: syncId,
          playlistId: detail['playlist_id'],
          playlistName: detail['playlist_name'],
          tracksInPlaylist: detail['tracks_in_playlist'],
        ),
      );
    }

    // Clean up old history
    await _dbRepo.cleanOldSyncHistory();
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
    logger.i(
      'Syncing playlist ${playlistIndex + 1}/$totalPlaylists: ${playlist.name} (ID: ${playlist.id})',
    );
    int downloaded = 0;

    // Fetch all tracks in this playlist
    logger.d('Fetching tracks for playlist ${playlist.name}');
    final tracksResponse = await _apiRepo.getPlaylistTracks(
      playlist.id,
      limit: 10000,
    );

    final serverTracks = tracksResponse.items;
    logger.i(
      'Playlist ${playlist.name} has ${serverTracks.length} tracks on server',
    );

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
    logger.d('Updated playlist ${playlist.name} in database');

    // Generate .m3u playlist file
    await _generatePlaylistFile(playlist, serverTracks);

    logger.i(
      'Completed sync for playlist ${playlist.name}: $downloaded tracks downloaded',
    );

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
            artworkPath: null,
          ),
        );
        return;
      }

      // Download the file to memory first
      final dio = Dio();
      final response = await dio.get<List<int>>(
        '${_apiRepo.baseUrl}/databases/1/items/${track.id}.dat',
        queryParameters: {'no_register_playback': '1'},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept-Codecs': 'mpeg,alac,flac,wav'},
        ),
        onReceiveProgress: onProgress,
      );

      if (response.data == null || response.data!.isEmpty) {
        throw Exception('Download failed - no data received');
      }

      // Write using platform-aware method
      final bytes = Uint8List.fromList(response.data!);
      await _fileRepo.writeFile(finalPath, bytes);

      // Get file size
      final fileSize = await _fileRepo.getFileSize(finalPath);

      // Handle artwork
      String? artworkPath;

      // First, try to extract embedded artwork from the audio file
      try {
        final tag = await AudioTags.read(finalPath);
        if (tag?.pictures != null && tag!.pictures.isNotEmpty) {
          // Has embedded artwork, save it to cache
          final picture = tag.pictures.first;
          artworkPath = await _fileRepo.getArtworkPath(track.albumId);

          // Only write if it doesn't already exist (multiple tracks share album art)
          if (!await File(artworkPath).exists()) {
            await File(artworkPath).writeAsBytes(picture.bytes);
          }
        }
      } catch (e) {
        // print('Could not read embedded artwork: $e');
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
    try {
      logger.d(
        'Generating playlist file for: ${playlist.name} with ${tracks.length} tracks',
      );

      final trackPaths = <String>[];
      final trackMetadata = <Map<String, dynamic>>[];

      for (final track in tracks) {
        // Get the track from database to find its local path
        final localTrack = await _dbRepo.getTrackById(track.id);
        if (localTrack != null) {
          trackPaths.add(localTrack.localPath);
          trackMetadata.add({
            'title': track.title,
            'artist': track.artist,
            'duration_ms': track.lengthMs,
          });
          // logger.d('Added track: ${track.title} by ${track.artist}');
        } else {
          logger.w(
            'Track ${track.id} (${track.title}) not found in database, skipping from playlist',
          );
        }
      }

      logger.i(
        'Collected ${trackPaths.length} track paths for playlist ${playlist.name}',
      );

      if (trackPaths.isEmpty) {
        logger.w(
          'No tracks found for playlist ${playlist.name}, creating empty playlist file',
        );
      }

      await _fileRepo.writePlaylistFile(playlist, trackPaths, trackMetadata);
      logger.i('Playlist file generation completed for: ${playlist.name}');
    } catch (e, stackTrace) {
      logger.e(
        'Error generating playlist file for ${playlist.name}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
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
      logger.i('Starting event sync');
      final unsyncedEvents = await _dbRepo.getUnsyncedEvents();
      logger.i('Found ${unsyncedEvents.length} unsynced events');

      if (unsyncedEvents.isEmpty) {
        logger.d('No events to sync');
        return SyncResult(success: true, eventsySynced: 0);
      }

      // Group events by track ID
      final eventsByTrack = <int, List<PendingEvent>>{};
      for (final event in unsyncedEvents) {
        eventsByTrack.putIfAbsent(event.trackId, () => []).add(event);
      }

      logger.d('Events grouped into ${eventsByTrack.length} tracks');

      int eventsSynced = 0;

      // Process each track's events
      for (final entry in eventsByTrack.entries) {
        final trackId = entry.key;
        final events = entry.value;

        try {
          logger.d('Syncing ${events.length} events for track $trackId');

          // Fetch current server stats
          final track = await _apiRepo.getTrack(trackId);
          logger.d(
            'Current server stats - plays: ${track.playCount}, skips: ${track.skipCount}',
          );

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

          logger.d('New stats - plays: $playCount, skips: $skipCount');

          // Update server
          await _apiRepo.updateTrackStats(
            trackId,
            playCount: playCount,
            skipCount: skipCount,
            timePlayed: timePlayed,
            timeSkipped: timeSkipped,
          );

          logger.i('Successfully updated server stats for track $trackId');

          // Mark events as synced and delete them
          for (final event in events) {
            await _dbRepo.deleteEvent(event.id!);
            eventsSynced++;
          }
        } catch (e, stackTrace) {
          logger.e(
            'Failed to sync events for track $trackId',
            error: e,
            stackTrace: stackTrace,
          );
          // Continue with other tracks
        }
      }

      logger.i('Event sync completed: $eventsSynced events synced');
      return SyncResult(success: true, eventsySynced: eventsSynced);
    } catch (e, stackTrace) {
      logger.e('Event sync failed', error: e, stackTrace: stackTrace);
      return SyncResult(success: false, error: e.toString());
    }
  }
}
