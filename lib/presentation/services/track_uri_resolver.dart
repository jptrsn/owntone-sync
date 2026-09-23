import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class TrackUriResolver {
  static const MethodChannel _storageChannel =
      MethodChannel('dev.educoder.owntone_sync/storage');

  /// Resolve a single track to a playable content:// URI.
  /// Returns the URI if successful, null otherwise.
  Future<String?> resolve(String localPath) async {
    if (localPath.isEmpty) {
      if (kDebugMode) {
        debugPrint('[TrackUriResolver] No localPath provided');
      }
      return null;
    }

    try {
      final uri = await _storageChannel.invokeMethod<String>(
        'buildContentUri',
        {'localPath': localPath},
      );

      if (uri != null && uri.isNotEmpty && kDebugMode) {
        debugPrint('[TrackUriResolver] Resolved: $localPath -> $uri');
      }

      return uri;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TrackUriResolver] Failed to resolve URI for $localPath: $e');
      }
      return null;
    }
  }

  /// Resolve a whole collection of tracks in one batch.
  /// Returns a list of resolved URIs aligned with [localPaths].
  Future<List<String?>> resolveBatch(List<String> localPaths) async {
    final results = <String?>[];
    for (final path in localPaths) {
      final uri = await resolve(path);
      results.add(uri);
    }
    return results;
  }
}
