import 'package:dio/dio.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class OwnToneApiRepository {
  final Dio _dio;
  final String baseUrl;

  OwnToneApiRepository({required this.baseUrl, Dio? dio})
    : _dio = dio ?? Dio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// Fetch all playlists from the server
  Future<PlaylistsResponse> getPlaylists({int? offset, int? limit}) async {
    final response = await _dio.get(
      '/api/library/playlists',
      queryParameters: {
        if (offset != null) 'offset': offset,
        if (limit != null) 'limit': limit,
      },
    );
    return PlaylistsResponse.fromJson(response.data);
  }

  /// Fetch tracks for a specific playlist
  Future<TracksResponse> getPlaylistTracks(
    int playlistId, {
    int? offset,
    int? limit,
  }) async {
    final response = await _dio.get(
      '/api/library/playlists/$playlistId/tracks',
      queryParameters: {
        if (offset != null) 'offset': offset,
        if (limit != null) 'limit': limit,
      },
    );
    return TracksResponse.fromJson(response.data);
  }

  /// Fetch a single track by ID
  Future<Track> getTrack(int trackId) async {
    final response = await _dio.get('/api/library/tracks/$trackId');
    return Track.fromJson(response.data);
  }

  /// Download a track file using DAAP protocol
  Future<void> downloadTrack(
    int trackId,
    String savePath, {
    void Function(int, int)? onProgress,
  }) async {
    await _dio.download(
      '/databases/1/items/$trackId.dat',
      savePath,
      queryParameters: {'no_register_playback': '1'},
      options: Options(headers: {'Accept-Codecs': 'mpeg,alac,flac,wav'}),
      onReceiveProgress: onProgress,
    );
  }

  /// Update track statistics on the server
  Future<void> updateTrackStats(
    int trackId, {
    int? playCount,
    int? skipCount,
    int? timePlayed,
    int? timeSkipped,
  }) async {
    final queryParams = <String, dynamic>{};

    if (playCount != null) queryParams['play_count'] = playCount;
    if (skipCount != null) queryParams['skip_count'] = skipCount;
    if (timePlayed != null) queryParams['time_played'] = timePlayed;
    if (timeSkipped != null) queryParams['time_skipped'] = timeSkipped;

    await _dio.put(
      '/api/library/tracks/$trackId',
      queryParameters: queryParams,
    );
  }
}
