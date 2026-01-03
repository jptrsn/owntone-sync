import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:dio/dio.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../../utils/logger.dart';

class FileSystemRepository {
  static const _storageChannel = MethodChannel(
    'dev.educoder.owntone_sync/storage',
  );

  /// Get Android SDK version
  Future<int> _getAndroidSdk() async {
    if (!Platform.isAndroid) return 0;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt;
  }

  /// Check if we're using SAF (Android 13+)
  Future<bool> _usingSaf() async {
    final sdk = await _getAndroidSdk();
    return sdk >= 33;
  }

  // Get the base Music directory
  Future<Directory> getMusicDirectory() async {
    // On Android SDK < 33, use the legacy path approach
    if (Platform.isAndroid && !await _usingSaf()) {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Could not access external storage');
      }

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
    } else if (Platform.isAndroid && await _usingSaf()) {
      // On SDK 33+, we can't use File() paths - return a dummy directory
      // Actual file operations will go through SAF method channels
      return Directory(
        '/storage/emulated/0/Music',
      ); // Placeholder for path building
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  // Get the tracks directory
  Future<Directory> getTracksDirectory() async {
    final musicDir = await getMusicDirectory();
    final tracksDir = Directory(path.join(musicDir.path, 'tracks'));

    if (!await _usingSaf() && !await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }

    return tracksDir;
  }

  // Get the playlists directory
  Future<Directory> getPlaylistsDirectory() async {
    final musicDir = await getMusicDirectory();
    final playlistsDir = Directory(path.join(musicDir.path, 'playlists'));

    if (!await _usingSaf() && !await playlistsDir.exists()) {
      await playlistsDir.create(recursive: true);
    }

    return playlistsDir;
  }

  // Sanitize a string for use in filesystem paths
  String sanitizeFilename(String name) {
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

    if (await _usingSaf()) {
      // Use native method to check file existence via SAF
      try {
        final exists = await _storageChannel.invokeMethod<bool>('fileExists', {
          'path': trackPath,
        });
        return exists ?? false;
      } catch (e) {
        logger.e('Error checking file existence via SAF', error: e);
        return false;
      }
    } else {
      return File(trackPath).exists();
    }
  }

  // Get file size
  Future<int> getFileSize(String filePath) async {
    if (await _usingSaf()) {
      try {
        final size = await _storageChannel.invokeMethod<int>('getFileSize', {
          'path': filePath,
        });
        return size ?? 0;
      } catch (e) {
        logger.e('Error getting file size via SAF', error: e);
        return 0;
      }
    } else {
      final file = File(filePath);
      if (!await file.exists()) return 0;
      return file.length();
    }
  }

  // Delete a track file
  Future<void> deleteTrack(String localPath) async {
    if (await _usingSaf()) {
      try {
        await _storageChannel.invokeMethod('deleteFile', {'path': localPath});
      } catch (e) {
        logger.e('Error deleting file via SAF', error: e);
        rethrow;
      }
    } else {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Write file bytes via SAF or File() depending on SDK version
  Future<void> writeFile(String filePath, Uint8List bytes) async {
    if (await _usingSaf()) {
      try {
        await _storageChannel.invokeMethod('writeFile', {
          'path': filePath,
          'data': bytes,
        });
      } catch (e) {
        logger.e('Error writing file via SAF', error: e);
        rethrow;
      }
    } else {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  /// Write string content via SAF or File() depending on SDK version
  Future<void> writeFileString(String filePath, String content) async {
    if (await _usingSaf()) {
      try {
        await _storageChannel.invokeMethod('writeFileString', {
          'path': filePath,
          'content': content,
        });
      } catch (e) {
        logger.e('Error writing file string via SAF', error: e);
        rethrow;
      }
    } else {
      await File(filePath).writeAsString(content);
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
    return typeMap[normalized] ?? 'mp3';
  }

  // Create or update a playlist file
  Future<void> writePlaylistFile(
    Playlist playlist,
    List<String> trackPaths,
    List<Map<String, dynamic>> trackMetadata,
  ) async {
    try {
      logger.d('Writing playlist file for: ${playlist.name}');

      final playlistsDir = await getPlaylistsDirectory();
      final sanitizedName = sanitizeFilename(playlist.name);
      final playlistPath = path.join(playlistsDir.path, '$sanitizedName.m3u');

      // Build extended M3U content
      final buffer = StringBuffer();
      buffer.writeln('#EXTM3U');
      buffer.writeln('#PLAYLIST:${playlist.name}');
      buffer.writeln('#EXTENC:UTF-8');

      for (int i = 0; i < trackPaths.length; i++) {
        final trackPath = trackPaths[i];
        final metadata = trackMetadata[i];

        final duration = (metadata['duration_ms'] as int) ~/ 1000;
        final artist = metadata['artist'] as String;
        final title = metadata['title'] as String;

        buffer.writeln('#EXTINF:$duration,$artist - $title');

        final relativePath = path.relative(trackPath, from: playlistsDir.path);
        buffer.writeln(relativePath);
      }

      final content = buffer.toString();

      // Use platform-aware write method
      await writeFileString(playlistPath, content);

      logger.i(
        'Playlist file written successfully: $playlistPath (${trackPaths.length} tracks)',
      );
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

      await deleteTrack(playlistPath); // Reuse delete logic
      logger.i('Deleted playlist file: $playlistPath');
    } catch (e, stackTrace) {
      logger.e(
        'Error deleting playlist file: $playlistName',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Get the artwork cache directory
  Future<Directory> getArtworkDirectory() async {
    final musicDir = await getMusicDirectory();
    final artworkDir = Directory(path.join(musicDir.path, 'artwork'));

    if (!await _usingSaf() && !await artworkDir.exists()) {
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

    if (await _usingSaf()) {
      try {
        final exists = await _storageChannel.invokeMethod<bool>('fileExists', {
          'path': artworkPath,
        });
        return exists ?? false;
      } catch (e) {
        return false;
      }
    } else {
      return File(artworkPath).exists();
    }
  }

  // Download artwork from URL
  Future<String?> downloadArtwork(String artworkUrl, String albumId) async {
    try {
      final artworkPath = await getArtworkPath(albumId);
      logger.d('Downloading artwork to: $artworkPath');

      final dio = Dio();
      final response = await dio.get<List<int>>(
        artworkUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = Uint8List.fromList(response.data!);

      // Use platform-aware write
      await writeFile(artworkPath, bytes);

      final fileSize = await getFileSize(artworkPath);
      if (fileSize == 0) {
        logger.w('Artwork download failed or file is empty');
        await deleteTrack(artworkPath);
        return null;
      }

      logger.i('Artwork downloaded successfully: $fileSize bytes');
      return artworkPath;
    } catch (e, stackTrace) {
      logger.e('Error downloading artwork', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
