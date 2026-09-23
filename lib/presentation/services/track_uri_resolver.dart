import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/local_database_repository.dart';

class TrackUriResolver {
  TrackUriResolver({LocalDatabaseRepository? dbRepo}) : _dbRepo = dbRepo;

  static const MethodChannel _storageChannel =
      MethodChannel('dev.educoder.owntone_sync/storage');

  final LocalDatabaseRepository? _dbRepo;

  /// A cached URI is only usable if it is a tree-scoped document URI
  /// (`content://<authority>/tree/<treeDocId>/document/<id>`). The persisted
  /// grant from ACTION_OPEN_DOCUMENT_TREE only authorises URIs that carry the
  /// tree; a bare `content://<authority>/document/<id>` URI is denied with a
  /// SecurityException at playback. The DB migration (v5) purged the bare
  /// form, but anything else malformed is rejected here rather than trusted,
  /// so it re-resolves and overwrites the bad value.
  static bool _isUsableTreeUri(String? uri) {
    return uri != null &&
        uri.isNotEmpty &&
        uri.startsWith('content://') &&
        uri.contains('/tree/');
  }

  /// Resolve a whole collection of tracks to playable content:// URIs.
  ///
  /// Prefers a cached tree-scoped [SyncedTrack.contentUri] (treating `''` as
  /// null and rejecting any other malformed shape), resolves the remainder in
  /// a single method-channel call, and writes successful resolutions back to
  /// the database so the cost is paid once per track.
  ///
  /// Returns a map of track id -> playable URI for every track that could be
  /// resolved. Tracks that cannot be resolved are simply absent from the map.
  Future<Map<int, String>> resolveCollection(List<SyncedTrack> tracks) async {
    final resolved = <int, String>{};
    final missing = <SyncedTrack>[];

    for (final track in tracks) {
      final cached = track.contentUri;
      if (_isUsableTreeUri(cached)) {
        resolved[track.id] = cached!;
      } else {
        missing.add(track);
      }
    }

    if (missing.isEmpty) return resolved;

    final uris = await _resolvePaths(missing.map((t) => t.localPath).toList());

    final toCache = <int, String>{};
    for (var i = 0; i < missing.length; i++) {
      final uri = uris[i];
      if (uri != null && uri.isNotEmpty) {
        resolved[missing[i].id] = uri;
        toCache[missing[i].id] = uri;
      } else if (kDebugMode) {
        debugPrint(
          '[TrackUriResolver] Failed to resolve: '
          '${missing[i].title} (${missing[i].localPath})',
        );
      }
    }

    if (toCache.isNotEmpty && _dbRepo != null) {
      try {
        await _dbRepo.updateTracksContentUri(toCache);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[TrackUriResolver] URI cache-back failed: $e');
        }
      }
    }

    return resolved;
  }

  Future<List<String?>> _resolvePaths(List<String> localPaths) async {
    try {
      final result = await _storageChannel.invokeMethod<List<dynamic>>(
        'buildContentUris',
        {'localPaths': localPaths},
      );
      if (result == null) {
        return List.filled(localPaths.length, null);
      }
      return result.map((e) => (e is String && e.isNotEmpty) ? e : null).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TrackUriResolver] Batch resolve failed: $e');
      }
      return List.filled(localPaths.length, null);
    }
  }
}
