import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../utils/logger.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Get the tracks directory path (relative)
  String getTracksPath() => 'tracks';

  // Get the playlists directory path (relative)
  String getPlaylistsPath() => 'playlists';

  // Get the artwork directory path (relative)
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

    if (await _usingSaf()) {
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
      final absolutePath = await _getAbsolutePath(trackPath);
      return File(absolutePath).exists();
    }
  }

  Future<bool> fileExists(String filePath) async {
    if (await _usingSaf()) {
      try {
        final exists = await _storageChannel.invokeMethod<bool>('fileExists', {
          'path': filePath,
        });
        return exists ?? false;
      } catch (e) {
        logger.e('Error checking file existence via SAF', error: e);
        return false;
      }
    } else {
      final absolutePath = await _getAbsolutePath(filePath);
      return File(absolutePath).exists();
    }
  }

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
      final absolutePath = await _getAbsolutePath(filePath);
      final file = File(absolutePath);
      if (!await file.exists()) return 0;
      return file.length();
    }
  }

  Future<void> deleteTrack(String localPath) async {
    if (await _usingSaf()) {
      try {
        await _storageChannel.invokeMethod('deleteFile', {'path': localPath});
      } catch (e) {
        logger.e('Error deleting file via SAF', error: e);
        rethrow;
      }
    } else {
      final absolutePath = await _getAbsolutePath(localPath);
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

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
      final absolutePath = await _getAbsolutePath(filePath);
      final file = File(absolutePath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsBytes(bytes);
    }
  }

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
      final sdk = await _getAndroidSdk();

      if (sdk >= 29) {
        try {
          await _storageChannel.invokeMethod('writeFileStringMediaStore', {
            'path': filePath,
            'content': content,
          });
        } catch (e) {
          logger.e('Error writing file via MediaStore', error: e);
          rethrow;
        }
      } else {
        final file = File(filePath);
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await file.writeAsString(content);
      }
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
      final absolutePath = await _getAbsolutePath(artworkPath);
      return File(absolutePath).exists();
    }
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

  /// Convert relative path to absolute path (only on legacy storage)
  Future<String> _getAbsolutePath(String relativePath) async {
    if (await _usingSaf()) {
      // On SAF, keep paths relative
      return relativePath;
    } else {
      // On legacy storage, need absolute paths
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Could not access external storage');
      }

      final parts = directory.path.split('/');
      final baseIndex = parts.indexOf('emulated');
      if (baseIndex == -1) {
        throw Exception('Unexpected storage path structure');
      }

      final basePath = '${parts.sublist(0, baseIndex + 2).join('/')}/Music';
      return path.join(basePath, relativePath);
    }
  }
}
