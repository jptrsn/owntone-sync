import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class FileSystemRepository {
  static const _storageChannel = MethodChannel(
    'dev.educoder.owntone_sync/storage',
  );

  // Get the tracks directory path (relative to SAF root)
  String getTracksPath() => 'tracks';

  // Get the playlists directory path (relative to SAF root)
  String getPlaylistsPath() => 'playlists';

  // Get the artwork directory path (app-private storage)
  String getArtworkPath() => 'artwork';

  String sanitizeFilename(String name) {
    final invalidChars = RegExp(r'[/\\:*?"<>|]');
    return name.replaceAll(invalidChars, '_');
  }

  String generateTrackFilename(Track track, String extension) {
    final artist = sanitizeFilename(track.artist);
    final album = sanitizeFilename(track.album);
    final trackId = track.id;

    return '${artist}_${album}_$trackId.$extension';
  }

  String getTrackFilePath(Track track, String extension) {
    final filename = generateTrackFilename(track, extension);
    return path.join(getTracksPath(), filename);
  }

  Future<bool> trackExists(Track track, String extension) async {
    final trackPath = getTrackFilePath(track, extension);

    try {
      final exists = await _storageChannel.invokeMethod<bool>('fileExists', {
        'path': trackPath,
      });
      return exists ?? false;
    } catch (e) {
      logger.e('Error checking file existence', error: e);
      return false;
    }
  }

  Future<bool> fileExists(String filePath) async {
    // Artwork is in app-private storage
    if (filePath.startsWith('artwork/')) {
      final absolutePath = await _getArtworkAbsolutePath(filePath);
      return File(absolutePath).exists();
    }

    // Music/playlists are in SAF storage
    try {
      final exists = await _storageChannel.invokeMethod<bool>('fileExists', {
        'path': filePath,
      });
      return exists ?? false;
    } catch (e) {
      logger.e('Error checking file existence', error: e);
      return false;
    }
  }

  Future<int> getFileSize(String filePath) async {
    // Artwork is in app-private storage
    if (filePath.startsWith('artwork/')) {
      final absolutePath = await _getArtworkAbsolutePath(filePath);
      final file = File(absolutePath);
      if (!await file.exists()) return 0;
      return file.length();
    }

    // Music/playlists are in SAF storage
    try {
      final size = await _storageChannel.invokeMethod<int>('getFileSize', {
        'path': filePath,
      });
      return size ?? 0;
    } catch (e) {
      logger.e('Error getting file size', error: e);
      return 0;
    }
  }

  Future<void> deleteTrack(String localPath) async {
    // Artwork is in app-private storage
    if (localPath.startsWith('artwork/')) {
      final absolutePath = await _getArtworkAbsolutePath(localPath);
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    // Music/playlists are in SAF storage
    try {
      await _storageChannel.invokeMethod('deleteFile', {'path': localPath});
    } catch (e) {
      logger.e('Error deleting file', error: e);
      rethrow;
    }
  }

  Future<void> writeFile(String filePath, Uint8List bytes) async {
    // Artwork is in app-private storage
    if (filePath.startsWith('artwork/')) {
      final absolutePath = await _getArtworkAbsolutePath(filePath);
      final file = File(absolutePath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsBytes(bytes);
      return;
    }

    // Music/playlists are in SAF storage
    try {
      await _storageChannel.invokeMethod('writeFile', {
        'path': filePath,
        'data': bytes,
      });
    } catch (e) {
      logger.e('Error writing file', error: e);
      rethrow;
    }
  }

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

  Future<void> writePlaylistFile(
    Playlist playlist,
    List<String> trackPaths,
    List<Map<String, dynamic>> trackMetadata,
  ) async {
    try {
      logger.d('Writing playlist file for: ${playlist.name}');

      final sanitizedName = sanitizeFilename(playlist.name);
      final playlistPath = path.join(getPlaylistsPath(), '$sanitizedName.m3u');

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

        final relativePath = path.relative(trackPath, from: getPlaylistsPath());
        buffer.writeln(relativePath);
      }

      final content = buffer.toString();
      final bytes = Uint8List.fromList(utf8.encode(content));
      await writeFile(playlistPath, bytes);

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

  Future<void> deletePlaylistFile(String playlistName) async {
    try {
      final sanitizedName = sanitizeFilename(playlistName);
      final playlistPath = path.join(getPlaylistsPath(), '$sanitizedName.m3u');

      await deleteTrack(playlistPath);
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

  String generateArtworkFilename(String albumId) {
    return 'album_$albumId.jpg';
  }

  String getArtworkFilePath(String albumId) {
    final filename = generateArtworkFilename(albumId);
    return path.join(getArtworkPath(), filename);
  }

  Future<bool> artworkExists(String albumId) async {
    final artworkPath = getArtworkFilePath(albumId);
    final absolutePath = await _getArtworkAbsolutePath(artworkPath);
    return File(absolutePath).exists();
  }

  Future<String?> downloadArtwork(String artworkUrl, String albumId) async {
    try {
      final artworkPath = getArtworkFilePath(albumId);
      logger.d('Downloading artwork to: $artworkPath');

      final dio = Dio();
      final response = await dio.get<List<int>>(
        artworkUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = Uint8List.fromList(response.data!);
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

  /// Get absolute path for artwork stored in app-private directory
  Future<String> _getArtworkAbsolutePath(String relativePath) async {
    final cacheDir = await getApplicationDocumentsDirectory();
    return path.join(cacheDir.path, relativePath);
  }
}
