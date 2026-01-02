import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:dio/dio.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../../utils/logger.dart';

class FileSystemRepository {
  // Get the base Music directory
  Future<Directory> getMusicDirectory() async {
    // On Android, we need to use the external storage directory differently
    if (Platform.isAndroid) {
      // Get the external storage directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Could not access external storage');
      }

      // Navigate to /storage/emulated/0/Music
      // The path typically looks like: /storage/emulated/0/Android/data/package/files
      // We need to go up to /storage/emulated/0/ and then to Music
      final parts = directory.path.split('/');
      final baseIndex = parts.indexOf('emulated');
      if (baseIndex == -1) {
        throw Exception('Unexpected storage path structure');
      }

      final musicPath = '${parts.sublist(0, baseIndex + 2).join('/')}/Music';
      final musicDir = Directory(musicPath);

      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      return musicDir;
    } else {
      // For other platforms (though we're Android-only for now)
      throw UnsupportedError('Platform not supported');
    }
  }

  // Get the tracks directory
  Future<Directory> getTracksDirectory() async {
    final musicDir = await getMusicDirectory();
    final tracksDir = Directory(path.join(musicDir.path, 'tracks'));

    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }

    return tracksDir;
  }

  // Get the playlists directory
  Future<Directory> getPlaylistsDirectory() async {
    final musicDir = await getMusicDirectory();
    final playlistsDir = Directory(path.join(musicDir.path, 'playlists'));

    if (!await playlistsDir.exists()) {
      await playlistsDir.create(recursive: true);
    }

    return playlistsDir;
  }

  // Sanitize a string for use in filesystem paths
  String sanitizeFilename(String name) {
    // Replace invalid characters with underscores
    final invalidChars = RegExp(r'[/\\:*?"<>|]');
    return name.replaceAll(invalidChars, '_');
  }

  // Generate a filename for a track
  String generateTrackFilename(Track track, String extension) {
    final artist = sanitizeFilename(track.artist);
    final album = sanitizeFilename(track.album);
    final trackId = track.id;

    return '${artist}_${album}_$trackId.$extension';
  }

  // Get the local file path for a track
  Future<String> getTrackPath(Track track, String extension) async {
    final tracksDir = await getTracksDirectory();
    final filename = generateTrackFilename(track, extension);
    return path.join(tracksDir.path, filename);
  }

  // Check if a track file exists locally
  Future<bool> trackExists(Track track, String extension) async {
    final trackPath = await getTrackPath(track, extension);
    return File(trackPath).exists();
  }

  // Get file size
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return 0;
    return file.length();
  }

  // Delete a track file
  Future<void> deleteTrack(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Extract file extension from content-type header
  String getExtensionFromContentType(String contentType) {
    final typeMap = {
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/flac': 'flac',
      'audio/x-flac': 'flac',
      'audio/alac': 'm4a',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/wave': 'wav',
      'audio/mp4': 'm4a',
      'audio/x-m4a': 'm4a',
      'audio/aac': 'aac',
    };

    final normalized = contentType.toLowerCase().split(';').first.trim();
    return typeMap[normalized] ?? 'mp3'; // Default to mp3 if unknown
  }

  // Create or update a playlist file
  Future<void> writePlaylistFile(
    Playlist playlist,
    List<String> trackPaths,
    List<Map<String, dynamic>> trackMetadata, // Add track metadata parameter
  ) async {
    try {
      logger.d('Writing playlist file for: ${playlist.name}');
      logger.d('Track paths count: ${trackPaths.length}');

      final playlistsDir = await getPlaylistsDirectory();
      logger.d('Playlists directory: ${playlistsDir.path}');

      final sanitizedName = sanitizeFilename(playlist.name);
      final playlistPath = path.join(playlistsDir.path, '$sanitizedName.m3u');
      logger.d('Playlist file path: $playlistPath');

      final file = File(playlistPath);

      // Build extended M3U content
      final buffer = StringBuffer();

      // M3U header
      buffer.writeln('#EXTM3U');
      buffer.writeln('#PLAYLIST:${playlist.name}');
      buffer.writeln('#EXTENC:UTF-8');

      // Add tracks with metadata
      for (int i = 0; i < trackPaths.length; i++) {
        final trackPath = trackPaths[i];
        final metadata = trackMetadata[i];

        // #EXTINF:duration_in_seconds,Artist - Title
        final duration = (metadata['duration_ms'] as int) ~/ 1000;
        final artist = metadata['artist'] as String;
        final title = metadata['title'] as String;

        buffer.writeln('#EXTINF:$duration,$artist - $title');

        // Convert to relative path
        final relativePath = path.relative(trackPath, from: playlistsDir.path);
        buffer.writeln(relativePath);
      }

      final content = buffer.toString();
      logger.d('Content length: ${content.length} characters');

      await file.writeAsString(content);

      // Verify file was written
      if (await file.exists()) {
        final fileSize = await file.length();
        logger.i(
          'Playlist file written successfully: $playlistPath ($fileSize bytes, ${trackPaths.length} tracks)',
        );
      } else {
        logger.e('Playlist file does not exist after write: $playlistPath');
      }
    } catch (e, stackTrace) {
      logger.e(
        'Error writing playlist file for ${playlist.name}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Delete a playlist file
  Future<void> deletePlaylistFile(String playlistName) async {
    try {
      final playlistsDir = await getPlaylistsDirectory();
      final sanitizedName = sanitizeFilename(playlistName);
      final playlistPath = path.join(playlistsDir.path, '$sanitizedName.m3u');

      final file = File(playlistPath);
      if (await file.exists()) {
        await file.delete();
        logger.i('Deleted playlist file: $playlistPath');
      } else {
        logger.d(
          'Playlist file does not exist, skipping delete: $playlistPath',
        );
      }
    } catch (e, stackTrace) {
      logger.e(
        'Error deleting playlist file: $playlistName',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Trigger Android media scanner to discover new files
  Future<void> scanMediaFile(String filePath) async {
    // This will require a platform channel implementation
    // For now, we'll leave this as a placeholder
    // The actual implementation will need native Android code
  }

  // Get the artwork cache directory
  Future<Directory> getArtworkDirectory() async {
    final musicDir = await getMusicDirectory();
    final artworkDir = Directory(path.join(musicDir.path, 'artwork'));

    if (!await artworkDir.exists()) {
      await artworkDir.create(recursive: true);
    }

    return artworkDir;
  }

  // Generate artwork filename (using album_id to deduplicate)
  String generateArtworkFilename(String albumId) {
    return 'album_$albumId.jpg';
  }

  // Get artwork path for an album
  Future<String> getArtworkPath(String albumId) async {
    final artworkDir = await getArtworkDirectory();
    final filename = generateArtworkFilename(albumId);
    return path.join(artworkDir.path, filename);
  }

  // Check if artwork exists for an album
  Future<bool> artworkExists(String albumId) async {
    final artworkPath = await getArtworkPath(albumId);
    return File(artworkPath).exists();
  }

  // Download artwork from URL
  Future<String?> downloadArtwork(String artworkUrl, String albumId) async {
    try {
      final artworkPath = await getArtworkPath(albumId);
      logger.d('Downloading artwork to: $artworkPath');

      // Download the image
      final dio = Dio();
      await dio.download(artworkUrl, artworkPath);

      // Verify the file was downloaded and is not empty
      final file = File(artworkPath);
      if (!await file.exists() || await file.length() == 0) {
        logger.w('Artwork download failed or file is empty');
        if (await file.exists()) {
          await file.delete(); // Delete empty file
        }
        return null;
      }

      final fileSize = await file.length();
      logger.i('Artwork downloaded successfully: $fileSize bytes');
      return artworkPath;
    } catch (e, stackTrace) {
      logger.e('Error downloading artwork', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
