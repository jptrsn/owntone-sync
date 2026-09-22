import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:owntone_sync/main.dart' show audioHandler;

import 'sync_provider.dart';
import 'package:owntone_sync/data/repositories/local_database_repository.dart';

class PlayerProvider extends ChangeNotifier {
  static const _eventChannel = MethodChannel('dev.educoder.owntone_sync/events');
  static const _storageChannel = MethodChannel('dev.educoder.owntone_sync/storage');

  final SyncProvider _syncProvider;

  int? _currentPlaylistId;
  bool _isPlaying = false;
  bool _shuffleMode = false;
  bool _repeatMode = false;
  List<SyncedTrack> _queue = [];
  
  int? _currentTrackId;
  Duration _currentTrackPosition = Duration.zero;
  Duration? _currentTrackDuration;

  PlayerProvider({SyncProvider? syncProvider})
      : _syncProvider = syncProvider ?? SyncProvider() {
    _syncProvider.addListener(_onSyncProgress);
    audioHandler!.playbackState.listen(_onPlaybackStateChanged);
    audioHandler!.mediaItem.listen(_onMediaItemChanged);
  }

  int? get currentPlaylistId => _currentPlaylistId;
  bool get isPlaying => _isPlaying;
  bool get shuffleMode => _shuffleMode;
  bool get repeatMode => _repeatMode;
  List<SyncedTrack> get queue => _queue;

  int? get currentTrackId => _currentTrackId;
  Duration get currentTrackPosition => _currentTrackPosition;
  Duration? get currentTrackDuration => _currentTrackDuration;

  SyncedTrack? getCurrentlyPlayingTrack() {
    if (kDebugMode) print('[PlayerProvider] getCurrentlyPlayingTrack: queue=${_queue.length}, _currentTrackId=$_currentTrackId, _isPlaying=$_isPlaying');
    if (_queue.isEmpty) return null;
    try {
      return _queue.firstWhere((t) => t.id == _currentTrackId);
    } catch (e) {
      return _queue.first;
    }
  }

  Future<String?> _resolveContentUri(SyncedTrack track) async {
    if (track.contentUri != null && track.contentUri!.isNotEmpty) {
      return track.contentUri;
    }
    
    try {
      final uri = await _storageChannel.invokeMethod<String>('buildContentUri', {
        'localPath': track.localPath,
      });
      return uri;
    } catch (e) {
      if (kDebugMode) print('Failed to build content URI for ${track.localPath}: $e');
      return null;
    }
  }

  Future<void> playPlaylist(int playlistId, {bool shuffle = false}) async {
    try {
      final tracks = await _syncProvider.getTracksForPlaylist(playlistId) ?? [];
      if (tracks.isEmpty) return;

      _currentPlaylistId = playlistId;
      if (shuffle) {
        _queue = List.from(tracks)..shuffle();
      } else {
        _queue = tracks;
      }
      _currentTrackId = _queue.first.id;
      await _playFirstTrack();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing playlist: $e');
      }
    }
  }

  Future<void> playArtist(String artistName, {bool shuffle = false}) async {
    try {
      final tracks = await _syncProvider.getTracksByArtist(artistName) ?? [];
      if (tracks.isEmpty) return;

      _currentPlaylistId = null;
      if (shuffle) {
        _queue = List.from(tracks)..shuffle();
      } else {
        _queue = tracks;
      }
      _currentTrackId = _queue.first.id;
      await _playFirstTrack();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing artist: $e');
      }
    }
  }

  Future<void> playAlbum(
    String albumName,
    String artistName, {
    bool shuffle = false,
  }) async {
    try {
      final tracks = await _syncProvider.getTracksByAlbum(albumName) ?? [];
      if (tracks.isEmpty) return;

      _currentPlaylistId = null;
      if (shuffle) {
        _queue = List.from(tracks)..shuffle();
      } else {
        _queue = tracks;
      }
      _currentTrackId = _queue.first.id;
      await _playFirstTrack();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing album: $e');
      }
    }
  }

  Future<void> playTrack(int trackId) async {
    try {
      final track = await _syncProvider.getTrackById(trackId);
      if (track == null) return;

      _currentPlaylistId = null;
      _queue = [track];
      _currentTrackId = trackId;
      await _playFirstTrack();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing track: $e');
      }
    }
  }

  Future<void> _playFirstTrack() async {
    if (_queue.isEmpty) return;
    final track = _queue.first;
    final contentUri = await _resolveContentUri(track);
    
    if (contentUri == null || contentUri.isEmpty) {
      if (kDebugMode) print('No content URI for track: ${track.title}');
      return;
    }

    final mediaItem = MediaItem(
      id: track.id.toString(),
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.lengthMs > 0 ? Duration(milliseconds: track.lengthMs) : null,
      artUri: track.artworkPath != null ? Uri.file(track.artworkPath!) : null,
      extras: {'uri': contentUri},
    );

    await audioHandler!.updateQueue([mediaItem]);
    await audioHandler!.playMediaItem(mediaItem);
    _isPlaying = true;
    _currentTrackDuration = track.lengthMs > 0
        ? Duration(milliseconds: track.lengthMs)
        : null;
  }

  Future<void> playAllTracks() async {
    try {
      final tracks = await _syncProvider.getAllTracks() ?? [];
      if (tracks.isEmpty) return;

      _currentPlaylistId = null;
      _queue = tracks;
      _currentTrackId = _queue.first.id;
      await _playFirstTrack();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing all tracks: $e');
      }
    }
  }

  Future<void> playNext(SyncedTrack track) async {
    try {
      int currentIndex =
          _queue.indexWhere((t) => t.id == _currentTrackId);
      if (currentIndex == -1) currentIndex = 0;

      _queue.insert(currentIndex + 1, track);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing next: $e');
      }
    }
  }

  Future<void> addToQueue(SyncedTrack track) async {
    _queue.add(track);
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    try {
      await audioHandler!.seek(position);
      _currentTrackPosition = position;
      await _checkPlayCompletion();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error seeking: $e');
      }
    }
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    notifyListeners();
  }

  void toggleRepeat() {
    _repeatMode = !_repeatMode;
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    notifyListeners();
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    _isPlaying = state.playing;
    _currentTrackPosition = state.position;
    if (kDebugMode) print('[PlayerProvider] playbackState: playing=${state.playing}, processingState=${state.processingState}, position=${state.position}');
    notifyListeners();
  }

  void _onMediaItemChanged(MediaItem? item) {
    if (item != null) {
      _currentTrackId = int.tryParse(item.id);
      _currentTrackDuration = item.duration;
      if (kDebugMode) print('[PlayerProvider] mediaItem changed: id=${item.id}, title=${item.title}');
    }
    notifyListeners();
  }

  Future<void> _checkPlayCompletion() async {
    if (_currentTrackId != null && _currentTrackDuration != null) {
      final percent = _currentTrackPosition.inMilliseconds /
          _currentTrackDuration!.inMilliseconds;
      if (percent >= 0.9) {
        await _recordPlayEvent();
      }
    }
  }

  Future<void> _recordPlayEvent() async {
    try {
      if (_currentTrackId != null) {
        await _eventChannel.invokeMethod('recordPlayEvent', {
          'trackId': _currentTrackId,
          'durationMs': _currentTrackDuration?.inMilliseconds ?? 0
        });
      }
    } catch (e) {
      // Event tracking may be disabled or channel not available
    }
  }

  void _onSyncProgress() {
    // Auto-play disabled - user must explicitly tap play
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onSyncProgress);
    super.dispose();
  }
}
