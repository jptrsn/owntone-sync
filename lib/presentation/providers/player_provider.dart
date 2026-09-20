import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sync_provider.dart';
import 'package:owntone_sync/data/repositories/local_database_repository.dart';

class PlayerProvider extends ChangeNotifier {
  static const _playerChannel = MethodChannel('dev.educoder.owntone_sync/player');

  final SyncProvider _syncProvider;

  int? _currentPlaylistId;
  bool _isPlaying = false;
  bool _shuffleMode = false;
  bool _repeatMode = false;
  int _queueVersion = 0;
  List<SyncedTrack> _queue = [];
  
  int? _currentTrackId;
  Duration _currentTrackPosition = Duration.zero;
  Duration? _currentTrackDuration;

  PlayerProvider({SyncProvider? syncProvider})
      : _syncProvider = syncProvider ?? SyncProvider() {
    _syncProvider.addListener(_onSyncProgress);
  }

  int? get currentPlaylistId => _currentPlaylistId;
  bool get isPlaying => _isPlaying;
  bool get shuffleMode => _shuffleMode;
  bool get repeatMode => _repeatMode;
  int get queueVersion => _queueVersion;
  List<SyncedTrack> get queue => _queue;

  int? get currentTrackId => _currentTrackId;
  Duration get currentTrackPosition => _currentTrackPosition;
  Duration? get currentTrackDuration => _currentTrackDuration;

  Future<void> loadPlaylist(int playlistId) async {
    _currentPlaylistId = playlistId;
    await _buildQueueFromPlaylist(playlistId);
    notifyListeners();
  }

  Future<void> loadAllTracks() async {
    _currentPlaylistId = null;
    await _buildQueueFromAllTracks();
    notifyListeners();
  }

  Future<void> playTrack(int trackId) async {
    try {
      await _playerChannel.invokeMethod('playTrack', {'trackId': trackId});
      _isPlaying = true;
      _currentTrackId = trackId;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing track: $e');
      }
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _playerChannel.invokeMethod('seek', {'positionMs': position.inMilliseconds});
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

  int getQueueTrackCount() {
    return _queue.length;
  }

  SyncedTrack? getCurrentlyPlayingTrack() {
    if (_isPlaying && _currentPlaylistId != null && _queue.isNotEmpty) {
      try {
        return _queue.firstWhere((t) => t.id == _currentPlaylistId);
      } catch (e) {
        return _queue.isNotEmpty ? _queue.first : null;
      }
    }
    return null;
  }

  Future<void> _buildQueueFromPlaylist(int playlistId) async {
    _queue = await _syncProvider.getTracksForPlaylist(playlistId) ?? [];
    _queueVersion = _queue.length;
    await _loadQueueIntoAudioHandler();
  }

  Future<void> _buildQueueFromAllTracks() async {
    _queue = await _syncProvider.getAllTracks() ?? [];
    _queueVersion = _queue.length;
    await _loadQueueIntoAudioHandler();
  }

  Future<void> _loadQueueIntoAudioHandler() async {
    if (_queue.isEmpty) return;

    final uris = _queue
        .where((t) => t.contentUri != null)
        .map((t) => t.contentUri!)
        .toList();

    if (uris.isNotEmpty) {
      try {
        await _playerChannel.invokeMethod('loadQueue', {'uris': uris});
      } catch (e) {
        if (kDebugMode) {
          print('Error loading queue: $e');
        }
      }
    }
  }

  Future<void> _checkPlayCompletion() async {
    if (_currentTrackId != null && _currentTrackDuration != null) {
      final percent = _currentTrackPosition.inMilliseconds / _currentTrackDuration!.inMilliseconds;
      if (percent >= 0.9) {
        await _recordPlayEvent();
      }
    }
  }

  Future<void> _recordPlayEvent() async {
    try {
      if (_currentTrackId != null) {
        await _playerChannel.invokeMethod('recordPlayEvent', {
          'trackId': _currentTrackId,
          'durationMs': _currentTrackDuration?.inMilliseconds ?? 0
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error recording play event: $e');
      }
    }
  }

  Future<void> skipToNext() async {
    try {
      await _playerChannel.invokeMethod('skipToNext');
      if (_currentTrackId != null) {
        await _recordSkipEvent();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error skipping to next: $e');
      }
    }
  }

  Future<void> skipToPrevious() async {
    try {
      await _playerChannel.invokeMethod('skipToPrevious');
      if (_currentTrackId != null) {
        await _recordSkipEvent();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error skipping to previous: $e');
      }
    }
  }

  Future<void> _recordSkipEvent() async {
    try {
      if (_currentTrackId != null) {
        await _playerChannel.invokeMethod('recordSkipEvent', {'trackId': _currentTrackId});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error recording skip event: $e');
      }
    }
  }

  void _onSyncProgress() {
    if (!_syncProvider.isSyncing && _syncProvider.syncProgress == null) {
      if (_currentPlaylistId != null) {
        loadPlaylist(_currentPlaylistId!);
      } else {
        loadAllTracks();
      }
    }
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onSyncProgress);
    super.dispose();
  }
}
